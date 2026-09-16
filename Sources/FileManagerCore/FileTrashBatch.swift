import Foundation

/// Reports partial success so panes can refresh after a stopped batch.
public struct FileTrashBatchError: LocalizedError {
    public let completed: [URL]
    public let failedItem: URL
    public let underlying: Error
    public var errorDescription: String? {
        "Could not move \(failedItem.lastPathComponent) to Trash. \(underlying.localizedDescription)\n\n\(completed.count) items moved to Trash before stopping. They can be recovered from Trash."
    }
}

public enum FileTrashBatch {
    public static func run(items: [URL], using trasher: any FileTrashing) throws -> [URL] {
        var completed: [URL] = []
        for item in items {
            do { try trasher.trashItem(at: item) }
            catch { throw FileTrashBatchError(completed: completed, failedItem: item, underlying: error) }
            completed.append(item)
        }
        return completed
    }
}
