import Foundation

/// ASCII control bytes cannot occur inside a UTF-8 multibyte sequence.
/// Detect line endings and NUL while normalizing in one byte scan. LF-only input
/// needs no rewritten buffer; allocate one lazily at the first CR.
enum EditorTextPreparation {
    private struct Scan {
        var normalized: [UInt8] = []
        var needsNormalization = false
        var lineStarts: [Int] = [0]
        var styles: UInt8 = 0 // LF = 1, CRLF = 2, CR = 4
    }

    private static func scan(_ bytes: UnsafeBufferPointer<UInt8>, file: Bool) throws -> Scan {
        var result = Scan()
        var index = 0
        var utf16Offset = 0
        while index < bytes.count {
            // Skip ordinary ASCII eight bytes at a time. The zero-byte test
            // also detects CR/LF after XOR; non-ASCII falls through for UTF-16
            // accounting. Unaligned loads are bounded by the remaining length.
            if !result.needsNormalization, bytes.count - index >= 8 {
                let word = UnsafeRawPointer(bytes.baseAddress! + index).loadUnaligned(as: UInt64.self)
                let high: UInt64 = 0x8080808080808080
                if word & high == 0 && !hasZeroByte(word) &&
                    !hasZeroByte(word ^ 0x0A0A0A0A0A0A0A0A) &&
                    !hasZeroByte(word ^ 0x0D0D0D0D0D0D0D0D) {
                    index += 8
                    utf16Offset += 8
                    continue
                }
            }
            // Consume the rejected block instead of retesting overlapping
            // eight-byte windows after each scalar byte. A CRLF at the boundary
            // may consume one byte beyond blockEnd, which is intentional.
            // Once rewriting starts, the fast path cannot be used for the tail.
            let blockEnd = result.needsNormalization
                ? bytes.count : index + min(8, bytes.count - index)
            while index < blockEnd {
                let byte = bytes[index]
                if file && byte == 0 {
                    throw EditorFile.Failure("The editor supports UTF-8 text files. Use F3 to view binary files or other encodings.")
                }
                if byte == 13 {
                    if !result.needsNormalization {
                        result.normalized.reserveCapacity(bytes.count)
                        result.normalized.append(contentsOf: bytes.prefix(index))
                        result.needsNormalization = true
                    }
                    let pair = index + 1 < bytes.count && bytes[index + 1] == 10
                    result.styles |= pair ? 2 : 4
                    result.normalized.append(10)
                    utf16Offset += 1
                    if file { result.lineStarts.append(utf16Offset) }
                    index += pair ? 2 : 1
                } else {
                    // Each ASCII byte or UTF-8 leading byte contributes UTF-16
                    // units; continuation bytes contribute none. Invalid sequences
                    // are rejected by the decoder before these offsets are used.
                    if byte < 0x80 { utf16Offset += 1 }
                    else if byte >= 0xC0 { utf16Offset += byte >= 0xF0 ? 2 : 1 }
                    if byte == 10 {
                        result.styles |= 1
                        if file { result.lineStarts.append(utf16Offset) }
                    }
                    if result.needsNormalization { result.normalized.append(byte) }
                    index += 1
                }
            }
        }
        if file && result.styles.nonzeroBitCount > 1 {
            throw EditorFile.Failure("This file has mixed line endings. Editing it is not supported yet.")
        }
        return result
    }

    @inline(__always)
    private static func hasZeroByte(_ word: UInt64) -> Bool {
        (word &- 0x0101010101010101) & ~word & 0x8080808080808080 != 0
    }

    static func prepareFile(_ payload: Data) throws -> (text: String, newline: String, lineStarts: [Int]) {
        let result = try payload.withUnsafeBytes { bytes in
            try scan(bytes.bindMemory(to: UInt8.self), file: true)
        }
        // UTF-8 validation is done once by the decoder, after the byte scan.
        let text = result.needsNormalization
            ? String(bytes: result.normalized, encoding: .utf8)
            : String(data: payload, encoding: .utf8)
        guard let text else {
            throw EditorFile.Failure("The editor supports UTF-8 text files. Use F3 to view binary files or other encodings.")
        }
        return (text, result.styles == 2 ? "\r\n" : result.styles == 4 ? "\r" : "\n", result.lineStarts)
    }

    static func normalize(_ text: String) -> String {
        func convert(_ bytes: UnsafeBufferPointer<UInt8>) -> String {
            // Text input is already valid Unicode; mixed endings and NUL are
            // allowed here, matching the existing insert/paste behavior.
            let result = try! scan(bytes, file: false)
            return result.needsNormalization
                ? String(decoding: result.normalized, as: UTF8.self)
                : text
        }
        return text.utf8.withContiguousStorageIfAvailable(convert) ??
            Array(text.utf8).withUnsafeBufferPointer(convert)
    }
}
