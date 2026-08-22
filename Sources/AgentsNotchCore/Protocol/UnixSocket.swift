import Darwin
import Foundation
import os

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
        let (fd, inode) = try UnixSocketSupport.bindListener(
            socketURL: socketURL,
            tightenDirectory: socketURL.standardizedFileURL
                == AgentSocketLocation.defaultURL.standardizedFileURL
        )
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
            let error = AgentSocketError.systemCall("fcntl", errno)
            Darwin.close(fd)
            if UnixSocketSupport.inodeOfPath(socketURL.path) == inode,
               !UnixSocketSupport.isPathAccepting(at: socketURL.path)
            {
                unlink(socketURL.path)
            }
            throw error
        }
        descriptor = fd
        ownedInode = inode

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPendingClients() }
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        source.resume()
        let path = socketURL.path
        UnixSocketSupport.logger.info("Event socket listening at \(path)")
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
        if let ownedInode, UnixSocketSupport.inodeOfPath(socketURL.path) == ownedInode {
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
            UnixSocketSupport.applyTimeout(client, kind: SO_RCVTIMEO, value: Self.clientReadTimeout)
            UnixSocketSupport.setNosigpipe(client)

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
            do {
                let event = try JSONDecoder.agentsNotch.decode(AgentEvent.self, from: Data(line))
                eventHandler(event)
            } catch {
                UnixSocketSupport.logger.warning(
                    "Dropped malformed event payload (\(line.count) bytes): \(String(describing: error))"
                )
            }
        }
    }
}

public enum UnixSocketClient {
    public static func send(_ event: AgentEvent, to socketURL: URL = AgentSocketLocation.defaultURL) throws {
        var payload = try JSONEncoder.agentsNotch.encode(event)
        payload.append(0x0A)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.systemCall("socket", errno) }
        defer { Darwin.close(fd) }

        // Peer close during write must not kill the hook with SIGPIPE (exit 141).
        UnixSocketSupport.setNosigpipe(fd)
        UnixSocketSupport.applyTimeout(fd, kind: SO_SNDTIMEO, value: UnixSocketSupport.probeTimeout)
        UnixSocketSupport.applyTimeout(fd, kind: SO_RCVTIMEO, value: UnixSocketSupport.probeTimeout)

        var address = try UnixSocketSupport.makeAddress(path: socketURL.path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, UnixSocketSupport.addressLength(for: socketURL.path))
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
