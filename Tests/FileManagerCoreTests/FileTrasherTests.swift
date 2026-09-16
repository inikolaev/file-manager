import Foundation
import Testing
@testable import FileManagerCore

@Test func trashRejectsRootAndMissingItems() {
    #expect(throws: FileTrashError.self) { try LocalFileTrasher().trashItem(at: URL(fileURLWithPath: "/")) }
    #expect(throws: (any Error).self) {
        try LocalFileTrasher().trashItem(at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
}
