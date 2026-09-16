import Foundation

public struct FileEntry: Sendable, Equatable {
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let size: Int64?
    public let modified: Date?
    public let isExecutable: Bool
    public let cloudStatus: CloudFileStatus
    public let isHidden: Bool

    public init(url: URL, name: String, isDirectory: Bool, isSymbolicLink: Bool,
                size: Int64?, modified: Date?, isExecutable: Bool = false, isHidden: Bool = false,
                cloudStatus: CloudFileStatus = .none) {
        self.cloudStatus = cloudStatus
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.size = size
        self.modified = modified
        self.isExecutable = isExecutable
        self.isHidden = isHidden || name.hasPrefix(".")
    }
}

/// Filesystem access is replaceable without coupling navigation to a UI framework.
public protocol DirectoryReading: Sendable {
    func entries(at directory: URL, showHidden: Bool) throws -> [FileEntry]
}

public struct LocalDirectoryReader: DirectoryReading {
    public init() {}

    public func entries(at directory: URL, showHidden: Bool) throws -> [FileEntry] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey,
            .isUbiquitousItemKey, .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingStatusKey,
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys),
            options: showHidden ? [] : [.skipsHiddenFiles]
        )
        return urls.map { url in
            // An individual unreadable or vanished entry must not break the entire listing.
            let values = try? url.resourceValues(forKeys: keys)
            let isLink = values?.isSymbolicLink == true
            let target = isLink ? try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]) : nil
            let isDirectory = target?.isDirectory ?? values?.isDirectory ?? false
            return FileEntry(
                url: url, name: url.lastPathComponent,
                isDirectory: isDirectory,
                isSymbolicLink: isLink,
                size: values?.fileSize.map(Int64.init),
                modified: values?.contentModificationDate,
                isExecutable: !isDirectory && FileManager.default.isExecutableFile(atPath: url.path),
                isHidden: values?.isHidden == true,
                cloudStatus: .resolve(isUbiquitous: values?.isUbiquitousItem,
                    isDownloading: values?.ubiquitousItemIsDownloading, status: values?.ubiquitousItemDownloadingStatus)
            )
        }.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.name < rhs.name : order == .orderedAscending
        }
    }
}
