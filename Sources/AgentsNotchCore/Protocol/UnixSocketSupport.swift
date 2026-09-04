import Darwin
import Foundation
import os

/// Shared low-level plumbing for the event and reply Unix-socket servers.
/// The two servers must stay behaviorally identical on bind/lock/probe
/// semantics; security-relevant changes land here once.
enum UnixSocketSupport {
    /// Matches the packaged app's bundle ID so `log stream` filters work for
    /// both the app and the hook relay processes.
    static let subsystem = "com.afonsoferreira.AgentNotch"

    static let logger = Logger(subsystem: subsystem, category: "socket")

    /// Short connect/write deadline for liveness probes and local clients so a
    /// stalled listener cannot block a provider hook's timeout budget.
    static let probeTimeout = timeval(tv_sec: 0, tv_usec: 250_000)

    static func setNosigpipe(_ fd: Int32) {
        var enabled: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    }

    static func applyTimeout(_ fd: Int32, kind: Int32, value: timeval) {
        var timeout = value
        _ = setsockopt(fd, SOL_SOCKET, kind, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Advisory lock serializing check-unlink-bind across concurrent app
    /// launches. Unlocking happens on deinit.
    final class ProcessFileLock {
        private let fd: Int32
        private var processLock = flock()

        init?(path: String) {
            guard let fd = Self.openAndLock(path: path) else { return nil }
            self.fd = fd
        }

        deinit {
            processLock.l_type = Int16(F_UNLCK)
            _ = Darwin.fcntl(fd, F_SETLK, &processLock)
            Darwin.close(fd)
        }

        private static func openAndLock(path: String) -> Int32? {
            let fd = Darwin.open(path, O_CREAT | O_RDWR, mode_t(0o600))
            guard fd >= 0 else {
                logger.error("open(\(path)) failed: \(String(cString: strerror(errno)))")
                return nil
            }
            var lock = flock()
            lock.l_type = Int16(F_WRLCK)
            lock.l_whence = Int16(SEEK_SET)
            guard Darwin.fcntl(fd, F_SETLKW, &lock) == 0 else {
                logger.error("fcntl(F_SETLKW) failed: \(String(cString: strerror(errno)))")
                Darwin.close(fd)
                return nil
            }
            return fd
        }
    }

    static func isPathAccepting(at path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        // Both send and receive deadlines: a peer that accepts but never reads
        // must not hang the probe.
        applyTimeout(fd, kind: SO_SNDTIMEO, value: timeval(tv_sec: 0, tv_usec: 100_000))
        applyTimeout(fd, kind: SO_RCVTIMEO, value: timeval(tv_sec: 0, tv_usec: 100_000))
        setNosigpipe(fd)

        guard let address = try? makeAddress(path: path) else { return false }
        var addressCopy = address
        let result = withUnsafePointer(to: &addressCopy) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, addressLength(for: path))
            }
        }
        return result == 0
    }

    static func inodeOfPath(_ path: String) -> ino_t? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return info.st_ino
    }

    static func makeAddress(path: String) throws -> sockaddr_un {
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

    static func addressLength(for path: String) -> socklen_t {
        let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 2
        return socklen_t(pathOffset + path.utf8.count + 1)
    }

    /// Binds and listens on `path`, refusing to steal a live listener. The
    /// advisory lock closes the check/unlink/bind race between processes.
    /// `tightenDirectory` force-sets 0700 on the parent directory even when it
    /// already existed (used only for the app-owned default location).
    static func bindListener(socketURL: URL, tightenDirectory: Bool) throws -> (fd: Int32, inode: ino_t) {
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if tightenDirectory {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: socketURL.deletingLastPathComponent().path
            )
        }

        let lock = ProcessFileLock(path: socketURL.path + ".lock")
        guard lock != nil else {
            throw AgentSocketError.systemCall("open", errno)
        }

        // Never steal a live listener. Only unlink a stale path that nothing accepts.
        if isPathAccepting(at: socketURL.path) {
            throw AgentSocketError.alreadyInUse
        }
        unlink(socketURL.path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.systemCall("socket", errno) }

        do {
            var address = try makeAddress(path: socketURL.path)
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, addressLength(for: socketURL.path))
                }
            }
            guard bound == 0 else { throw AgentSocketError.systemCall("bind", errno) }
            guard chmod(socketURL.path, 0o600) == 0 else {
                throw AgentSocketError.systemCall("chmod", errno)
            }
            guard Darwin.listen(fd, 16) == 0 else {
                throw AgentSocketError.systemCall("listen", errno)
            }
            guard let inode = inodeOfPath(socketURL.path) else {
                throw AgentSocketError.systemCall("stat", errno)
            }
            return (fd, inode)
        } catch {
            Darwin.close(fd)
            if !isPathAccepting(at: socketURL.path) {
                unlink(socketURL.path)
            }
            throw error
        }
    }
}
