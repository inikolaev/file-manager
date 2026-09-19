import Foundation

public enum FileRenameError: LocalizedError {
    case invalidName
    public var errorDescription: String? {
        "Enter a name, without slashes. The names . and .. are not allowed."
    }
}

/// Renames one entry in its existing parent, without following a file symlink.
public struct FileRenamer: Sendable {
    private let mover: any FileMoving
    public init(mover: any FileMoving = LocalFileMover()) { self.mover = mover }

    public func rename(source: URL, name: String) throws -> URL {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw FileRenameError.invalidName
        }
        if name == source.lastPathComponent { return source }
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        try mover.moveItem(from: source, to: destination)
        return destination
    }
}
