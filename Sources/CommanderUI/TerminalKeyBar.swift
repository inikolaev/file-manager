import AppKit

@MainActor
final class TerminalKeyBar: NSView {
    enum Command: Int, CaseIterable {
        case viewFile = 3, copy = 5, move = 6, createDirectory = 7, delete = 8, quit = 10
        var label: String {
            switch self {
            case .viewFile: "View"
            case .copy: "Copy"
            case .move: "Move"
            case .createDirectory: "Mkdir"
            case .delete: "Delete"
            case .quit: "Quit"
            }
        }
    }
    var onCommand: ((Command) -> Void)?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        TerminalFunctionKeys.draw(in: bounds, labels: Dictionary(uniqueKeysWithValues:
            Command.allCases.map { ($0.rawValue, $0.label) }))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let number = TerminalFunctionKeys.number(at: point, in: bounds), let command = Command(rawValue: number) {
            onCommand?(command)
        }
    }
}
