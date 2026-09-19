import AppKit

@MainActor
final class TerminalKeyBar: NSView {
    enum Command: Int, CaseIterable {
        case viewFile = 3, copy = 5, move = 6, createDirectory = 7, delete = 8, quit = 10, rename = 106
        var label: String {
            switch self {
            case .viewFile: "View"
            case .copy: "Copy"
            case .move: "Move"
            case .rename: "Rename"
            case .createDirectory: "Mkdir"
            case .delete: "Delete"
            case .quit: "Quit"
            }
        }
    }
    var shiftPressed = false { didSet { needsDisplay = true } }
    static func command(number: Int, shift: Bool) -> Command? {
        shift ? (number == 6 ? .rename : nil) : Command(rawValue: number)
    }
    var labels: [Int: String] {
        Dictionary(uniqueKeysWithValues: (1...10).compactMap { number in
            Self.command(number: number, shift: shiftPressed).map { (number, $0.label) }
        })
    }
    var onCommand: ((Command) -> Void)?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        TerminalFunctionKeys.draw(in: bounds, labels: labels)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let number = TerminalFunctionKeys.number(at: point, in: bounds), let command = Self.command(number: number, shift: event.modifierFlags.contains(.shift)) {
            onCommand?(command)
        }
    }
}
