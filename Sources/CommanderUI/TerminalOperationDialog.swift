import AppKit
import CoreText
import FileManagerCore

/// An in-window modal surface. Only the borderless path editor uses AppKit text
/// editing; borders, labels, buttons, progress, and focus are drawn consistently.
@MainActor
final class TerminalOperationDialog: NSView, NSTextFieldDelegate {
    enum Mode {
        case textInput(title: String, prompt: String, value: String, confirmTitle: String)
        case confirmation(sourceName: String, destination: String, isBatch: Bool = false)
        case progress(sourceName: String, destination: String)
        case error(message: String, title: String = "Copy error")
        case decision(title: String, message: String, confirmTitle: String, destructive: Bool = true)
        case busy(title: String, message: String)
    }
    let mode: Mode
    var onConfirm: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onDismiss: (() -> Void)?
    private(set) var progress = CopyProgress()
    private(set) var cancelling = false
    private let pathField = NSTextField()
    // Text input: 0 = field, 1 = confirm, 2 = Cancel.
    private(set) var focusedControl = 0
    private let gray = NSColor(srgbRed: 0.75, green: 0.75, blue: 0.75, alpha: 1)
    private let red = NSColor(srgbRed: 0.52, green: 0, blue: 0, alpha: 1)
    private var isError: Bool { if case .error = mode { true } else { false } }
    private var isDecision: Bool { if case .decision = mode { true } else { false } }
    private var isBusy: Bool { if case .busy = mode { true } else { false } }
    private var usesRed: Bool {
        if case .decision(_, _, _, let destructive) = mode { return destructive }
        return isError
    }
    private var hasTextInput: Bool {
        switch mode { case .confirmation, .textInput: true; default: false }
    }
    private var foreground: NSColor { usesRed ? TerminalTheme.white : .black }
    private var background: NSColor { usesRed ? red : gray }
    var panelRect: NSRect {
        let width = min(660, max(1, bounds.width - 40))
        let height: CGFloat = if case .progress = mode { 264 } else if isError { 226 } else { 206 }
        return NSRect(x: floor((bounds.width - width) / 2), y: floor((bounds.height - height) / 2), width: width, height: height)
    }
    private var fieldRect: NSRect {
        let panel = panelRect
        return NSRect(x: panel.minX + 26, y: panel.minY + 82, width: panel.width - 52, height: 22)
    }
    private var buttonRects: [NSRect] {
        let panel = panelRect
        if isBusy { return [] }
        if hasTextInput || isDecision {
            return [NSRect(x: panel.midX - 126, y: panel.maxY - 47, width: 112, height: 24),
                    NSRect(x: panel.midX + 14, y: panel.maxY - 47, width: 112, height: 24)]
        }
        return [NSRect(x: panel.midX - 70, y: panel.maxY - 47, width: 140, height: 24)]
    }

