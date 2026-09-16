import Foundation
import Testing
@testable import FileManagerCore

@Test func cloudMetadataDistinguishesLocalMissingAndDownloading() {
    #expect(CloudFileStatus.resolve(isUbiquitous: nil, isDownloading: nil, status: nil) == .none)
    #expect(CloudFileStatus.resolve(isUbiquitous: false, isDownloading: false, status: nil) == .none)
    #expect(CloudFileStatus.resolve(isUbiquitous: true, isDownloading: false, status: nil) == .unknown)
    #expect(CloudFileStatus.resolve(isUbiquitous: true, isDownloading: false, status: .notDownloaded) == .notDownloaded)
    #expect(CloudFileStatus.resolve(isUbiquitous: true, isDownloading: true, status: .notDownloaded) == .downloading)
    #expect(CloudFileStatus.resolve(isUbiquitous: true, isDownloading: true, status: .downloaded) == .downloading)
    #expect(CloudFileStatus.resolve(isUbiquitous: true, isDownloading: false, status: .downloaded) == .downloaded)
    #expect(CloudFileStatus.resolve(isUbiquitous: true, isDownloading: false, status: .current) == .downloaded)
}
