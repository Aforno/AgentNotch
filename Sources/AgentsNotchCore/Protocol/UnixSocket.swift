import Darwin
import Foundation

public enum AgentSocketError: LocalizedError {
    case pathTooLong
    case systemCall(String, Int32)
    case invalidEvent
    case alreadyInUse

    public var errorDescription: String? {
        switch self {
        case .pathTooLong:
            "The Unix socket path is too long."
        case let .systemCall(call, code):
            "\(call) failed: \(String(cString: strerror(code)))"
        case .invalidEvent:
            "The socket received an invalid event."
        case .alreadyInUse:
            "Another Agent Notch instance is already listening on this socket."
        }
    }
}

public enum AgentSocketLocation {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentnotch", isDirectory: true)
            .appendingPathComponent("agent.sock")
    }
}

public final class UnixSocketServer: @unchecked Sendable {
    public typealias EventHandler = @Sendable (AgentEvent) -> Void

    /// Per-client read deadline so one idle peer cannot stall event delivery.
    private static let clientReadTimeout = timeval(tv_sec: 2, tv_usec: 0)
    private static let maximumConcurrentClients = 64
    /// Serializes check-unlink-bind across instances so concurrent start() calls
    /// cannot both observe not-accepting and orphan each other's listener path.
    private static let startLock = NSLock()

    private let socketURL: URL
    private let maximumPayloadBytes: Int
    private let eventHandler: EventHandler
    private let queue = DispatchQueue(label: "com.agentnotch.socket.listener", qos: .utility)
    /// Concurrent so one slow client read does not block others for the full timeout.
    private let clientsQueue = DispatchQueue(
        label: "com.agentnotch.socket.clients",
        qos: .utility,
        attributes: .concurrent
    )
    private let clientsLock = NSLock()
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    /// Inode of the bound socket path while this instance owns it; used so stop()
    /// only unlinks a path that still belongs to this server.
    private var ownedInode: ino_t?
    /// Accepted client fds still being read; closed on stop so weak-self races cannot leak them.
    private var clientFDs: Set<Int32> = []

    public init(
        socketURL: URL = AgentSocketLocation.defaultURL,
        maximumPayloadBytes: Int = 1_048_576,
        eventHandler: @escaping EventHandler
    ) {
        self.socketURL = socketURL
        self.maximumPayloadBytes = max(1, maximumPayloadBytes)
        self.eventHandler = eventHandler
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard descriptor == -1 else { return }
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if socketURL.standardizedFileURL == AgentSocketLocation.defaultURL.standardizedFileURL {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: socketURL.deletingLastPathComponent().path
            )
        }

        // Hold the process-wide lock across accept-check, unlink, bind, and listen
        // so a second starter cannot unlink a path the first just bound.
        Self.startLock.lock()
        defer { Self.startLock.unlock() }

        // `startLock` coordinates servers in this process. A persistent advisory
        // lock file closes the same check/unlink/bind race when two packaged app
        // processes launch concurrently.
        let lockPath = socketURL.path + ".lock"
        let lockFD = Darwin.open(lockPath, O_CREAT | O_RDWR, mode_t(0o600))
        guard lockFD >= 0 else { throw AgentSocketError.systemCall("open", errno) }
        var processLock = flock()
        processLock.l_type = Int16(F_WRLCK)
        processLock.l_whence = Int16(SEEK_SET)
        defer {
            processLock.l_type = Int16(F_UNLCK)
            _ = Darwin.fcntl(lockFD, F_SETLK, &processLock)
            Darwin.close(lockFD)
        }
        guard Darwin.fcntl(lockFD, F_SETLKW, &processLock) == 0 else {
            throw AgentSocketError.systemCall("fcntl(F_SETLKW)", errno)
        }

        // Never steal a live listener. Only unlink a stale path that nothing accepts.
        if isSocketAccepting(at: socketURL.path) {
            throw AgentSocketError.alreadyInUse
        }
        unlink(socketURL.path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.systemCall("socket", errno) }
        descriptor = fd

