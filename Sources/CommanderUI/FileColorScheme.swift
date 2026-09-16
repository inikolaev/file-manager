import AppKit
import FileManagerCore

/// File-name palette and matching rules. Adjust colors, extensions, and rule
/// precedence here; rendering never performs filesystem queries.
@MainActor
enum FileColorScheme {
    static let directory = TerminalTheme.white
    static let regularFile = TerminalTheme.cyan
    static let hidden = NSColor(srgbRed: 0.35, green: 0.46, blue: 0.61, alpha: 1)
    static let archive = NSColor(srgbRed: 1, green: 0.40, blue: 0.80, alpha: 1)
    static let executable = NSColor(srgbRed: 0.25, green: 0.90, blue: 0.35, alpha: 1)
    static let selected = NSColor.black
    static let marked = TerminalTheme.yellow

    static let archiveExtensions: Set<String> = [
        "zip", "zipx", "7z", "rar", "tar", "gz", "gzip", "bz2", "bzip2",
        "xz", "zst", "zstd", "lz", "lzma", "lz4", "lzo", "z", "tgz",
        "tbz", "tbz2", "txz", "tzst", "cpio", "ar", "jar", "war", "ear",
    ]

    static func color(for row: PaneRow, isSelected: Bool, isMarked: Bool = false) -> NSColor {
        if isMarked { return marked }
        // Selection stays readable. Hidden takes precedence over file categories;
        // directories cannot match archives or executable search permissions.
        if isSelected { return selected }
        guard case .entry(let entry) = row else { return directory }
        if entry.isHidden { return hidden }
        if entry.isDirectory { return directory }
        if archiveExtensions.contains(entry.url.pathExtension.lowercased()) { return archive }
        if entry.isExecutable { return executable }
        return regularFile
    }
}
