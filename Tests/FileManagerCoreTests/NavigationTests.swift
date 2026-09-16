import Foundation
import Testing
@testable import FileManagerCore

@Test func rootDoesNotHaveParent() {
    var pane = PaneState(directory: URL(fileURLWithPath: "/"))
    pane.replace(directory: pane.directory, entries: [])
    #expect(pane.parent == nil)
    #expect(pane.rows.isEmpty)
    #expect(pane.selectedRow == nil)
}

@Test func returningToParentSelectsFolderYouLeft() {
    let parent = URL(fileURLWithPath: "/Users")
    let child = parent.appendingPathComponent("someone")
    let entry = FileEntry(url: child, name: "someone", isDirectory: true, isSymbolicLink: false, size: nil, modified: nil)
    var pane = PaneState(directory: child)
    pane.replace(directory: parent, entries: [entry], preferredSelection: child)
    #expect(pane.selectedRow?.url == child)
    #expect(pane.selectedIndex == 1)
    #expect(pane.rows.first?.name == "..")
}

@Test func refreshFallsBackWhenSelectedFileDisappears() {
    let directory = URL(fileURLWithPath: "/Users/someone")
    var pane = PaneState(directory: directory)
    pane.replace(directory: directory, entries: [], preferredSelection: directory.appendingPathComponent("removed"))
    #expect(pane.selectedIndex == 0)
    pane.select(99)
    #expect(pane.selectedRow == nil)
}

@Test func directoryReaderSortsFiltersAndFollowsDirectoryLinks() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    try manager.createDirectory(at: directory.appendingPathComponent("z-folder"), withIntermediateDirectories: false)
    try Data("hello".utf8).write(to: directory.appendingPathComponent("a-file"))
    try Data().write(to: directory.appendingPathComponent(".hidden"))
    try manager.createSymbolicLink(atPath: directory.appendingPathComponent("b-link").path, withDestinationPath: "z-folder")
    let reader = LocalDirectoryReader()
    let entries = try reader.entries(at: directory, showHidden: false)
    #expect(entries.map(\.name) == ["b-link", "z-folder", "a-file"])
    #expect(entries.first?.isSymbolicLink == true)
    #expect(entries.first?.isDirectory == true)
    #expect(entries.last?.size == 5)
    #expect(try reader.entries(at: directory, showHidden: true).count == 4)
}

@Test func nonexistentDirectoryReportsFailure() {
    #expect(throws: (any Error).self) {
        try LocalDirectoryReader().entries(at: URL(fileURLWithPath: "/nonexistent-\(UUID())"), showHidden: false)
    }
}

@Test func panesNavigateIndependently() {
    var left = PaneState(directory: URL(fileURLWithPath: "/Users"))
    let right = PaneState(directory: URL(fileURLWithPath: "/Applications"))
    left.replace(directory: URL(fileURLWithPath: "/tmp"), entries: [])
    #expect(left.directory.path == "/tmp")
    #expect(right.directory.path == "/Applications")
}

@Test func directoryReaderCapturesExecutableAndHiddenMetadata() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("tool")
    try Data("#!/bin/sh\n".utf8).write(to: executable)
    try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    try manager.createSymbolicLink(atPath: directory.appendingPathComponent("tool-link").path, withDestinationPath: "tool")
    try manager.createDirectory(at: directory.appendingPathComponent(".config"), withIntermediateDirectories: false)
    try Data().write(to: directory.appendingPathComponent("plain"))
    let entries = try LocalDirectoryReader().entries(at: directory, showHidden: true)
    #expect(entries.first(where: { $0.name == "tool" })?.isExecutable == true)
    #expect(entries.first(where: { $0.name == "tool-link" })?.isExecutable == true)
    #expect(entries.first(where: { $0.name == "plain" })?.isExecutable == false)
    let hidden = try #require(entries.first(where: { $0.name == ".config" }))
    #expect(hidden.isHidden)
    #expect(hidden.isDirectory)
    #expect(!hidden.isExecutable)
}

@Test func marksToggleIndependentlyOfCursorAndResetOnNavigation() {
    let root = URL(fileURLWithPath: "/example")
    let file = FileEntry(url: root.appendingPathComponent("file"), name: "file", isDirectory: false, isSymbolicLink: false, size: nil, modified: nil)
    let folder = FileEntry(url: root.appendingPathComponent("folder"), name: "folder", isDirectory: true, isSymbolicLink: false, size: nil, modified: nil)
    var pane = PaneState(directory: root)
    pane.replace(directory: root, entries: [folder, file])
    pane.toggleMark() // Parent cannot be marked.
    #expect(pane.markedURLs.isEmpty)
    pane.select(1)
    pane.toggleMark()
    pane.select(2)
    pane.toggleMark()
    #expect(pane.markedURLs.count == 2)
    pane.toggleMark()
    #expect(pane.markedURLs == [folder.url])
    pane.replace(directory: root, entries: [file, folder])
    #expect(pane.markedURLs == [folder.url])
    pane.replace(directory: root, entries: [file])
    #expect(pane.markedURLs.isEmpty)
    pane.select(1)
    pane.toggleMark()
    pane.replace(directory: folder.url, entries: [])
    #expect(pane.markedURLs.isEmpty)
    pane.replace(directory: root, entries: [folder, file])
    #expect(pane.markedURLs.isEmpty)
}

@Test func spaceAdvancesAndShiftRangesShrinkPreservingEarlierMarks() {
    let root = URL(fileURLWithPath: "/example")
    let entries = (0..<5).map { i in
        FileEntry(url: root.appendingPathComponent("file\(i)"), name: "file\(i)", isDirectory: false,
            isSymbolicLink: false, size: nil, modified: nil)
    }
    var pane = PaneState(directory: root)
    pane.replace(directory: root, entries: entries)
    pane.toggleMarkAndAdvance() // Skip parent.
    #expect(pane.markedURLs.isEmpty)
    #expect(pane.selectedIndex == 1)
    pane.toggleMarkAndAdvance()
    pane.toggleMarkAndAdvance()
    #expect(pane.selectedIndex == 3)
    #expect(pane.markedURLs == Set(entries.prefix(2).map(\.url)))
    pane.extendSelection(to: 5)
    #expect(pane.markedURLs.count == 5)
    pane.extendSelection(to: 4)
    #expect(pane.markedURLs == Set(entries.prefix(4).map(\.url)))
    pane.select(5)
    pane.toggleMarkAndAdvance()
    #expect(pane.selectedIndex == 5)
    #expect(pane.markedURLs.count == 5)
    pane.toggleMarkAndAdvance()
    #expect(pane.markedURLs.count == 4)
    pane.select(1)
    pane.extendSelection(to: 0)
    #expect(!pane.isMarked(.parent(root.deletingLastPathComponent())))
}
