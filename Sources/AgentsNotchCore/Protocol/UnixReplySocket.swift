import Darwin
import Foundation

public enum AgentReplySocketLocation {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentsnotch", isDirectory: true)
            .appendingPathComponent("reply.sock")
    }
}

/// Accepts blocked hook processes and writes one `AgentReply` line when the
/// user clicks Deny, Allow, or an option.
public final class UnixReplyServer: @unchecked Sendable {
    private static let helloTimeout = timeval(tv_sec: 2, tv_usec: 0)
    private static let maximumConcurrentClients = 64
    private static let startLock = NSLock()

    private let socketURL: URL
    private let pendingChanged: @Sendable (Set<UUID>) -> Void
    /// Guards `descriptor`, `ownedInode`, `listener`, `pending`, and `clients`.
    /// `descriptor` is also read by the accept thread, so every access must
    /// go through this lock to stay data-race free.
    private let lock = NSLock()
    private let clientsQueue = DispatchQueue(
        label: "com.agentsnotch.reply.clients",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var descriptor: Int32 = -1
    private var listener: Thread?
    private var ownedInode: ino_t?
    private var pending: [UUID: Int32] = [:]
    private var clients: Set<Int32> = []

    public init(
        socketURL: URL = AgentReplySocketLocation.defaultURL,
        pendingChanged: @escaping @Sendable (Set<UUID>) -> Void = { _ in }
    ) {
        self.socketURL = socketURL
        self.pendingChanged = pendingChanged
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard lock.withLock({ descriptor == -1 }) else { return }
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if socketURL.standardizedFileURL == AgentReplySocketLocation.defaultURL.standardizedFileURL {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: socketURL.deletingLastPathComponent().path
            )
        }

        Self.startLock.lock()
        defer { Self.startLock.unlock() }

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

        if isReplySocketAccepting(at: socketURL.path) {
            throw AgentSocketError.alreadyInUse
        }
        unlink(socketURL.path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.systemCall("socket", errno) }

        do {
            var address = try makeReplyAddress(path: socketURL.path)
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, replyAddressLength(for: socketURL.path))
                }
            }
            guard bound == 0 else { throw AgentSocketError.systemCall("bind", errno) }
            guard chmod(socketURL.path, 0o600) == 0 else {
                throw AgentSocketError.systemCall("chmod", errno)
            }
            guard Darwin.listen(fd, 16) == 0 else { throw AgentSocketError.systemCall("listen", errno) }
            guard let inode = replyInode(of: socketURL.path) else {
                throw AgentSocketError.systemCall("stat", errno)
            }
            lock.withLock {
                descriptor = fd
                ownedInode = inode
            }
        } catch {
            Darwin.close(fd)
            lock.withLock {
                descriptor = -1
                ownedInode = nil
            }
            if !isReplySocketAccepting(at: socketURL.path) {
                unlink(socketURL.path)
            }
            throw error
        }

        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        thread.name = "com.agentsnotch.reply.listener"
        thread.qualityOfService = .userInitiated
        lock.withLock { listener = thread }
        thread.start()
    }

    public func stop() {
        let state = lock.withLock { () -> (fd: Int32, inode: ino_t?) in
            let current = descriptor
            let inode = ownedInode
            descriptor = -1
            ownedInode = nil
            listener = nil
            return (current, inode)
        }
        if state.fd >= 0 {
            _ = Darwin.shutdown(state.fd, SHUT_RDWR)
            Darwin.close(state.fd)
        }
        lock.lock()
        let openClients = clients
        let hadPendingReplies = !pending.isEmpty
        pending.removeAll()
        clients.removeAll()
        lock.unlock()
        for client in openClients {
            _ = Darwin.shutdown(client, SHUT_RDWR)
            Darwin.close(client)
        }
        if hadPendingReplies { publishPendingReplies() }
        if let inode = state.inode, replyInode(of: socketURL.path) == inode {
            unlink(socketURL.path)
        }
    }

    public func isPending(_ replyId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending[replyId] != nil
    }

    public var pendingReplyIDs: Set<UUID> {
        lock.withLock { Set(pending.keys) }
    }

    @discardableResult
    public func submit(_ reply: AgentReply) -> Bool {
        lock.lock()
        let client = pending.removeValue(forKey: reply.replyId)
        if let client { clients.remove(client) }
        lock.unlock()
        guard let client else { return false }
        defer {
            _ = Darwin.shutdown(client, SHUT_RDWR)
            Darwin.close(client)
        }
        guard var payload = try? JSONEncoder.agentsNotch.encode(reply) else { return false }
        payload.append(0x0A)
        let delivered = payload.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    client,
                    bytes.baseAddress!.advanced(by: offset),
                    bytes.count - offset
                )
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
        publishPendingReplies()
        return delivered
    }

    private func acceptLoop() {
        while true {
            let listenFD = lock.withLock { descriptor }
            guard listenFD >= 0 else { return }
            let client = Darwin.accept(listenFD, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            var timeout = Self.helloTimeout
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
            lock.lock()
            guard clients.count < Self.maximumConcurrentClients else {
                lock.unlock()
                Darwin.close(client)
                continue
            }
            clients.insert(client)
            lock.unlock()
            clientsQueue.async { [weak self] in self?.register(client: client) }
        }
    }

    private func register(client: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while data.count < 4_096 {
            let count = Darwin.read(client, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if data.contains(0x0A) { break }
            } else {
                closeUnregistered(client)
                return
            }
        }
        let line = firstLine(in: data)
        guard let hello = try? JSONDecoder.agentsNotch.decode(AgentReplyHello.self, from: line)
        else {
            closeUnregistered(client)
            return
        }
        var idle = timeval(tv_sec: AgentReplyPolicy.waitSeconds + 5, tv_usec: 0)
        _ = setsockopt(
            client,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &idle,
            socklen_t(MemoryLayout<timeval>.size)
        )
        lock.lock()
        if let previous = pending.updateValue(client, forKey: hello.replyId) {
            clients.remove(previous)
            lock.unlock()
            _ = Darwin.shutdown(previous, SHUT_RDWR)
            Darwin.close(previous)
        } else {
            lock.unlock()
        }
        guard writeLine(AgentReplyAcknowledgement(), to: client) else {
            dropIfStillPending(replyId: hello.replyId, client: client)
            return
        }
        publishPendingReplies()
        watchDisconnect(replyId: hello.replyId, client: client)
    }

    /// Drops a waiter when the hook closes or times out. SO_RCVTIMEO does not
    /// fire unless someone reads; this read is that someone.
    private func watchDisconnect(replyId: UUID, client: Int32) {
        clientsQueue.async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 1)
            _ = Darwin.read(client, &buffer, 1)
            self?.dropIfStillPending(replyId: replyId, client: client)
        }
    }

    private func dropIfStillPending(replyId: UUID, client: Int32) {
        lock.lock()
        let matches = pending[replyId] == client
        if matches {
            pending.removeValue(forKey: replyId)
            clients.remove(client)
        }
        lock.unlock()
        guard matches else { return }
        _ = Darwin.shutdown(client, SHUT_RDWR)
        Darwin.close(client)
        publishPendingReplies()
    }

    private func closeUnregistered(_ client: Int32) {
        lock.lock()
        let shouldClose = clients.remove(client) != nil
        lock.unlock()
        if shouldClose { Darwin.close(client) }
    }

    private func publishPendingReplies() {
        pendingChanged(pendingReplyIDs)
    }
}

