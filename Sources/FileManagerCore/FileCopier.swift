import Foundation
import CFileCopy

public protocol FileCopying: Sendable {
    func copyFile(from source: URL, to destination: URL,
                  progress: @escaping @Sendable (CopyProgress) -> Void,
                  isCancelled: @escaping @Sendable () -> Bool) throws
}

public struct CopyProgress: Sendable {
    public let copiedBytes: Int64
    public let totalBytes: Int64

    public init(copiedBytes: Int64 = 0, totalBytes: Int64 = 0) {
        self.copiedBytes = copiedBytes
        self.totalBytes = totalBytes
    }
    public var fraction: Double {
        totalBytes > 0 ? min(1, max(0, Double(copiedBytes) / Double(totalBytes))) : 0
    }
}

/// Shared between the UI and the worker; the lock protects every access to cancellation.
public final class CopyCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.withLock { cancelled = true } }
    public var isCancelled: Bool { lock.withLock { cancelled } }
}

public extension FileCopying {
    func copyFile(from source: URL, to destination: URL) throws {
        try copyFile(from: source, to: destination, progress: { _ in }, isCancelled: { false })
    }
}

/// The C callback is synchronous; this context is retained for the duration of copyfile.
private final class CopyCallbackContext {
    let total: Int64
    let progress: @Sendable (CopyProgress) -> Void
    let isCancelled: @Sendable () -> Bool
    init(total: Int64, progress: @escaping @Sendable (CopyProgress) -> Void,
         isCancelled: @escaping @Sendable () -> Bool) {
        self.total = total
        self.progress = progress
        self.isCancelled = isCancelled
    }
}

public enum FileCopyError: LocalizedError {
    case sameFile, directoryNotSupported, destinationExists

    public var errorDescription: String? {
        switch self {
        case .sameFile: "The source and destination are the same file. Choose a different name or folder."
        case .directoryNotSupported: "Folder copying is not supported yet. Select a file to copy."
        case .destinationExists: "An item already exists at the destination. Choose a different name; existing items are not overwritten."
        }
    }
}

public struct LocalFileCopier: FileCopying {
    public init() {}

    public func copyFile(from source: URL, to destination: URL,
                         progress: @escaping @Sendable (CopyProgress) -> Void,
                         isCancelled: @escaping @Sendable () -> Bool) throws {
        if isCancelled() { throw CancellationError() }
        let manager = FileManager.default
        guard source.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath() else {
            throw FileCopyError.sameFile
        }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true || values.isSymbolicLink == true else {
            throw FileCopyError.directoryNotSupported
        }
        // attributesOfItem also sees dangling symlinks, unlike fileExists(atPath:).
        if (try? manager.attributesOfItem(atPath: destination.path)) != nil {
            throw FileCopyError.destinationExists
        }
        // Stage in the destination filesystem so a failed copy never exposes a partial
        // destination. moveItem refuses collisions, including ones created during copying.
        let stagingDirectory = destination.deletingLastPathComponent()
            .appendingPathComponent(".commander-copy-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: stagingDirectory) }
        let staged = stagingDirectory.appendingPathComponent("item")
        let total = values.isSymbolicLink == true ? 0 : Int64(values.fileSize ?? 0)
        progress(CopyProgress(totalBytes: total))
        let context = CopyCallbackContext(total: total, progress: progress, isCancelled: isCancelled)
        let raw = Unmanaged.passRetained(context).toOpaque()
        defer { Unmanaged<CopyCallbackContext>.fromOpaque(raw).release() }
        let error = commander_copy_file(source.path, staged.path, { copied, raw in
            guard let raw else { return 1 }
            let context = Unmanaged<CopyCallbackContext>.fromOpaque(raw).takeUnretainedValue()
            if context.isCancelled() { return 1 }
            context.progress(CopyProgress(copiedBytes: copied, totalBytes: context.total))
            return context.isCancelled() ? 1 : 0
        }, raw)
        if isCancelled() { throw CancellationError() }
        if error != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(error)) }
        try manager.moveItem(at: staged, to: destination)
        progress(CopyProgress(copiedBytes: total, totalBytes: total))
    }
}
