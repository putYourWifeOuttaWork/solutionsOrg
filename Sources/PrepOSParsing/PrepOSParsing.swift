import Foundation

/// Document parsers that normalize captured files (txt/md/vtt/srt/pdf/docx) into plain item
/// text (PRD C1.5). Pure where possible; PDF/DOCX use platform/Foundation facilities behind
/// a protocol so the rest stays testable.
///
/// Placeholder namespace — implemented in Phase 1 piece P1-c.
public enum PrepOSParsing {}
