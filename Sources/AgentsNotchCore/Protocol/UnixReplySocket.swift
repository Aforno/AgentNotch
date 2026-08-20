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
    private static let startLock = NSLock()

    private let socketURL: URL
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var listener: Thread?
    private var ownedInode: ino_t?
    private var pending: [UUID: Int32] = [:]

    public init(socketURL: URL = AgentReplySocketLocation.defaultURL) {
        self.socketURL = socketURL
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
        if socketURL.standardizedFileURL == AgentReplySocketLocation.defaultURL.standardizedFileURL {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: socketURL.deletingLastPathComponent().path
            )
        }

        Self.startLock.lock()
        defer { Self.startLock.unlock() }

        if isReplySocketAccepting(at: socketURL.path) {
            throw AgentSocketError.alreadyInUse
        }
        unlink(socketURL.path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.systemCall("socket", errno) }
        descriptor = fd

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
            ownedInode = inode
        } catch {
            Darwin.close(fd)
            descriptor = -1
            ownedInode = nil
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
        listener = thread
        thread.start()
    }

    public func stop() {
        let fd = descriptor
        descriptor = -1
        if fd >= 0 {
            _ = Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
        listener = nil
        lock.lock()
        let clients = Array(pending.values)
        pending.removeAll()
        lock.unlock()
        for client in clients {
            _ = Darwin.shutdown(client, SHUT_RDWR)
            Darwin.close(client)
        }
        if let ownedInode, replyInode(of: socketURL.path) == ownedInode {
            unlink(socketURL.path)
        }
        ownedInode = nil
    }

    public func isPending(_ replyId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending[replyId] != nil
    }

    @discardableResult
    public func submit(_ reply: AgentReply) -> Bool {
        lock.lock()
        let client = pending.removeValue(forKey: reply.replyId)
        lock.unlock()
        guard let client else { return false }
        defer {
            _ = Darwin.shutdown(client, SHUT_RDWR)
            Darwin.close(client)
        }
        guard var payload = try? JSONEncoder.agentsNotch.encode(reply) else { return false }
        payload.append(0x0A)
        return payload.withUnsafeBytes { bytes in
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
    }

    private func acceptLoop() {
        while true {
            let listenFD = descriptor
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
            register(client: client)
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
                Darwin.close(client)
                return
            }
        }
        let line = firstLine(in: data)
        guard let hello = try? JSONDecoder.agentsNotch.decode(AgentReplyHello.self, from: line)
        else {
            Darwin.close(client)
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
            lock.unlock()
            Darwin.close(previous)
        } else {
            lock.unlock()
        }
    }
}

public enum UnixReplyClient {
    public static func awaitReply(
        id: UUID,
        socketURL: URL = AgentReplySocketLocation.defaultURL,
        timeoutSeconds: Int = AgentReplyPolicy.waitSeconds - 10,
        afterHello: (() -> Void)? = nil
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
        afterHello?()

        var wait = timeval(tv_sec: max(1, timeoutSeconds), tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while data.count < 8_192 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if data.contains(0x0A) { break }
            } else {
                return nil
            }
        }
        return try? JSONDecoder.agentsNotch.decode(AgentReply.self, from: firstLine(in: data))
    }
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
