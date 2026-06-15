import Foundation

/// WebVTT caption parser (`.vtt`): strips the `WEBVTT` header, header metadata/`NOTE` blocks,
/// cue identifiers, timestamp lines and inline cue tags; returns de-duplicated dialogue
/// joined by newlines. Delegates the rules to ``CaptionStripper``.
public struct VTTParser: DocumentParser {
    public init() {}

    public var supportedExtensions: [String] { ["vtt"] }

    public func parse(_ data: Data, filename: String) throws -> String {
        let raw = try TextDecoding.string(from: data, filename: filename)
        return CaptionStripper.dialogue(from: raw, format: .vtt)
    }
}

/// SubRip caption parser (`.srt`): strips numeric cue indices and `,`-millisecond timestamp
/// lines; returns de-duplicated dialogue joined by newlines. Delegates to ``CaptionStripper``.
public struct SRTParser: DocumentParser {
    public init() {}

    public var supportedExtensions: [String] { ["srt"] }

    public func parse(_ data: Data, filename: String) throws -> String {
        let raw = try TextDecoding.string(from: data, filename: filename)
        return CaptionStripper.dialogue(from: raw, format: .srt)
    }
}
