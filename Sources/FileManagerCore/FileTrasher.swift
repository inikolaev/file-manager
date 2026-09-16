import Foundation

public protocol FileTrashing: Sendable {
    /// Moves the item itself to Trash. Symlinks are not resolved to their targets.
    func trashItem(at url: URL) throws
}

public enum FileTrashError: LocalizedError {
    case rootNotAllowed
    public var errorDescription: String? { "The filesystem root cannot be moved to Trash." }
}

public struct LocalFileTrasher: FileTrashing {
    public init() {}
    public func trashItem(at url: URL) throws {
        let item = url.standardizedFileURL
        guard item.path != "/" else { throw FileTrashError.rootNotAllowed }
        // No permanent-delete fallback: an unavailable Trash is reported as an error.
        try FileManager.default.trashItem(at: item, resultingItemURL: nil)
    }
}
