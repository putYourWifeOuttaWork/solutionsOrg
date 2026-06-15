# Design note — PrepOSParsing (piece P1-c, PRD C1.5)

Status: **design only** (this note). Implementation lands next, TDD-first.

Target: `PrepOSParsing` (source `Sources/PrepOSParsing/`, tests `Tests/PrepOSParsingTests/`).
Depends on `PrepOSCore` only (per `Package.swift`); no new package dependencies.

## 1. Scope

Normalize captured files into plain item text for the ingestion pipeline
(`capture surface → normalize text (parser) → EmbeddingService.embed`, architecture.md §4).

In scope (PRD C1.5): `.txt`, `.md`, `.vtt`, `.srt`, `.pdf`, `.docx`. Pasted plain text is
handled upstream by the app (no file → no parser), so it is **out of scope** here.

Per-format behavior:
- **TextParser** (`.txt`, `.md`): UTF-8 decode. `.md` is returned **raw** (no markdown
  stripping) — Markdown is meaningful structure for downstream embedding/retrieval.
- **VTTParser** (`.vtt`) / **SRTParser** (`.srt`): strip the `WEBVTT` header and any header
  metadata block, cue identifiers/indices, and timestamp lines (`00:00:01.000 --> 00:00:04.000`
  for VTT; `00:00:01,000 --> 00:00:04,000` for SRT). Return dialogue text joined by `\n`,
  de-duplicated of consecutive caption artifacts (repeated rolling-caption lines collapse to
  one). Inline cue tags (`<v Speaker>`, `<c>`, `<00:00:01.000>`) are stripped from VTT text.
- **PDFParser** (`.pdf`): extract text across all pages via **PDFKit** (`import PDFKit`,
  guarded by `#if canImport(PDFKit)`), pages joined by `\n`.
- **DocxParser** (`.docx`): read Office Open XML via `NSAttributedString` with
  `documentType: .officeOpenXML`, returning its `.string` (guarded by
  `#if canImport(AppKit)` / Foundation availability).

Decoding is **lenient where safe**: parsers attempt UTF-8 first; VTT/SRT/TXT fall back to a
lossy decode only to avoid hard-failing on a stray byte. PDF/DOCX rely on the platform reader.

## 2. Public Swift API

All in the `PrepOSParsing` module. Value/config types are `Sendable`; parsers are stateless
`Sendable` structs. The placeholder `enum PrepOSParsing {}` namespace file and
`PlaceholderTests.swift` are deleted and replaced.