        do {
            var address = try makeAddress(path: socketURL.path)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, addressLength(for: socketURL.path))
                }
            }
            guard result == 0 else { throw AgentSocketError.systemCall("bind", errno) }
            guard chmod(socketURL.path, 0o600) == 0 else {
                throw AgentSocketError.systemCall("chmod", errno)
            }
            guard Darwin.listen(fd, 16) == 0 else {
                throw AgentSocketError.systemCall("listen", errno)
            }
            guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
                throw AgentSocketError.systemCall("fcntl", errno)
            }
            guard let inode = inodeOfPath(socketURL.path) else {
                throw AgentSocketError.systemCall("stat", errno)
            }
            ownedInode = inode
        } catch {
            Darwin.close(fd)
            descriptor = -1
            ownedInode = nil
            // Only remove a path we may have just created; do not unlink a peer's socket.
            if !isSocketAccepting(at: socketURL.path) {
                unlink(socketURL.path)
            }
            throw error
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPendingClients() }
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        source.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        descriptor = -1

        clientsLock.lock()
        let openClients = clientFDs
        clientsLock.unlock()
        for client in openClients {
            // Wake blocked readers; the owning reader closes the descriptor
            // exactly once after it leaves read(). This avoids fd-reuse races.
            _ = Darwin.shutdown(client, SHUT_RDWR)
        }

        // Only unlink if the path still refers to the socket we bound.
        if let ownedInode, inodeOfPath(socketURL.path) == ownedInode {
            unlink(socketURL.path)
        }
        ownedInode = nil
    }

    private func acceptPendingClients() {
        while true {
            let client = Darwin.accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return
            }

            // Bound reads so a connected peer that never sends cannot monopolize delivery.
            var timeout = Self.clientReadTimeout
            _ = setsockopt(
                client,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &timeout,
                socklen_t(MemoryLayout<timeval>.size)
            )
            var nosigpipe: Int32 = 1
            _ = setsockopt(
                client,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &nosigpipe,
                socklen_t(MemoryLayout<Int32>.size)
            )

            clientsLock.lock()
            guard clientFDs.count < Self.maximumConcurrentClients else {
                clientsLock.unlock()
                Darwin.close(client)
                continue
            }
            clientFDs.insert(client)
            clientsLock.unlock()

            clientsQueue.async { [weak self] in
                guard let self else {
                    // No reader took ownership before server deallocation.
                    Darwin.close(client)
                    return
                }
                self.read(client: client)
            }
        }
    }

    private func read(client: Int32) {
        defer {
            clientsLock.lock()
            let shouldClose = clientFDs.remove(client) != nil
            clientsLock.unlock()
            if shouldClose {
                Darwin.close(client)
            }
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)

        while data.count <= maximumPayloadBytes {
            let count = Darwin.read(client, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count <= maximumPayloadBytes else { return }
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        for line in data.split(separator: 0x0A) where !line.isEmpty {
            if let event = try? JSONDecoder.agentsNotch.decode(AgentEvent.self, from: Data(line)) {
                eventHandler(event)
            }
        }
    }
}

public enum UnixSocketClient {
    /// Fail-fast budget for local connect/write so a stalled listener cannot
    /// block provider hook timeouts (Codex 3s/5s).
    private static let ioTimeout = timeval(tv_sec: 0, tv_usec: 250_000)

    public static func send(_ event: AgentEvent, to socketURL: URL = AgentSocketLocation.defaultURL) throws {
        var payload = try JSONEncoder.agentsNotch.encode(event)
        payload.append(0x0A)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.systemCall("socket", errno) }
        defer { Darwin.close(fd) }

        // Peer close during write must not kill the hook with SIGPIPE (exit 141).
        var nosigpipe: Int32 = 1
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &nosigpipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw AgentSocketError.systemCall("setsockopt(SO_NOSIGPIPE)", errno)
        }

        var timeout = ioTimeout
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            throw AgentSocketError.systemCall("setsockopt(SO_SNDTIMEO)", errno)
        }
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            throw AgentSocketError.systemCall("setsockopt(SO_RCVTIMEO)", errno)
        }

        var address = try makeAddress(path: socketURL.path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, addressLength(for: socketURL.path))
            }
        }
        guard result == 0 else { throw AgentSocketError.systemCall("connect", errno) }

        try payload.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard written > 0 else { throw AgentSocketError.systemCall("write", errno) }
                offset += written
            }
        }
    }
}

/// Returns true when something is accepting connections on the AF_UNIX path.
private func isSocketAccepting(at path: String) -> Bool {
    guard FileManager.default.fileExists(atPath: path) else { return false }
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { Darwin.close(fd) }

    var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var nosigpipe: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

    guard let address = try? makeAddress(path: path) else { return false }
    var addressCopy = address
    let result = withUnsafePointer(to: &addressCopy) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, addressLength(for: path))
        }
    }
    return result == 0
}

private func inodeOfPath(_ path: String) -> ino_t? {
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    return info.st_ino
}

private func makeAddress(path: String) throws -> sockaddr_un {
    let bytes = Array(path.utf8CString)
    var address = sockaddr_un()
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        throw AgentSocketError.pathTooLong
    }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(addressLength(for: path))
    _ = withUnsafeMutablePointer(to: &address.sun_path) { destination in
        bytes.withUnsafeBytes { source in
            memcpy(UnsafeMutableRawPointer(destination), source.baseAddress!, bytes.count)
        }
    }
    return address
}

private func addressLength(for path: String) -> socklen_t {
    let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 2
    return socklen_t(pathOffset + path.utf8.count + 1)
}
