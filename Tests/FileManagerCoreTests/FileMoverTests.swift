import Foundation
import Testing
@testable import FileManagerCore

private func moveFixture() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func nativeMoveRemovesSourceAndPreservesFileIdentity() throws {
    let root = try moveFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let destination = root.appendingPathComponent("renamed")
    try Data("payload".utf8).write(to: source)
    let before = try FileManager.default.attributesOfItem(atPath: source.path)[.systemFileNumber] as? NSNumber
    try LocalFileMover().moveItem(from: source, to: destination)
    #expect(!FileManager.default.fileExists(atPath: source.path))
    #expect(try String(contentsOf: destination, encoding: .utf8) == "payload")
    let after = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? NSNumber
    #expect(before != nil && before == after) // Same-volume rename, not a new copy.
}

@Test func moveRefusesCollisionsSameLocationAndFolderDescendants() throws {
    let root = try moveFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    try Data("source".utf8).write(to: source)
    try Data("existing".utf8).write(to: target)
    let mover = LocalFileMover()
    #expect(throws: FileMoveError.self) { try mover.moveItem(from: source, to: source) }
    #expect(throws: FileMoveError.self) { try mover.moveItem(from: source, to: target) }
    #expect(try String(contentsOf: target, encoding: .utf8) == "existing")
    #expect(try String(contentsOf: source, encoding: .utf8) == "source")
    #expect(throws: FileMoveError.self) { try mover.moveItem(from: root, to: root.appendingPathComponent("nested")) }
}

@Test func movingFoldersAndSymlinksDoesNotFollowTheLink() throws {
    let root = try moveFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    try Data("contents".utf8).write(to: folder.appendingPathComponent("file"))
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "folder")
    let mover = LocalFileMover()
    let newLink = root.appendingPathComponent("new-link")
    try mover.moveItem(from: link, to: newLink)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: newLink.path) == "folder")
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("file").path))
    let newFolder = root.appendingPathComponent("new-folder")
    try mover.moveItem(from: folder, to: newFolder)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(FileManager.default.fileExists(atPath: newFolder.appendingPathComponent("file").path))
    // The now-dangling link itself can still be moved.
    try mover.moveItem(from: newLink, to: link)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "folder")
}

@Test func movePlanTargetsFolderForMultipleFilesAndSupportsRename() throws {
    let root = try moveFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let sources = [URL(fileURLWithPath: "/one"), URL(fileURLWithPath: "/two")]
    let plan = try FileMovePlan.make(sources: sources, destination: root)
    #expect(plan.map(\.destination) == sources.map { root.appendingPathComponent($0.lastPathComponent) })
    let renamed = root.appendingPathComponent("renamed")
    #expect(throws: FileMoveError.self) { try FileMovePlan.make(sources: sources, destination: renamed) }
    #expect(try FileMovePlan.make(sources: [sources[0]], destination: renamed).first?.destination == renamed)
}
