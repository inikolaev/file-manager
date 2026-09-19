#!/usr/bin/env python3
"""Isolated scanner ablation: compile an exact copy of today's scanner, never edit the app."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("file", type=Path)
parser.add_argument("--rounds", type=int, default=15)
parser.add_argument("--output", type=Path)
args = parser.parse_args()
if args.rounds < 1:
    parser.error("--rounds must be positive")
root = Path(__file__).resolve().parents[1]
source = (root / "Sources/EditorCore/EditorTextPreparation.swift").read_text()
# Expose the private entry point only in this temporary benchmark copy.
source = source.replace("private struct Scan", "struct Scan")
source = source.replace("    private static func scan(", "    @inline(never)\n    static func scan(")
stub = """
import Foundation
enum EditorFile {
    struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
"""
harness = r"""
import Foundation

// Keep UTF-16 accounting but treat NUL, CR and LF like any other ASCII byte.
// No normalization, newline indexing, or NUL validation. NOT a usable editor scanner.
@inline(never)
func noControls(_ bytes: UnsafeBufferPointer<UInt8>, keepBlockChecks: Bool) -> Int {
    var index = 0
    var utf16Offset = 0
    while index < bytes.count {
        if bytes.count - index >= 8 {
            let word = UnsafeRawPointer(bytes.baseAddress! + index).loadUnaligned(as: UInt64.self)
            if word & 0x8080808080808080 == 0 &&
                (!keepBlockChecks || (!hasZeroByte(word) &&
                !hasZeroByte(word ^ 0x0A0A0A0A0A0A0A0A) &&
                !hasZeroByte(word ^ 0x0D0D0D0D0D0D0D0D))) {
                index += 8
                utf16Offset += 8
                continue
            }
        }
        let end = index + min(8, bytes.count - index)
        while index < end {
            let byte = bytes[index]
            if byte < 0x80 { utf16Offset += 1 }
            else if byte >= 0xC0 { utf16Offset += byte >= 0xF0 ? 2 : 1 }
            index += 1
        }
    }
    return utf16Offset
}
@inline(__always)
func hasZeroByte(_ word: UInt64) -> Bool {
    (word &- 0x0101010101010101) & ~word & 0x8080808080808080 != 0
}
// Compile constant-argument variants so the experiment adds no per-byte mode switch.
@inline(never)
func noControlChecks(_ bytes: UnsafeBufferPointer<UInt8>) -> Int {
    noControls(bytes, keepBlockChecks: false)
}
@inline(never)
func checksWithoutProcessing(_ bytes: UnsafeBufferPointer<UInt8>) -> Int {
    noControls(bytes, keepBlockChecks: true)
}

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let rounds = Int(CommandLine.arguments[2])!
let decoded = String(data: data, encoding: .utf8)!
let expectedUTF16 = decoded.utf16.count
var samples: [String: [Double]] = ["full": [], "checks-only": [], "no-controls": []]
var checksum = 0
try data.withUnsafeBytes { raw in
    let bytes = raw.bindMemory(to: UInt8.self)
    // Verify all variants are actually executing and agree on the unchanged UTF-16 count.
    precondition(noControlChecks(bytes) == expectedUTF16)
    precondition(checksWithoutProcessing(bytes) == expectedUTF16)
    for iteration in 0..<(rounds + 3) {
        let order = iteration % 3 == 0 ? ["full", "checks-only", "no-controls"]
            : iteration % 3 == 1 ? ["no-controls", "full", "checks-only"]
            : ["checks-only", "no-controls", "full"]
        for mode in order {
            let start = DispatchTime.now().uptimeNanoseconds
            let elapsed: Double
            if mode == "full" {
                let result = try EditorTextPreparation.scan(bytes, file: true)
                elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
                // Consume the real output outside the timed section. Keep destruction outside too.
                checksum &+= result.lineStarts.reduce(0, &+)
                checksum &+= result.normalized.count
            } else {
                let count = mode == "no-controls" ? noControlChecks(bytes) : checksWithoutProcessing(bytes)
                elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
                checksum &+= count
            }
            if iteration >= 3 { samples[mode, default: []].append(elapsed) }
        }
    }
}
let output: [String: Any] = [
    "bytes": data.count, "rounds": rounds, "checksum": checksum,
    "milliseconds": samples,
    "medianMilliseconds": samples.mapValues { values in
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
]
print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
"""
with tempfile.TemporaryDirectory(prefix="commander-scan-ablation-") as directory:
    work = Path(directory)
    (work / "Scanner.swift").write_text(stub + source)
    (work / "main.swift").write_text(harness)
    executable = work / "ScanAblation"
    subprocess.run(["swiftc", "-O", "-whole-module-optimization", str(work / "Scanner.swift"),
                    str(work / "main.swift"), "-o", str(executable)], check=True)
    result = subprocess.run([str(executable), str(args.file.resolve()), str(args.rounds)],
                            check=True, capture_output=True, text=True)
    print(result.stdout, end="")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(result.stdout)
