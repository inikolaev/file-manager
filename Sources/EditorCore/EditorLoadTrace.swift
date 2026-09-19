import Foundation

/// Opt-in diagnostics shared by the app and benchmark; no document contents logged.
final class EditorLoadTrace {
    private let enabled = ProcessInfo.processInfo.environment["COMMANDER_PROFILE_EDITOR"] == "1"
    private var previous = DispatchTime.now().uptimeNanoseconds

    func checkpoint(_ name: String) {
        guard enabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let seconds = Double(now - previous) / 1_000_000_000
        let message = String(format: "editor-load %@ %.6f s\n", name, seconds)
        FileHandle.standardError.write(Data(message.utf8))
        previous = DispatchTime.now().uptimeNanoseconds
    }
}
