import Foundation
import Testing
@testable import FileManagerCore

private func withCopyFixture(_ body: (URL, URL) throws -> Void) throws {
    let manager = FileManager.default
    let folder = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source.txt")
    try Data("original contents".utf8).write(to: source)
    try body(folder, source)
}

@Test func copyPreservesSourceAndProducesCompleteDestination() throws {
    try withCopyFixture { (folder: URL, source: URL) throws -> Void in
        let destination = folder.appendingPathComponent("copy with spaces.txt")
        try LocalFileCopier().copyFile(from: source, to: destination)
        #expect(try Data(contentsOf: source) == Data(contentsOf: destination))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["copy with spaces.txt", "source.txt"])
    }
}

@Test func copyDoesNotOverwriteExistingFileOrSource() throws {
    try withCopyFixture { (folder: URL, source: URL) throws -> Void in
        let destination = folder.appendingPathComponent("existing.txt")
        try Data("keep me".utf8).write(to: destination)
        #expect(throws: FileCopyError.self) { try LocalFileCopier().copyFile(from: source, to: destination) }
        #expect(try String(contentsOf: destination, encoding: .utf8) == "keep me")
        #expect(throws: FileCopyError.self) { try LocalFileCopier().copyFile(from: source, to: source) }
        #expect(try String(contentsOf: source, encoding: .utf8) == "original contents")
    }
}

@Test func copyRejectsDirectoriesAndMissingDestinationFolder() throws {
    try withCopyFixture { (folder: URL, source: URL) throws -> Void in
        #expect(throws: FileCopyError.self) { try LocalFileCopier().copyFile(from: folder, to: folder.appendingPathComponent("nested")) }
        #expect(throws: (any Error).self) { try LocalFileCopier().copyFile(from: source, to: folder.appendingPathComponent("missing/file")) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.txt"])
    }
}

@Test func copyPreservesSymlinksAndProtectsDanglingDestination() throws {
    try withCopyFixture { (folder: URL, source: URL) throws -> Void in
        let link = folder.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "source.txt")
        let copy = folder.appendingPathComponent("copied-link")
        try LocalFileCopier().copyFile(from: link, to: copy)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: copy.path) == "source.txt")
        let dangling = folder.appendingPathComponent("dangling")
        try FileManager.default.createSymbolicLink(atPath: dangling.path, withDestinationPath: "missing")
        #expect(throws: FileCopyError.self) { try LocalFileCopier().copyFile(from: source, to: dangling) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: dangling.path) == "missing")
    }
}

private final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CopyProgress] = []
    func record(_ value: CopyProgress) { lock.withLock { values.append(value) } }
    var samples: [CopyProgress] { lock.withLock { values } }
}

@Test func copyReportsBytesAndPreservesPermissionsAndDate() throws {
    try withCopyFixture { (folder: URL, source: URL) throws -> Void in
        let contents = Data(repeating: 42, count: 4 * 1024 * 1024)
        try contents.write(to: source)
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o751, .modificationDate: modified], ofItemAtPath: source.path)
        let capture = ProgressCapture()
        let destination = folder.appendingPathComponent("copy")
        try LocalFileCopier().copyFile(from: source, to: destination,
            progress: { capture.record($0) }, isCancelled: { false })
        #expect(capture.samples.first?.copiedBytes == 0)
        #expect(capture.samples.last?.copiedBytes == Int64(contents.count))
        #expect(capture.samples.allSatisfy { $0.totalBytes == Int64(contents.count) })
        #expect(try Data(contentsOf: destination) == contents)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o751)
        #expect(attributes[.modificationDate] as? Date == modified)
    }
}

@Test func cancellationDuringCopyRemovesStagingAndLeavesSourceUntouched() throws {
    try withCopyFixture { (folder: URL, source: URL) throws -> Void in
        let contents = Data(repeating: 17, count: 8 * 1024 * 1024)
        try contents.write(to: source)
        let destination = folder.appendingPathComponent("copy")
        let token = CopyCancellation()
        #expect(throws: CancellationError.self) {
            try LocalFileCopier().copyFile(from: source, to: destination, progress: {
                if $0.copiedBytes > 0 { token.cancel() }
            }, isCancelled: { token.isCancelled })
        }
        #expect(token.isCancelled)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.txt"])
        #expect(try Data(contentsOf: source) == contents)
    }
}

@Test func zeroByteFileCompletesAndPreCancelledCopyWritesNothing() throws {
    try withCopyFixture { (folder: URL, source: URL) throws -> Void in
        try Data().write(to: source)
        let destination = folder.appendingPathComponent("empty")
        try LocalFileCopier().copyFile(from: source, to: destination)
        #expect(try Data(contentsOf: destination).isEmpty)
        #expect(throws: CancellationError.self) {
            try LocalFileCopier().copyFile(from: source, to: folder.appendingPathComponent("cancelled"),
                progress: { _ in }, isCancelled: { true })
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["empty", "source.txt"])
    }
}
