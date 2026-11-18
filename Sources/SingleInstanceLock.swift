import Darwin
import Foundation

final class SingleInstanceLock {
    private let descriptor: Int32

    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }

    static func acquire() throws -> SingleInstanceLock? {
        // Unlike TMPDIR, this directory is stable across Finder and shell launches.
        let key = _CS_DARWIN_USER_TEMP_DIR
        let size = confstr(key, nil, 0)
        guard size > 1 else { throw POSIXError(.EIO) }
        var path = [CChar](repeating: 0, count: size)
        let written = confstr(key, &path, size)
        guard written > 1, written <= size else { throw POSIXError(.EIO) }
        let directory = path.withUnsafeBufferPointer {
            URL(fileURLWithFileSystemRepresentation: $0.baseAddress!, isDirectory: true, relativeTo: nil)
        }
        return try acquire(at: directory.appendingPathComponent("local.monochrome.app.lock"))
    }

    static func acquire(at url: URL) throws -> SingleInstanceLock? {
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var acquired = false
        defer { if !acquired { close(fd) } }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1 else {
            throw POSIXError(.EACCES)
        }
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            if code == EINTR { continue }
            if code == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        // Leave the inode in place so independent launches always lock the same file.
        acquired = true
        return SingleInstanceLock(fd)
    }
}
