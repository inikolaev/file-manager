import AppKit
import Foundation
import Testing
import FileManagerCore
@testable import CommanderUI

@Test @MainActor func viewerDisplaysFilePagesAndRestoresFocusOnEscape() async throws {
    _ = NSApplication.shared
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try (1...100).map { "Line \($0): read-only viewer" }.joined(separator: "\n").write(to: url, atomically: false, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    let pane = TerminalPaneView(name: "Test")
    window.contentView = pane
    window.makeFirstResponder(pane)
    let coordinator = FileViewerCoordinator()
    var closed = false
    coordinator.onClose = { closed = true }
    coordinator.present(url: url, window: window)
    #expect(coordinator.view == nil)
    #expect(window.firstResponder === pane)
    for _ in 0..<200 {
        if coordinator.view != nil { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    let viewer = try #require(coordinator.view)
    #expect(viewer.page?.lines.first?.text == "Line 1: read-only viewer")
    #expect(window.firstResponder === viewer)
    coordinator.request(.end)
    for _ in 0..<200 {
        if viewer.page?.lines.last?.text == "Line 100: read-only viewer" { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(viewer.page?.lines.last?.text == "Line 100: read-only viewer")
    if let output = ProcessInfo.processInfo.environment["COMMANDER_VIEWER_RENDER_PATH"] {
        let bitmap = try #require(viewer.bitmapImageRepForCachingDisplay(in: viewer.bounds))
        viewer.cacheDisplay(in: viewer.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output))
    }
    let f4 = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
        windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 118))
    viewer.keyDown(with: f4)
    for _ in 0..<200 {
        if viewer.page?.mode == .hex { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(viewer.page?.mode == .hex)
    #expect(viewer.page?.lines.first?.text.contains(": ") == true)
    if let output = ProcessInfo.processInfo.environment["COMMANDER_HEX_RENDER_PATH"] {
        let bitmap = try #require(viewer.bitmapImageRepForCachingDisplay(in: viewer.bounds))
        viewer.cacheDisplay(in: viewer.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output))
    }
    viewer.keyDown(with: f4)
    for _ in 0..<200 {
        if viewer.page?.mode == .text { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(viewer.page?.mode == .text)
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
        windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53))
    viewer.keyDown(with: escape)
    #expect(closed)
    #expect(coordinator.view == nil)
    #expect(window.firstResponder === pane)
}

@Test @MainActor func failedViewerOpenKeepsPanesVisibleAndRestoresFocus() async throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    let pane = TerminalPaneView(name: "Test")
    window.contentView = pane
    window.makeFirstResponder(pane)
    let coordinator = FileViewerCoordinator()
    var closed = false
    coordinator.onClose = { closed = true }
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    coordinator.present(url: missing, window: window)
    #expect(coordinator.view == nil)
    for _ in 0..<200 {
        #expect(coordinator.view == nil)
        if pane.subviews.contains(where: { $0 is TerminalOperationDialog }) { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    let dialog = try #require(pane.subviews.compactMap { $0 as? TerminalOperationDialog }.first)
    #expect(!pane.subviews.contains(where: { $0 is TerminalFileViewer }))
    dialog.onDismiss?()
    #expect(closed)
    #expect(window.firstResponder === pane)
    #expect(pane.subviews.isEmpty)
}

@Test @MainActor func closingPendingViewerDoesNotPresentItLater() async throws {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    let pane = TerminalPaneView(name: "Test")
    window.contentView = pane
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("hello".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let coordinator = FileViewerCoordinator()
    coordinator.present(url: url, window: window)
    coordinator.close()
    try await Task.sleep(for: .milliseconds(100))
    #expect(coordinator.view == nil)
    #expect(pane.subviews.isEmpty)
}
