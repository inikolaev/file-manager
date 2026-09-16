import AppKit
import FileManagerCore

enum PaneAction {
    case activate, switchPane, open, parent, copy, move, delete, viewFile, quit, createDirectory
}

/// Coordinates filesystem snapshots and navigation, without knowing how rows are drawn.
@MainActor
final class PaneViewController: NSViewController {
    private(set) var state: PaneState
    private let reader: any DirectoryReading
    private let terminalView: TerminalPaneView
    private var loadTask: Task<Void, Never>?
    private var requestID = UUID()
    private(set) var isLoading = false
    private var status = ""
    private var listingStatus = ""
    private var isError = false
    var showHidden = false
    var onAction: ((PaneAction) -> Void)?

    init(title: String, directory: URL, reader: any DirectoryReading) {
        state = PaneState(directory: directory)
        self.reader = reader
        terminalView = TerminalPaneView(name: title)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = terminalView
        terminalView.onInput = { [weak self] input in
            guard let self else { return }
            switch input {
            case .toggleMark:
                guard !self.isLoading else { return }
                self.state.toggleMark()
                self.render()
            case .extendSelection(let index):
                guard !self.isLoading else { return }
                self.state.extendSelection(to: index)
                self.render()
            case .endRangeSelection: self.state.endRangeSelection()
            case .activate: self.onAction?(.activate)
            case .switchPane: self.onAction?(.switchPane)
            case .open: self.onAction?(.open)
            case .parent: self.onAction?(.parent)
            case .viewFile: self.onAction?(.viewFile)
            case .copy: self.onAction?(.copy)
            case .move: self.onAction?(.move)
            case .createDirectory: self.onAction?(.createDirectory)
            case .delete: self.onAction?(.delete)
            case .quit: self.onAction?(.quit)
            case .select(let index):
                self.state.select(index)
                self.render()
            }
        }
        render()
    }

    private func render() {
        let marks = state.markedURLs.count
        let displayStatus = !isError && !isLoading && marks > 0 ? "\(status) · \(marks) selected" : status
        terminalView.update(state: state, status: displayStatus, isError: isError)
    }
    func setActive(_ active: Bool) { terminalView.isActive = active }
    func focus() { view.window?.makeFirstResponder(terminalView) }

    func load(_ directory: URL, preferredSelection: URL? = nil) {
        _ = view
        loadTask?.cancel()
        let id = UUID()
        requestID = id
        isLoading = true
        isError = false
        status = "Loading…"
        render()
        let reader = self.reader
        let hidden = showHidden
        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    let entries = try reader.entries(at: directory, showHidden: hidden)
                    let modified = try? directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    return (entries, modified)
                }
            }.value
            guard !Task.isCancelled, let self, self.requestID == id else { return }
            self.isLoading = false
            switch result {
            case .success(let (entries, modified)):
                self.state.replace(directory: directory, entries: entries, preferredSelection: preferredSelection, directoryModified: modified)
                self.listingStatus = "\(entries.count) items\(hidden ? " · hidden shown" : "")"
                self.status = self.listingStatus
                self.isError = false
            case .failure(let error):
                self.status = "Cannot open folder: \(error.localizedDescription)"
                self.isError = true
            }
            self.render()
        }
    }

    func restoreListingStatus() { showStatus(listingStatus) }

    func showStatus(_ message: String, isError: Bool = false) {
        status = message
        self.isError = isError
        render()
    }

    func refresh() { load(state.directory, preferredSelection: state.selectedRow?.url) }
    func clearMarks() { state.clearMarks(); render() }

    func openSelected() {
        guard !isLoading, let row = state.selectedRow else { return }
        if row.isDirectory {
            if case .parent = row { goToParent() }
            else { load(row.url) }
        } else {
            status = "File opening is not included in this draft"
            isError = false
            render()
        }
    }

    func goToParent() {
        guard !isLoading, let parent = state.parent else { return }
        load(parent, preferredSelection: state.directory)
    }
}
