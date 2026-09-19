import AppKit
import FileManagerCore

@MainActor
final class TerminalFileViewer: NSView {
    enum Input { case navigate(ViewerCommand), close, toggleMode }
    var onInput: ((Input) -> Void)?
    let path: String
    private(set) var page: ViewerPage?
    private var horizontalOffset = 0
    private var scrollRemainder: CGFloat = 0
    var onResize: (() -> Void)?
    var visibleRows: Int { min(200, TerminalTextGeometry(bounds: bounds).visibleRows) }

    init(path: String) {
        self.path = path
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.textArea)
        setAccessibilityLabel("Read-only file viewer: \(path)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func update(_ page: ViewerPage) {
        if self.page?.mode != page.mode { horizontalOffset = 0 }
        self.page = page
        setAccessibilityValue(page.lines.map(\.text).joined(separator: "\n"))
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldRows = visibleRows
        super.setFrameSize(newSize)
        needsDisplay = true
        if oldRows != visibleRows { onResize?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        TerminalTheme.background.setFill()
        bounds.fill()
        let line = TerminalTheme.lineHeight
        let header = NSRect(x: 0, y: 0, width: bounds.width, height: line)
        let footer = NSRect(x: 0, y: bounds.height - line, width: bounds.width, height: line)
        TerminalTheme.selection.setFill()
        header.fill()
        let percent = page.map { $0.fileSize == 0 ? 100 : Int(Double($0.endOffset) / Double($0.fileSize) * 100) }
        let position = page.map { "Byte \($0.offset.formatted())/\($0.fileSize.formatted())" } ?? "Opening…"
        let encoding = page?.mode == .hex ? "HEX / ASCII" : "UTF-8"
        let status = "\(encoding)   \(position)   Col \(horizontalOffset + 1)   \(percent.map { "\($0)%" } ?? "")"
        let statusWidth = min(bounds.width * 0.76, ceil((status as NSString).size(withAttributes: [.font: TerminalTheme.font]).width))
        TerminalTheme.text(path, in: NSRect(x: 1, y: 0, width: max(0, bounds.width - statusWidth - 16), height: line), color: .black)
        TerminalTheme.text(status, in: NSRect(x: bounds.width - statusWidth - 2, y: 0,
            width: statusWidth, height: line), color: .black, alignment: .right)
        drawFunctionKeys(in: footer)
        NSGraphicsContext.saveGraphicsState()
        TerminalTextGeometry(bounds: bounds).contentRect.clip()
        if let page {
            for (index, row) in page.lines.prefix(visibleRows).enumerated() {
                let rect = NSRect(x: 1, y: CGFloat(index + 1) * line, width: bounds.width - 2, height: line)
                if rect.intersects(dirtyRect) {
                    TerminalTheme.text(String(row.text.dropFirst(horizontalOffset)), in: rect,
                        color: TerminalTheme.cyan, truncate: .byClipping)
                }
            }
            if page.fileSize == 0 {
                TerminalTheme.text("Empty file", in: NSRect(x: 8, y: line, width: bounds.width - 16, height: line))
            }
        } else {
            TerminalTheme.text("Opening file…", in: NSRect(x: 8, y: line, width: bounds.width - 16, height: line))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawFunctionKeys(in footer: NSRect) {
        TerminalFunctionKeys.draw(in: footer, labels: [3: "Close", 4: page?.mode == .hex ? "Text" : "Hex", 10: "Quit"])
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "r" { onInput?(.navigate(.stay)) }
            else { super.keyDown(with: event) }
            return
        }
        switch event.keyCode {
        case 118: onInput?(.toggleMode) // F4
        case 53, 99, 109: onInput?(.close) // Escape / F3 / F10
        case 125: onInput?(.navigate(.scroll(1)))
        case 126: onInput?(.navigate(.scroll(-1)))
        case 121, 49: onInput?(.navigate(.scroll(visibleRows)))
        case 116: onInput?(.navigate(.scroll(-visibleRows)))
        case 115: onInput?(.navigate(.home))
        case 119: onInput?(.navigate(.end))
        case 123: horizontalOffset = max(0, horizontalOffset - 8); needsDisplay = true
        case 124: horizontalOffset = min(32768, horizontalOffset + 8); needsDisplay = true
        default: break
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let footer = NSRect(x: 0, y: bounds.height - TerminalTheme.lineHeight, width: bounds.width, height: TerminalTheme.lineHeight)
        if let slot = TerminalFunctionKeys.number(at: point, in: footer) {
            if slot == 3 || slot == 10 { onInput?(.close) }
            else if slot == 4 { onInput?(.toggleMode) }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        scrollRemainder += event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? TerminalTheme.lineHeight : 1)
        let steps = Int(scrollRemainder)
        if steps != 0 { onInput?(.navigate(.scroll(-steps))); scrollRemainder -= CGFloat(steps) }
    }
}
