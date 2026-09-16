import Foundation

public protocol FileMoving: Sendable {
    func moveItem(from source: URL, to destination: URL) throws
}

public enum FileMoveError: LocalizedError {
    case sameLocation, insideSource, destinationExists, destinationFolderRequired
    public var errorDescription: String? {
        switch self {
        case .sameLocation: "The source and destination are the same location."
        case .insideSource: "A folder cannot be moved inside itself."
        case .destinationExists: "An item already exists at the destination. Existing items are not overwritten."
        case .destinationFolderRequired: "Choose an existing destination folder for multiple selected items."
        }
    }
}

public struct LocalFileMover: FileMoving {
    public init() {}
    public func moveItem(from source: URL, to destination: URL) throws {
        // Resolve parent aliases, but never follow the item itself: move symlinks as links.
        let from = source.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(source.lastPathComponent)
        let to = destination.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(destination.lastPathComponent)
        guard from.standardizedFileURL != to.standardizedFileURL else { throw FileMoveError.sameLocation }
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        if attributes[.type] as? FileAttributeType == .typeDirectory {
            guard from.path != "/", !to.path.hasPrefix(from.path + "/") else { throw FileMoveError.insideSource }
        }
        if (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil {
            throw FileMoveError.destinationExists
        }
        // Native move: rename on the same volume; macOS handles cross-volume relocation.
        try FileManager.default.moveItem(at: source, to: destination)
    }
}

public struct FileMove: Sendable, Equatable {
    public let source: URL
    public let destination: URL
    public init(source: URL, destination: URL) { self.source = source; self.destination = destination }
}

public enum FileMovePlan {
    public static func make(sources: [URL], destination: URL) throws -> [FileMove] {
        let isFolder = (try? destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        guard sources.count <= 1 || isFolder else { throw FileMoveError.destinationFolderRequired }
        return sources.map { FileMove(source: $0,
            destination: isFolder ? destination.appendingPathComponent($0.lastPathComponent) : destination) }
    }
}
