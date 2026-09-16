import Foundation

public enum PaneRow: Sendable, Equatable {
    case parent(URL)
    case entry(FileEntry)

    public var url: URL {
        switch self {
        case .parent(let url): url
        case .entry(let entry): entry.url
        }
    }
    public var name: String {
        switch self {
        case .parent: ".."
        case .entry(let entry): entry.name
        }
    }
    public var isDirectory: Bool {
        switch self {
        case .parent: true
        case .entry(let entry): entry.isDirectory
        }
    }
}

/// Pure navigation state. A failed directory read leaves the current pane intact.
public struct PaneState: Sendable {
    public private(set) var directory: URL
    public private(set) var directoryModified: Date?
    public private(set) var rows: [PaneRow] = []
    public private(set) var selectedIndex: Int?
    /// Marked entries are independent of the keyboard cursor (selectedIndex).
    public private(set) var markedURLs: Set<URL> = []
    public var markedEntries: [FileEntry] {
        rows.compactMap { row in
            guard case .entry(let entry) = row, isMarked(row) else { return nil }
            return entry
        }
    }

    public mutating func clearMarks() {
        markedURLs.removeAll()
        endRangeSelection()
    }
    private var rangeAnchor: Int?
    private var marksBeforeRange: Set<URL> = []

    public mutating func endRangeSelection() {
        rangeAnchor = nil
        marksBeforeRange = []
    }

    public mutating func extendSelection(to index: Int) {
        guard let current = selectedIndex, rows.indices.contains(index) else { return }
        if rangeAnchor == nil { rangeAnchor = current; marksBeforeRange = markedURLs }
        let anchor = rangeAnchor ?? current
        markedURLs = marksBeforeRange
        for row in rows[min(anchor, index)...max(anchor, index)] {
            if case .entry = row { markedURLs.insert(row.url.standardizedFileURL) }
        }
        selectedIndex = index
    }

    public mutating func toggleMarkAndAdvance() {
        toggleMark()
        if let index = selectedIndex { select(min(index + 1, rows.count - 1)) }
    }

    public func isMarked(_ row: PaneRow) -> Bool {
        guard case .entry = row else { return false }
        return markedURLs.contains(row.url.standardizedFileURL)
    }

    public mutating func toggleMark() {
        endRangeSelection()
        guard let row = selectedRow, case .entry = row else { return }
        let url = row.url.standardizedFileURL
        if !markedURLs.insert(url).inserted { markedURLs.remove(url) }
    }

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    public var selectedRow: PaneRow? {
        guard let selectedIndex, rows.indices.contains(selectedIndex) else { return nil }
        return rows[selectedIndex]
    }

    public var parent: URL? {
        let candidate = directory.deletingLastPathComponent().standardizedFileURL
        return candidate.path == directory.path ? nil : candidate
    }

    public mutating func select(_ index: Int) {
        endRangeSelection()
        selectedIndex = rows.indices.contains(index) ? index : nil
    }

    public mutating func replace(directory: URL, entries: [FileEntry], preferredSelection: URL? = nil, directoryModified: Date? = nil) {
        endRangeSelection()
        if self.directory != directory.standardizedFileURL { markedURLs.removeAll() }
        else { markedURLs.formIntersection(entries.map { $0.url.standardizedFileURL }) }
        self.directory = directory.standardizedFileURL
        self.directoryModified = directoryModified
        rows = (parent.map { [PaneRow.parent($0)] } ?? []) + entries.map(PaneRow.entry)
        selectedIndex = preferredSelection.flatMap { preferred in
            rows.firstIndex { $0.url.standardizedFileURL == preferred.standardizedFileURL }
        } ?? (rows.isEmpty ? nil : 0)
    }
}
