import Foundation
import Testing
@testable import FileManagerCore

@Test func renamePreservesContentsAndRejectsExistingTargets() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("old.txt")
    try Data("content".utf8).write(to: source)
    let renamer = FileRenamer()
    for invalid in ["", " ", ".", "..", "../escape", "a/b", "a\0b"] {
        #expect(throws: FileRenameError.self) { try renamer.rename(source: source, name: invalid) }
    }
    let folder = root.appendingPathComponent("existing")
    try fm.createDirectory(at: folder, withIntermediateDirectories: false)
    #expect(throws: FileMoveError.self) { try renamer.rename(source: source, name: "existing") }
    #expect(!fm.fileExists(atPath: folder.appendingPathComponent("old.txt").path))
    let renamed = try renamer.rename(source: source, name: "new.txt")
    #expect(!fm.fileExists(atPath: source.path))
    #expect(try Data(contentsOf: renamed) == Data("content".utf8))
    #expect(try renamer.rename(source: renamed, name: "new.txt") == renamed)
    let link = root.appendingPathComponent("link")
    try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "new.txt")
    let newLink = try renamer.rename(source: link, name: "renamed-link")
    #expect(try fm.destinationOfSymbolicLink(atPath: newLink.path) == "new.txt")
    let newFolder = try renamer.rename(source: folder, name: "renamed-folder")
    #expect(fm.fileExists(atPath: newFolder.path))
}
