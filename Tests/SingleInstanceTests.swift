import Darwin
import Foundation

@main
struct SingleInstanceTests {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count == 2 {
            exit(try SingleInstanceLock.acquire(at: URL(fileURLWithPath: arguments[1])) == nil ? 10 : 0)
        }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let url = scratch.appendingPathComponent("test.lock")
        func contender(_ location: URL) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
            process.arguments = [location.path]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        do {
            let owner = try SingleInstanceLock.acquire(at: url)
            require(owner != nil, "first launch must get the lock")
            let result = try withExtendedLifetime(owner) { try contender(url) }
            require(result == 10, "a different process must not get the existing lock")
        }
        require(try contender(url) == 0, "relaunch must work after the owner exits, even with a stale lock file")
        // Nothing is allowed to follow a link and take a lock on the linked file.
        let link = scratch.appendingPathComponent("link.lock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        do {
            _ = try SingleInstanceLock.acquire(at: link)
            require(false, "a symlink is not an acceptable lock file")
        } catch is POSIXError {}
        print("PASS: cross-process exclusivity, relaunch with stale file, symlink rejection")
    }
}