    init(mode: Mode) {
        self.mode = mode
        super.init(frame: .zero)
        setAccessibilityElement(false)
        let input: (value: String, label: String)?
        switch mode {
        case .confirmation(_, let destination, _): input = (destination, "Destination file path")
        case .textInput(_, let prompt, let value, _): input = (value, prompt)
        default: input = nil
        }
        if let input {
            pathField.stringValue = input.value
            pathField.isBordered = false
            pathField.drawsBackground = false
            pathField.backgroundColor = TerminalTheme.selection
            pathField.textColor = .black
            pathField.font = TerminalTheme.font
            pathField.focusRingType = .none
            pathField.delegate = self
            pathField.cell?.isScrollable = true
            pathField.setAccessibilityLabel(input.label)
            addSubview(pathField)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        // Keep the native editor at its natural single-line height, centered in
        // the taller painted input area. This also centers selection and caret.
        let input = fieldRect
        let textHeight = min(input.height, ceil(pathField.cell?.cellSize.height ?? TerminalTheme.lineHeight))
        pathField.frame = NSRect(x: input.minX, y: input.midY - textHeight / 2,
            width: input.width, height: textHeight)
        needsDisplay = true
    }

    func focusInitialControl() {
        focusedControl = isDecision ? 1 : 0 // Cancel is the default for deletion.
        if hasTextInput {
            window?.makeFirstResponder(pathField)
            pathField.selectText(nil)
            if let editor = pathField.currentEditor() as? NSTextView {
                editor.insertionPointColor = .black
                editor.selectedTextAttributes = [.backgroundColor: NSColor.black, .foregroundColor: gray]
            }
        } else { window?.makeFirstResponder(self) }
        needsDisplay = true
    }

    func update(progress: CopyProgress) {
        self.progress = progress
        needsDisplay = true
    }

    func showCancelling() {
        cancelling = true
        needsDisplay = true
    }

    private func label(_ text: String, x: CGFloat = 26, y: CGFloat, width: CGFloat? = nil,
                       alignment: NSTextAlignment = .left) {
        let panel = panelRect
        TerminalTheme.text(text, in: NSRect(x: panel.minX + x, y: panel.minY + y,
            width: width ?? panel.width - x - 26, height: 20), color: foreground, alignment: alignment)
    }

    override func draw(_ dirtyRect: NSRect) {
        let panel = panelRect
        NSColor.black.withAlphaComponent(0.65).setFill()
        panel.offsetBy(dx: 10, dy: 10).fill()
        background.setFill()
        panel.fill()
        foreground.setStroke()
        for inset: CGFloat in [15.5, 18.5] {
            let border = NSBezierPath(rect: panel.insetBy(dx: inset, dy: inset))
            border.lineWidth = 1
            border.stroke()
        }
        let title: String
        switch mode {
        case .error(_, let heading), .decision(let heading, _, _, _), .busy(let heading, _), .textInput(let heading, _, _, _): title = heading
        default: title = "Copy"
        }
        let titleWidth = ceil((title as NSString).size(withAttributes: [.font: TerminalTheme.font]).width) + 8
        let titleRect = NSRect(x: panel.midX - titleWidth / 2, y: panel.minY + 7, width: titleWidth, height: 20)
        background.setFill()
        titleRect.fill()
        TerminalTheme.text(title.trimmingCharacters(in: .whitespaces), in: titleRect, color: foreground, alignment: .center)

        switch mode {
        case .textInput(_, let prompt, _, _):
            TerminalTheme.selection.setFill()
            fieldRect.fill()
            label(prompt, y: 62)
        case .confirmation(let name, _, let isBatch):
            TerminalTheme.selection.setFill()
            fieldRect.fill()
            label(isBatch ? "Copy: \(name)" : "Copy file: \(name)", y: 40)
            label(isBatch ? "To folder:" : "To:", y: 62)
            label("Existing files will not be overwritten.", y: 114)
        case .progress(let name, let destination):
            label(cancelling ? "Cancelling…" : "Copying the file", y: 38)
            label(name, y: 60)
            label("To: \(destination)", y: 86)
            let bar = NSRect(x: panel.minX + 26, y: panel.minY + 118, width: panel.width - 112, height: 18)
            NSColor.black.withAlphaComponent(0.15).setFill()
            bar.fill()
            let fraction = progress.fraction
            NSColor.black.setFill()
            NSRect(x: bar.minX, y: bar.minY, width: floor(bar.width * fraction), height: bar.height).fill()
            NSColor.black.setStroke()
            NSBezierPath(rect: bar.insetBy(dx: 0.5, dy: 0.5)).stroke()
            label("\(Int(fraction * 100))%", x: panel.width - 78, y: 118, width: 52, alignment: .right)
            label("\(progress.copiedBytes.formatted()) of \(progress.totalBytes.formatted()) bytes", y: 150)
            if progress.totalBytes > 0 && progress.copiedBytes >= progress.totalBytes && !cancelling {
                label("Finishing file metadata…", y: 174)
            }
        case .error(let message, _), .decision(_, let message, _, _), .busy(_, let message):
            // Wrap errors instead of truncating away the useful failure reason.
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let rect = NSRect(x: panel.minX + 28, y: panel.minY + 42, width: panel.width - 56, height: 116)
            NSGraphicsContext.saveGraphicsState()
            rect.clip()
            (message as NSString).draw(in: rect, withAttributes: [
                .font: TerminalTheme.font, .foregroundColor: foreground, .paragraphStyle: paragraph,
            ])
            NSGraphicsContext.restoreGraphicsState()
        }
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: panel.minX + 19, y: panel.maxY - 61))
        separator.line(to: NSPoint(x: panel.maxX - 19, y: panel.maxY - 61))
        foreground.setStroke()
        separator.stroke()
        let titles: [String]
        switch mode {
        case .confirmation: titles = ["Copy", "Cancel"]
        case .textInput(_, _, _, let confirmTitle): titles = [confirmTitle, "Cancel"]
        case .decision(_, _, let confirmTitle, _): titles = [confirmTitle, "Cancel"]
        case .error: titles = ["OK"]
        case .progress: titles = [cancelling ? "Cancelling…" : "Cancel"]
        case .busy: titles = []
        }
        for (index, rect) in buttonRects.enumerated() {
            let focused = hasTextInput ? focusedControl == index + 1 : isDecision ? focusedControl == index : true
            let title = "[ \(titles[index]) ]"
            let titleSize = (title as NSString).size(withAttributes: [.font: TerminalTheme.font])
            let backgroundRect = rect.insetBy(dx: 2, dy: 2)
            if focused {
                // Paint just beyond the brackets while preserving the generous click target.
                let width = min(rect.width, ceil(titleSize.width) + 4)
                let highlight = NSRect(x: rect.midX - width / 2, y: backgroundRect.minY,
                    width: width, height: backgroundRect.height)
                (usesRed ? TerminalTheme.white : TerminalTheme.selection).setFill()
                highlight.fill()
            }
            drawButtonTitle(title, in: backgroundRect,
                color: focused ? (usesRed ? red : .black) : foreground)
        }
    }

    private func drawButtonTitle(_ title: String, in rect: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: TerminalTheme.font, .foregroundColor: color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: attributes))
        let brackets = CTLineCreateWithAttributedString(NSAttributedString(string: "[]", attributes: attributes))
        let ink = CTLineGetBoundsWithOptions(brackets, .useGlyphPathBounds)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.clip(to: rect)
        // Core Text uses an upward Y axis. Center the visible brackets about the
        // button midpoint, giving every label the same baseline regardless of descenders.
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -width / 2, y: -ink.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func activateButton(_ index: Int) {
        guard !isBusy else { return }
        if hasTextInput || isDecision {
            if index == 0 { onConfirm?(pathField.stringValue) }
            else { onCancel?() }
        } else if isError { onDismiss?() }
        else if !cancelling { onCancel?() }
    }

    private func advanceFocus(backward: Bool) {
        if isDecision {
            focusedControl = 1 - focusedControl
            needsDisplay = true
            return
        }
        guard hasTextInput else { return }
        focusedControl = (focusedControl + (backward ? 2 : 1)) % 3
        if focusedControl == 0 { window?.makeFirstResponder(pathField) }
        else { window?.makeFirstResponder(self) }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard !isBusy else { return }
        switch event.keyCode {
        case 53: if isError { onDismiss?() } else if !cancelling { onCancel?() }
        case 36, 76: activateButton(isDecision ? focusedControl : hasTextInput && focusedControl == 2 ? 1 : 0)
        case 48: advanceFocus(backward: event.modifierFlags.contains(.shift))
        case 123, 124: advanceFocus(backward: event.keyCode == 123)
        default: break
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)): onConfirm?(pathField.stringValue)
        case #selector(NSResponder.cancelOperation(_:)): onCancel?()
        case #selector(NSResponder.insertTab(_:)): advanceFocus(backward: false)
        case #selector(NSResponder.insertBacktab(_:)): advanceFocus(backward: true)
        default: return false
        }
        return true
    }

    func controlTextDidBeginEditing(_ obj: Notification) { focusedControl = 0; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = buttonRects.firstIndex(where: { $0.contains(point) }) { activateButton(index) }
        // All other clicks are consumed, so panes cannot change underneath a dialog.
    }
    override func scrollWheel(with event: NSEvent) {}
}
