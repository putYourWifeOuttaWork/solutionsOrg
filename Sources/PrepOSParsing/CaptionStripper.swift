import Foundation

/// Shared caption-cleaning logic for the VTT and SRT parsers, kept as one pure tested
/// function so the timestamp/index/dedup rules are single-source (design note §2, §6).
///
/// It works on blank-line-separated **cue blocks**: it drops the `WEBVTT` header block and any
/// `NOTE` comment block, drops each block's cue identifier/index (everything up to and
/// including the timestamp line), strips inline VTT cue tags, then returns the remaining
/// dialogue joined by `\n` with consecutive duplicate lines collapsed (rolling captions).
enum CaptionStripper {

    /// The caption container format being cleaned.
    enum Format {
        /// WebVTT — `.` millisecond separator, has a `WEBVTT` header and inline cue tags.
        case vtt
        /// SubRip — `,` millisecond separator, numeric cue indices, no header.
        case srt
    }

    /// Extract de-duplicated dialogue text from a raw caption file body.
    static func dialogue(from raw: String, format: Format) -> String {
        var dialogue: [String] = []
        for block in blocks(in: raw) {
            for line in dialogueLines(in: block, format: format) {
                // Collapse consecutive duplicate caption lines (rolling-caption artifact).
                if line == dialogue.last { continue }
                dialogue.append(line)
            }
        }
        return dialogue.joined(separator: "\n")
    }

    /// Split the body into blank-line-separated blocks of non-empty, trimmed lines, dropping
    /// blocks that are empty after trimming.
    private static func blocks(in raw: String) -> [[String]] {
        var blocks: [[String]] = []
        var current: [String] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty { blocks.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks
    }

    /// The dialogue lines of a single cue block, or `[]` for header/`NOTE`/comment blocks.
    private static func dialogueLines(in block: [String], format: Format) -> [String] {
        guard let first = block.first else { return [] }
        // Drop the VTT header block and NOTE comment blocks entirely.
        if format == .vtt, first == "WEBVTT" || first.hasPrefix("WEBVTT ") || first.hasPrefix("NOTE") {
            return []
        }
        // Find the timestamp line; everything after it is dialogue. Lines before it are the
        // cue identifier/index. A block with no timestamp (e.g. stray text) yields nothing.
        guard let tsIndex = block.firstIndex(where: isTimestampLine) else { return [] }

        return block[block.index(after: tsIndex)...].compactMap { line in
            let text = format == .vtt ? stripInlineTags(line) : line
            let cleaned = text.trimmingCharacters(in: .whitespaces)
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    /// A cue timestamp line such as `00:00:01.000 --> 00:00:04.000` (VTT) or with a `,`
    /// millisecond separator for SRT — matched by the presence of the `-->` arrow.
    private static func isTimestampLine(_ line: String) -> Bool {
        line.contains("-->")
    }

    /// Remove inline VTT cue tags: `<v Speaker>`, `</v>`, `<c>`, `<00:00:01.000>`, etc.
    private static func stripInlineTags(_ line: String) -> String {
        var out = ""
        var insideTag = false
        for ch in line {
            if ch == "<" { insideTag = true; continue }
            if ch == ">" { insideTag = false; continue }
            if !insideTag { out.append(ch) }
        }
        return out
    }
}
