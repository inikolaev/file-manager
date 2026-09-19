import Foundation
import EditorCore

// One iteration for latency; repeat in one process to collect useful stack samples.
guard (2...3).contains(CommandLine.arguments.count) else {
    FileHandle.standardError.write(Data("Usage: COMMANDER_PROFILE_EDITOR=1 swift run -c release EditorBenchmark /path/to/file [iterations]\n".utf8))
    exit(2)
}
let iterations = CommandLine.arguments.count == 3 ? Int(CommandLine.arguments[2]) ?? 0 : 1
guard iterations > 0 else { exit(2) }

@inline(never)
func benchmarkLoad(_ url: URL) throws {
    let start = DispatchTime.now().uptimeNanoseconds
    let file = try EditorFile.open(url)
    let document = EditorDocuments.make(file: file)
    let ready = DispatchTime.now().uptimeNanoseconds
    let firstPage = (0..<min(40, document.lineCount)).map { document.text(in: document.lineRange($0)) }
    let pageReady = DispatchTime.now().uptimeNanoseconds
    print(String(format: "document-ready %.6f s", Double(ready - start) / 1e9))
    print(String(format: "first-page-read %.6f s", Double(pageReady - ready) / 1e9))
    print("lines \(document.lineCount), utf16 \(document.length), first-page-utf8 \(firstPage.reduce(0) { $0 + $1.utf8.count })")
}

do {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    for _ in 0..<iterations {
        // Release Foundation temporaries between iterations, like separate loads.
        try autoreleasepool { try benchmarkLoad(url) }
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
