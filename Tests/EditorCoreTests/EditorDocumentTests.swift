import Foundation
import Testing
import EditorCore

@Test func editsUpdateLinesAndUndoRestoresSavedRevision() {
    let doc = EditorDocuments.make(text: "one\ntwo\nthree")
    let cursor = EditorSelection(document: doc)
    cursor.set(4)
    cursor.replace(with: "new\n")
    #expect(doc.lineCount == 4)
    #expect(doc.text(in: doc.lineRange(2)) == "two")
    #expect(doc.lineIndex(at: 8) == 2)
    doc.markSaved()
    cursor.select(NSRange(location: 2, length: 8))
    cursor.replace(with: "")
    #expect(doc.isModified)
    #expect(doc.lineCount == 2)
    cursor.undo()
    #expect(!doc.isModified)
    #expect(doc.lineCount == 4)
    cursor.undo()
    #expect(doc.isModified)
    #expect(doc.text(in: NSRange(location: 0, length: doc.length)) == "one\ntwo\nthree")
    cursor.redo()
    #expect(!doc.isModified)
}

@Test func unicodeCursorSelectionAndDeletion() {
    let doc = EditorDocuments.make(text: "a👨‍👩‍👧‍👦e\u{301}\nshort\n")
    let cursor = EditorSelection(document: doc)
    cursor.moveHorizontal(1, extending: false)
    cursor.moveHorizontal(1, extending: false)
    #expect(cursor.column == 2)
    cursor.delete(backward: true)
    #expect(doc.text(in: doc.lineRange(0)) == "ae\u{301}")
    cursor.undo()
    #expect(cursor.column == 2)
    cursor.moveHorizontal(1, extending: false)
    cursor.delete(backward: true)
    #expect(doc.text(in: doc.lineRange(0)) == "a👨‍👩‍👧‍👦")
    cursor.set(doc.length)
    cursor.delete(backward: true)
    #expect(doc.lineCount == 2)
}

@Test func verticalNavigationRetainsColumnAcrossShortLines() {
    let doc = EditorDocuments.make(text: "abcdef\nx\nuvwxyz")
    let cursor = EditorSelection(document: doc)
    cursor.set(5)
    cursor.moveVertical(1, extending: true)
    #expect(cursor.column == 1)
    cursor.moveVertical(1, extending: true)
    #expect(cursor.column == 5)
    #expect(cursor.anchor == 5)
}

@Test func compositionIsOneUndoStep() {
    let doc = EditorDocuments.make(text: "before")
    doc.beginUndoGroup()
    doc.replace(NSRange(location: 6, length: 0), with: "e")
    doc.replace(NSRange(location: 6, length: 1), with: "é")
    doc.endUndoGroup()
    doc.undo()
    #expect(doc.text(in: NSRange(location: 0, length: doc.length)) == "before")
    doc.redo()
    #expect(doc.text(in: NSRange(location: 0, length: doc.length)) == "beforeé")
}

@Test func lineIndexMatchesReferenceAfterManyEdits() {
    let doc = EditorDocuments.make(text: "")
    var reference = ""
    var seed: UInt64 = 7
    func next(_ limit: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1
        return Int((seed >> 32) % UInt64(limit))
    }
    for _ in 0..<700 {
        let length = reference.utf16.count
        let start = next(length + 1)
        let count = next(length - start + 1)
        let text = ["a", "\n", "ab\ncd", "", "\n\n"][next(5)]
        let range = NSRange(location: start, length: count)
        doc.replace(range, with: text)
        reference = (reference as NSString).replacingCharacters(in: range, with: text)
        let lines = reference.components(separatedBy: "\n")
        #expect(doc.lineCount == lines.count)
        for (index, line) in lines.enumerated() {
            #expect(doc.text(in: doc.lineRange(index)) == line)
            #expect(doc.lineIndex(at: doc.lineRange(index).location) == index)
        }
    }
}
