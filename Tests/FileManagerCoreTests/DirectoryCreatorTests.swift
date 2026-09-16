import Foundation
import Testing
@testable import FileManagerCore

@Test func directoryCreationValidatesNamesAndRefusesExistingItems() throws {
    let manager = FileManager.default
    let parent = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: parent) }
    let creator = LocalDirectoryCreator()
    for name in ["", " ", ".", "..", "../outside", "a/b", "bad\0name"] {
        #expect(throws: DirectoryCreationError.self) { try creator.create(name: name, in: parent) }
    }
    let created = try creator.create(name: "New Märkä folder", in: parent)
    #expect(try created.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
    #expect(throws: (any Error).self) { try creator.create(name: created.lastPathComponent, in: parent) }
    try Data("keep".utf8).write(to: parent.appendingPathComponent("file"))
    try manager.createSymbolicLink(atPath: parent.appendingPathComponent("link").path, withDestinationPath: "missing")
    for name in ["file", "link"] {
        #expect(throws: (any Error).self) { try creator.create(name: name, in: parent) }
    }
    #expect(try String(contentsOf: parent.appendingPathComponent("file"), encoding: .utf8) == "keep")
}