```swift
/// A parser that turns a captured file's bytes into normalized plain item text (PRD C1.5).
/// Implementations are pure/stateless and `Sendable`; platform-backed parsers (PDF/DOCX)
/// hide their framework behind this protocol so the pipeline stays testable.
public protocol DocumentParser: Sendable {
    /// File extensions this parser handles, lowercased, without the leading dot
    /// (e.g. ["txt", "md"]). Used by `ParserRegistry` for dispatch.
    var supportedExtensions: [String] { get }

    /// Decode `data` (a file named `filename`) into normalized plain text.
    /// - Throws: `ParsingError` on decode/format failure or unavailable platform support.
    func parse(_ data: Data, filename: String) throws -> String
}

/// Errors surfaced by the parsing layer.
public enum ParsingError: Error, Sendable, Equatable {
    /// No registered parser handles the file's extension.
    case unsupportedExtension(String)
    /// The filename had no usable extension to dispatch on.
    case missingExtension
    /// The bytes could not be decoded as text in the expected encoding.
    case decodingFailed(filename: String)
    /// The format was structurally invalid (e.g. unreadable PDF/DOCX container).
    case malformedDocument(filename: String, detail: String)
    /// The parser needs a platform framework (PDFKit/AppKit) not available in this build.
    case platformUnavailable(format: String)
}

/// Dispatches a file to the right `DocumentParser` by its (lowercased) extension.
public struct ParserRegistry: Sendable {
    /// Build a registry from explicit parsers. Later parsers win on extension conflicts.
    public init(parsers: [any DocumentParser])

    /// The default registry wiring all built-in parsers (txt/md/vtt/srt/pdf/docx).
    public static func makeDefault() -> ParserRegistry

    /// Returns the parser registered for `ext` (lowercased, no dot), or `nil`.
    public func parser(forExtension ext: String) -> (any DocumentParser)?

    /// Returns the parser for `filename`'s extension, or `nil`.
    public func parser(forFilename filename: String) -> (any DocumentParser)?

    /// Dispatch and parse. Throws `.missingExtension` / `.unsupportedExtension` when no
    /// parser matches, otherwise the chosen parser's error.
    public func parse(_ data: Data, filename: String) throws -> String
}

/// UTF-8 text parser for `.txt` and `.md`. `.md` is returned raw (structure preserved).
public struct TextParser: DocumentParser {
    public init()
    public var supportedExtensions: [String] { ["txt", "md"] }
}

/// WebVTT caption parser (`.vtt`): strips the WEBVTT header, cue ids, timestamp lines and
/// inline cue tags; returns de-duplicated dialogue joined by newlines.
public struct VTTParser: DocumentParser {
    public init()
    public var supportedExtensions: [String] { ["vtt"] }
}

/// SubRip caption parser (`.srt`): strips cue indices and timestamp lines; returns
/// de-duplicated dialogue joined by newlines.
public struct SRTParser: DocumentParser {
    public init()
    public var supportedExtensions: [String] { ["srt"] }
}

/// PDF text extractor (`.pdf`) backed by PDFKit; pages joined by newlines.
public struct PDFParser: DocumentParser {
    public init()
    public var supportedExtensions: [String] { ["pdf"] }
}

/// DOCX (Office Open XML) text extractor backed by `NSAttributedString`.
public struct DocxParser: DocumentParser {
    public init()
    public var supportedExtensions: [String] { ["docx"] }
}
```

Internal (not public, but unit-tested via `@testable`): a shared caption-cleaning helper,
e.g. `enum CaptionStripper { static func dialogue(from raw: String, format: …) -> String }`,
so the VTT/SRT timestamp/index/dedup logic is one pure tested function reused by both parsers.

## 3. Dependencies

- `PrepOSCore` (module import; no new symbols required — parsers are self-contained).
- `Foundation` (Data, String encodings, `NSAttributedString` for DOCX).
- `PDFKit` for `PDFParser`, behind `#if canImport(PDFKit)`. When unavailable, `parse`
  throws `.platformUnavailable(format: "pdf")` rather than failing to compile.
- AppKit/Foundation `NSAttributedString` OOXML reader for `DocxParser`, behind
  `#if canImport(AppKit)`; same `.platformUnavailable` fallback.
- **No `Package.swift` change** — both PDFKit and AppKit are system frameworks on macOS 14,
  no SPM dependency needed.

## 4. Security & Privacy (Constitution)

Trivially compliant and verifiable:
- **No network.** Pure local byte→text transforms; no URLSession, no MCP, no Altify/SFDC
  path anywhere in the target.
- **No secrets.** Nothing read from or written to disk/Keychain; no `SecretStore` usage
  needed. No key material in source or tests.
- **No logging of content.** Parsers return values; they do not log file bytes or text.
- **No write paths.** No Salesforce/Altify tooling is importable from this target (depends
  on `PrepOSCore` only, which has no MCP surface).
- **No audio/transcription.** Parses already-imported transcript files only; never captures.

## 5. Test list (`Tests/PrepOSParsingTests/`)

Pure parsers (txt/md/vtt/srt) are tested exhaustively with **inline string fixtures**
(`Data(string.utf8)`), no fixture files. PDF/DOCX get smoke tests with a documented
limitation where in-memory fixture creation is impractical.

### TextParser
- happy: `.txt` UTF-8 decodes to identical text.
- happy: `.md` is returned **raw** — markdown markers (`#`, `*`, links) preserved verbatim.
- edge: empty file → empty string (no throw).
- edge: multi-byte UTF-8 (emoji / accented chars) round-trips intact.
- boundary: content with a UTF-8 BOM decodes without the BOM leaking into text.

