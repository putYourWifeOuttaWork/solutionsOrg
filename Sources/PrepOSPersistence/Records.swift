import Foundation
import GRDB
import PrepOSCore

// GRDB record conformances for the PRD §6 domain entities. They are declared **here** (not in
// PrepOSCore) so Core stays I/O-free and GRDB-free. The domain types are already `Codable`, so
// GRDB's default Codable column mapping does the work; we only pin the storage conventions:
//
//   • UUID  → `TEXT` (`uuidString`)  via `databaseUUIDEncodingStrategy`.
//   • Date  → `TEXT` (ISO-8601 with fractional seconds) via the shared strategies below.
//             Timestamps round-trip to millisecond precision; sub-millisecond precision from
//             `Date()` is not preserved (standard for DB-stored dates).
//   • Enums → `TEXT` (their `String` rawValue) — automatic, since the enums are `Codable`.
//   • Array/struct fields (`attendees`, `sources`, `candidateBuckets`) → JSON `TEXT`, which is
//             GRDB's default for nested `Codable` values that aren't `DatabaseValueConvertible`.

/// ISO-8601 `DateFormatter` with fractional seconds in UTC, shared by every record's date
/// strategy so `Date` values round-trip without losing sub-second (millisecond) precision.
/// (GRDB's `.formatted` strategies take a `DateFormatter`, hence this rather than
/// `ISO8601DateFormatter`.)
private let iso8601Fractional: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    return f
}()

/// Shared GRDB Codable storage conventions: UUIDs as strings, Dates as fractional ISO-8601.
private protocol PrepOSRecord: FetchableRecord, PersistableRecord, Codable {}

extension PrepOSRecord {
    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .formatted(iso8601Fractional)
    }
    public static var databaseDateDecodingStrategy: DatabaseDateDecodingStrategy {
        .formatted(iso8601Fractional)
    }
}

extension Bucket: PrepOSRecord {
    public static let databaseTableName = "buckets"
}

extension Item: PrepOSRecord {
    public static let databaseTableName = "items"
}

extension BucketLink: PrepOSRecord {
    public static let databaseTableName = "bucket_links"
}

extension Contact: PrepOSRecord {
    public static let databaseTableName = "contacts"
}

extension CalendarEvent: PrepOSRecord {
    public static let databaseTableName = "calendar_events"
}

extension PrepBrief: PrepOSRecord {
    public static let databaseTableName = "prep_briefs"
}

extension TriageItem: PrepOSRecord {
    public static let databaseTableName = "triage_items"
}

extension Asset: PrepOSRecord {
    public static let databaseTableName = "assets"
}

/// A stored embedding for an item (PRD §6.2 note). `vector` is the raw `[Double]` encoded as a
/// `BLOB`; MVP computes similarity in Swift, so no sqlite-vec virtual table yet — the shape is
/// additive for that later swap. Keyed by `itemId` with an `ON DELETE CASCADE` from `items`.
public struct ItemEmbedding: Identifiable, Sendable, Codable, Equatable {
    /// Owning item id — primary key and `id`.
    public var itemId: UUID
    /// The raw embedding vector, stored bit-for-bit in the `vector` BLOB column.
    public var vector: [Double]
    public var id: UUID { itemId }

    public init(itemId: UUID, vector: [Double]) {
        self.itemId = itemId
        self.vector = vector
    }
}

extension ItemEmbedding: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "item_embeddings"

    public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }

    public func encode(to container: inout PersistenceContainer) {
        container["itemId"] = itemId.uuidString
        container["vector"] = VectorBlob.encode(vector)
    }

    public init(row: Row) {
        let raw: Data = row["vector"]
        self.itemId = UUID(uuidString: row["itemId"]) ?? UUID()
        self.vector = VectorBlob.decode(raw)
    }
}

/// Fixed-width little-endian packing of `[Double]` into a `Data` BLOB and back, so the vector
/// round-trips bit-for-bit through SQLite without any JSON/text precision loss.
enum VectorBlob {
    static func encode(_ vector: [Double]) -> Data {
        var data = Data(capacity: vector.count * MemoryLayout<UInt64>.size)
        for value in vector {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func decode(_ data: Data) -> [Double] {
        let stride = MemoryLayout<UInt64>.size
        guard data.count % stride == 0 else { return [] }
        var result: [Double] = []
        result.reserveCapacity(data.count / stride)
        var index = data.startIndex
        while index < data.endIndex {
            var bits: UInt64 = 0
            for byte in 0..<stride {
                bits |= UInt64(data[index + byte]) << (8 * byte)
            }
            result.append(Double(bitPattern: UInt64(littleEndian: bits)))
            index += stride
        }
        return result
    }
}
