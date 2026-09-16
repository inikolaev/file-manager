import Foundation
import Darwin

public protocol DirectoryCreating: Sendable {
    func create(name: String, in parent: URL) throws -> URL
}

public enum DirectoryCreationError: LocalizedError {
    case invalidName
    public var errorDescription: String? {
        "Enter a folder name, without slashes. The names . and .. are not allowed."
    }
}

public struct LocalDirectoryCreator: DirectoryCreating {
    public init() {}
    public func create(name: String, in parent: URL) throws -> URL {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw DirectoryCreationError.invalidName
        }
        let target = parent.appendingPathComponent(name, isDirectory: true)
        // mkdir fails for existing files, directories, and symlinks; no overwrite.
        guard mkdir(target.path, 0o777) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return target
    }
}