### VTTParser
- happy: standard `WEBVTT` file with header + 3 cues → only the 3 dialogue lines, joined by `\n`.
- edge: header block with `Kind:`/`Language:` metadata and a `NOTE` comment block → all stripped.
- edge: cues carrying numeric identifiers and inline tags (`<v Alex>Hi</v>`,
  `<00:00:02.000>`) → tags removed, speaker text kept.
- edge: rolling/duplicate consecutive caption lines collapse to a single line (dedup).
- boundary: cue with multi-line dialogue → both text lines kept under one cue.
- boundary: empty/whitespace-only VTT (header only, no cues) → empty string.
- edge: timestamp with hours (`01:02:03.000 --> 01:02:05.000`) recognized and stripped.

### SRTParser
- happy: standard `.srt` (index, `00:00:01,000 --> 00:00:04,000`, dialogue) × N → dialogue only.
- edge: comma-millisecond timestamps stripped (SRT uses `,`, not `.`).
- edge: blank-line-separated blocks parsed; trailing blank lines tolerated.
- edge: consecutive duplicate caption lines de-duplicated.
- boundary: single cue with no trailing newline → dialogue extracted.
- boundary: empty input → empty string.

### ParserRegistry
- happy: `parse(_:filename:)` dispatches `report.txt`→TextParser, `a.vtt`→VTTParser,
  `b.srt`→SRTParser by extension and returns the expected text.
- edge: extension matching is **case-insensitive** (`NOTES.MD`, `Clip.VTT`).
- edge: filename with multiple dots (`q3.deal.notes.md`) uses the last segment.
- error: unknown extension (`data.xyz`) → `ParsingError.unsupportedExtension("xyz")`.
- error: filename with no extension (`README`) → `ParsingError.missingExtension`.
- happy: `makeDefault()` resolves a parser for each of txt/md/vtt/srt/pdf/docx.

### PDFParser / DocxParser (smoke + documented limitation)
- PDFParser smoke: if a tiny valid single-page PDF can be synthesized in-memory (via
  `PDFDocument` write-back of a one-page doc), assert extracted text contains the known
  string. **Limitation:** if synthesizing a fixture in a headless CLT/CI run proves
  impractical, fall back to asserting malformed bytes throw `.malformedDocument`, and
  document that real-PDF extraction is covered manually / by the App target's integration
  pass. The chosen approach will be noted in the test file header.
- PDFParser error: non-PDF bytes (`Data("not a pdf".utf8)`) → throws (malformed/decoding),
  never returns garbage silently.
- DocxParser error: non-DOCX bytes (a zip-less blob) → throws `.malformedDocument`.
- DocxParser smoke / limitation: constructing a minimal valid OOXML container in-memory is
  impractical; documented as a limitation, with the malformed-input throw test standing in
  for the negative path and real `.docx` extraction verified manually / in the App target.

### Constitution boundary test
- `testNoNetworkOrWriteSymbolsInParsingSources`: scan `Sources/PrepOSParsing/` and assert it
  contains **no** `URLSession`, no `write.mcp.altify.dev`, and no `altify_`/write-tool tokens
  — proving the parsing layer has no network or Salesforce/Altify write surface (mirrors the
  grep-style boundary tests in testing-strategy.md §3). Source path resolved via `#filePath`.

## 6. Notes / decisions

- `.md` raw (not stripped): downstream embedding/retrieval benefits from preserved structure;
  C1.5 says "parse … into normalized item text," and raw UTF-8 text is the normalized form
  for Markdown. Revisit only if retrieval quality demands stripping.
- VTT/SRT share one tested `CaptionStripper` to keep timestamp/index/dedup logic single-source.
- PDFKit/AppKit are gated behind `canImport` so `swift build` stays green even on a toolchain
  lacking them, throwing `.platformUnavailable` at runtime instead of breaking compilation.
- FAILURE RULE acknowledged: if build + `--filter PrepOSParsingTests` cannot go green, the
  source + test folders revert to the single placeholder namespace file + `PlaceholderTests`.
```
