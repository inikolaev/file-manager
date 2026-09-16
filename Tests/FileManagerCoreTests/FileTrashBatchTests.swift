import Foundation
import Testing
@testable import FileManagerCore

private final class PartialTrasher: FileTrashing, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var recorded: [URL] { lock.withLock { urls } }
    func trashItem(at url: URL) throws {
        try lock.withLock {
            if urls.count == 1 { throw CocoaError(.fileWriteNoPermission) }
            urls.append(url)
        }
    }
}

@Test func trashBatchStopsAndReportsCompletedItemsOnFailure() throws {
    let items = ["one", "two", "three"].map { URL(fileURLWithPath: "/" + $0) }
    let trasher = PartialTrasher()
    do {
        _ = try FileTrashBatch.run(items: items, using: trasher)
        Issue.record("Expected second item to fail")
    } catch let error as FileTrashBatchError {
        #expect(error.completed == [items[0]])
        #expect(error.failedItem == items[1])
    }
    #expect(trasher.recorded == [items[0]])
}

@Test func clearingMarksPreservesCursorAndRefreshingPrunesTrashedMarks() {
    let directory = URL(fileURLWithPath: "/example")
    let entries = ["one", "two"].map {
        FileEntry(url: directory.appendingPathComponent($0), name: $0, isDirectory: false,
            isSymbolicLink: false, size: nil, modified: nil)
    }
    var state = PaneState(directory: directory)
    state.replace(directory: directory, entries: entries)
    state.select(1); state.toggleMark()
    state.select(2); state.toggleMark()
    state.replace(directory: directory, entries: [entries[1]], preferredSelection: entries[1].url)
    #expect(state.markedEntries == [entries[1]])
    let cursor = state.selectedIndex
    state.clearMarks()
    #expect(state.markedURLs.isEmpty)
    #expect(state.selectedIndex == cursor)
}
