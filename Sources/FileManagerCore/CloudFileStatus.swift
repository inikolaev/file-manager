import Foundation

/// Metadata snapshot only: querying status never requests a download.
public enum CloudFileStatus: Sendable, Equatable {
    case none, unknown, notDownloaded, downloading, downloaded

    static func resolve(isUbiquitous: Bool?, isDownloading: Bool?, status: URLUbiquitousItemDownloadingStatus?) -> Self {
        guard isUbiquitous == true else { return .none }
        if isDownloading == true { return .downloading }
        switch status {
        case .notDownloaded: return .notDownloaded
        case .downloaded, .current: return .downloaded
        default: return .unknown
        }
    }
}