public enum UnixReplyClient {
    /// The default timeout is 10 seconds shorter than the provider hook's
    /// 120-second timeout so the hook process still has time to write its
    /// passive response and exit 0 after a notch wait fails open.
    public static func awaitReply(
        id: UUID,
        socketURL: URL = AgentReplySocketLocation.defaultURL,
        timeoutSeconds: Int = AgentReplyPolicy.waitSeconds - 10,
        afterRegistration: (() -> Void)? = nil
    ) -> AgentReply? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var nosigpipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
        var connectTimeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &connectTimeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &connectTimeout, socklen_t(MemoryLayout<timeval>.size))

        guard var address = try? makeReplyAddress(path: socketURL.path) else { return nil }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, replyAddressLength(for: socketURL.path))
            }
        }
        guard connected == 0 else { return nil }

        guard var hello = try? JSONEncoder.agentsNotch.encode(AgentReplyHello(replyId: id)) else {
            return nil
        }
        hello.append(0x0A)
        let wroteHello: Bool = hello.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    fd,
                    bytes.baseAddress!.advanced(by: offset),
                    bytes.count - offset
                )
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
        guard wroteHello else { return nil }
        guard let ackData = readReplyLine(from: fd, maximumBytes: 1_024),
              let ack = try? JSONDecoder.agentsNotch.decode(AgentReplyAcknowledgement.self, from: ackData),
              ack.registered
        else { return nil }
        afterRegistration?()

        var wait = timeval(tv_sec: max(1, timeoutSeconds), tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

        guard let data = readReplyLine(from: fd, maximumBytes: 8_192) else { return nil }
        return try? JSONDecoder.agentsNotch.decode(AgentReply.self, from: data)
    }
}

private func writeLine<T: Encodable>(_ value: T, to descriptor: Int32) -> Bool {
    guard var payload = try? JSONEncoder.agentsNotch.encode(value) else { return false }
    payload.append(0x0A)
    return payload.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let written = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            guard written > 0 else { return false }
            offset += written
        }
        return true
    }
}

private func readReplyLine(from descriptor: Int32, maximumBytes: Int) -> Data? {
    var data = Data()
    var byte: UInt8 = 0
    while data.count < maximumBytes {
        let count = Darwin.read(descriptor, &byte, 1)
        guard count > 0 else { return nil }
        if byte == 0x0A { return data }
        data.append(byte)
    }
    return nil
}

private func firstLine(in data: Data) -> Data {
    if let index = data.firstIndex(of: 0x0A) {
        return data.prefix(upTo: index)
    }
    return data
}

private func isReplySocketAccepting(at path: String) -> Bool {
    guard FileManager.default.fileExists(atPath: path) else { return false }
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { Darwin.close(fd) }
    var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var nosigpipe: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
    guard var address = try? makeReplyAddress(path: path) else { return false }
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, replyAddressLength(for: path))
        }
    }
    return result == 0
}

private func replyInode(of path: String) -> ino_t? {
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    return info.st_ino
}

private func makeReplyAddress(path: String) throws -> sockaddr_un {
    let bytes = Array(path.utf8CString)
    var address = sockaddr_un()
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        throw AgentSocketError.pathTooLong
    }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(replyAddressLength(for: path))
    _ = withUnsafeMutablePointer(to: &address.sun_path) { destination in
        bytes.withUnsafeBytes { source in
            memcpy(UnsafeMutableRawPointer(destination), source.baseAddress!, bytes.count)
        }
    }
    return address
}

private func replyAddressLength(for path: String) -> socklen_t {
    let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 2
    return socklen_t(pathOffset + path.utf8.count + 1)
}