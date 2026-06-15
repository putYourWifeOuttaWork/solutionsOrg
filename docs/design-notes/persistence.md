# Design note — PrepOSPersistence (piece "persistence", PRD §6, C8.1/C8.4)

Status: **design only** (this note). Implementation lands next, TDD-first (XCTest).

Target: `PrepOSPersistence` (source `Sources/PrepOSPersistence/`, tests
`Tests/PrepOSPersistenceTests/`). Per `Package.swift` (which this piece must **not** edit)
it depends on `PrepOSCore` and the `GRDB` product (already added, resolved at 7.11.0). No
new package dependencies. The only at-rest crypto uses Apple's **CryptoKit** (system
framework, no SPM dep). No network. Secrets only via the `SecretStore` protocol from
`PrepOSCore`.

The placeholder namespace file `Sources/PrepOSPersistence/PrepOSPersistence.swift`
(`enum PrepOSPersistence {}`) and `Tests/PrepOSPersistenceTests/PlaceholderTests.swift` are
deleted and replaced with the code below.

## 1. Scope

This piece is the **on-device system of record**: the GRDB schema, record conformances,
repositories, and whole-file AES-GCM encryption-at-rest (PRD §6, C8.1, C8.4). It is the
one place that performs disk I/O for domain data.

In scope:
- A **`DatabaseMigrator`** creating tables for every §6 entity (`buckets`, `items`,
  `bucket_links`, `contacts`, `calendar_events`, `prep_briefs`, `triage_items`, `assets`)
  plus an **`item_embeddings`** table (`itemId` PK, `vector` BLOB). Storage conventions:
  UUIDs as `TEXT`, enums via their `String` `rawValue`, and composite/array fields
  (`attendees`, `sources`, `candidateBuckets`) as JSON `TEXT` columns.
- **GRDB record conformances** (`FetchableRecord` + `PersistableRecord`, plus
  `TableRecord`/`Codable` column mapping) for the §6 entities — **defined in this target**,
  so `PrepOSCore` stays I/O-free (no GRDB import in Core).
- **Repositories** (`BucketRepository`, `ItemRepository`, plus thin repos for the rest)
  offering CRUD and the key queries: items in a bucket; pending triage items.
- **`EncryptedDatabase`** — whole-file AES-GCM encryption (CryptoKit), key sourced from
  `SecretStore` (`SecretKey.databaseKey`), generated on first use and **never** written to
  disk in plaintext. Decrypt to a plaintext **working file** for GRDB, re-encrypt on
  persist/close.
- **Encrypted export/backup** (C8.4): `exportEncrypted(to:)` producing an AES-GCM blob.

Explicitly **out of scope** for this piece (later pieces / other targets):
- `sqlite-vec` virtual table / native vector search — MVP stores raw vectors in the
  `item_embeddings` BLOB column; similarity is computed in Swift in `PrepOSBucketing`
  (per `Package.swift` comment). The schema is shaped so a sqlite-vec swap is additive.
- Prototype storage, re-clustering, and any bucketing logic (`PrepOSBucketing`).
- Altify reads, Graph sync, brief composition (other targets).

### Constitution posture (inviolable)
- **Encryption at rest (Constitution §2, C8.1).** The database file persisted to disk is an
  AES-GCM ciphertext blob. The symmetric key is fetched from `SecretStore`
  (`SecretKey.databaseKey`); if absent it is generated with
  `SymmetricKey(size: .bits256)`, persisted **only** via `SecretStore.set` (Keychain in the
  app, in-memory fake in tests), and never logged or written to disk in plaintext.
- **Plaintext-working-file tradeoff (documented in code).** GRDB/SQLite needs a real file
  handle, so on open we decrypt the ciphertext to a working file, operate, then re-encrypt
  and atomically replace the ciphertext on persist/close. The working file is created with
  owner-only permissions (`0o600`) under a caller-supplied directory (the app passes a
  sandbox/`FileVault`-protected location) and removed on close. This window is the
  deliberate, documented tradeoff for using SQLite without SQLCipher in the MVP; FileVault
  is the defense-in-depth backstop (Constitution §2). A code comment on `EncryptedDatabase`
  states this explicitly.
- **Secrets only via `SecretStore`.** This target never touches the Keychain directly and
  holds no key material in any persisted field. The key bytes never appear in the
  ciphertext output (asserted by a boundary test).
- **No Salesforce/Altify write paths, no network.** Persistence is local disk I/O only; it
  imports neither networking nor any MCP/Altify surface. A Constitution boundary test
  asserts the module exposes no network/write affordance and that secrets flow only through
  `SecretStore`.

## 2. Public Swift API

All in the `PrepOSPersistence` module. Value types remain the `PrepOSCore` ones
(`Sendable`/`Codable`); GRDB conformances are added **here** via extensions so Core stays
I/O-free. Repositories are `Sendable` and serialize writes through GRDB's `DatabaseQueue`.
Doc-comments match the PrepOSCore style.

```swift
import Foundation
import GRDB
import CryptoKit
import PrepOSCore

// MARK: - Errors

/// Failures from the persistence layer (typed per target, per architecture.md §6).
public enum PersistenceError: Error, Sendable, Equatable {
    /// The on-disk ciphertext failed AES-GCM authentication (tampered or wrong key).
    case decryptionFailed
    /// The database key was neither found in nor storable via `SecretStore`.
    case missingDatabaseKey
    /// A working-file / filesystem operation failed.
    case io(String)
}

// MARK: - Schema / migrations

/// Owns the GRDB schema for every PRD §6 entity plus `item_embeddings`. UUIDs are `TEXT`,
/// enums are their `String` rawValues, and composite fields are JSON `TEXT` columns.
public enum PrepOSSchema {
    /// A configured `DatabaseMigrator` with one registered migration, `"v1"`, creating all
    /// tables. Idempotent — safe to run on every open.
    public static func migrator() -> DatabaseMigrator

    /// Run all pending migrations on `writer` (a `DatabaseQueue`/`DatabasePool`).
    public static func migrate(_ writer: any DatabaseWriter) throws
}

// MARK: - Record conformances (defined here; Core stays GRDB-free)

extension Bucket:        FetchableRecord, PersistableRecord {}
extension Item:          FetchableRecord, PersistableRecord {}
extension BucketLink:    FetchableRecord, PersistableRecord {}
extension Contact:       FetchableRecord, PersistableRecord {}
extension CalendarEvent: FetchableRecord, PersistableRecord {}
extension PrepBrief:     FetchableRecord, PersistableRecord {}
extension TriageItem:    FetchableRecord, PersistableRecord {}
extension Asset:         FetchableRecord, PersistableRecord {}
// Per-table: `databaseTableName`, and where the default Codable column mapping is
// insufficient (JSON-encoded `attendees`/`sources`/`candidateBuckets`, UUID-as-TEXT),
// custom `encode(to:)` / `init(row:)` or a `databaseJSONEncoder`/Decoder.

/// A stored embedding for an item (PRD §6.2 note). `vector` is the raw `[Double]` (or
/// `[Float]`) encoded as a `BLOB`; MVP computes similarity in Swift, so no sqlite-vec yet.
public struct ItemEmbedding: Identifiable, Sendable, Codable, Equatable,
                             FetchableRecord, PersistableRecord {
    public var itemId: UUID            // primary key
    public var vector: [Double]
    public var id: UUID { itemId }
    public init(itemId: UUID, vector: [Double])
}

// MARK: - Repositories

/// CRUD + key queries for buckets. Writes serialize through the shared `DatabaseQueue`.
public struct BucketRepository: Sendable {
    public init(database: any DatabaseWriter)
    public func upsert(_ bucket: Bucket) throws
    public func fetch(id: UUID) throws -> Bucket?
    public func all() throws -> [Bucket]
    public func active() throws -> [Bucket]
    public func delete(id: UUID) throws
}

/// CRUD + key queries for items, including "items in a bucket" (PRD C7.1 retrieval) and
/// embedding co-storage.
public struct ItemRepository: Sendable {
    public init(database: any DatabaseWriter)
    public func upsert(_ item: Item) throws
    public func fetch(id: UUID) throws -> Item?
    /// Items whose `homeBucketId == bucketId`, newest first.
    public func items(inBucket bucketId: UUID) throws -> [Item]
    public func delete(id: UUID) throws

    public func setEmbedding(_ embedding: ItemEmbedding) throws
    public func embedding(forItem itemId: UUID) throws -> ItemEmbedding?
}

/// CRUD + the "pending triage" query backing the Needs-Sorting inbox (PRD §6.7, C2.4).
public struct TriageRepository: Sendable {
    public init(database: any DatabaseWriter)
    public func upsert(_ item: TriageItem) throws
    public func fetch(id: UUID) throws -> TriageItem?
    /// All triage items with `status == .pending`.
    public func pending() throws -> [TriageItem]
    public func delete(id: UUID) throws
}
// Thin repos for the remaining entities (BucketLink, Contact, CalendarEvent, PrepBrief,
// Asset) follow the same upsert/fetch/all/delete shape; CalendarEvent/PrepBrief keyed by
// their String/UUID ids respectively.

// MARK: - Encryption at rest (Constitution §2, C8.1 / C8.4)

/// Whole-file AES-GCM (CryptoKit) wrapper around a GRDB database.
///
/// At-rest, the database is an AES-GCM ciphertext blob at `cipherURL`. On `open()` the blob
/// is decrypted to a plaintext **working file** (perms `0o600`) that GRDB opens; on
/// `persist()`/`close()` the working file is re-encrypted and atomically replaces the
/// ciphertext, then deleted. The key comes from `SecretStore` (`SecretKey.databaseKey`),
/// generated on first use and never written to disk in plaintext.
///
/// TRADEOFF (documented): a plaintext working file exists on disk while the DB is open —
/// the deliberate cost of plain SQLite without SQLCipher in the MVP. It is owner-only,
/// short-lived, in a sandbox/FileVault-protected directory, and removed on close;
/// FileVault is the defense-in-depth backstop.
public final class EncryptedDatabase: Sendable {
    /// - Parameters:
    ///   - cipherURL: where the encrypted blob lives (system of record).
    ///   - workingDirectory: sandbox-private dir for the transient plaintext file.
    ///   - secretStore: source of the AES-GCM key (Keychain in app, fake in tests).
    public init(cipherURL: URL, workingDirectory: URL, secretStore: any SecretStore)

    /// Decrypt to the working file (or create an empty DB on first run), run migrations,
    /// and return the GRDB `DatabaseQueue` repositories build on.
    public func open() throws -> DatabaseQueue

    /// Re-encrypt the current working file and atomically replace the ciphertext.
    public func persist() throws

    /// `persist()` then remove the plaintext working file.
    public func close() throws

    /// Encrypted export/backup (C8.4): persist, then write a fresh AES-GCM blob of the
    /// current database to `url`. Encrypts under the same `SecretKey.databaseKey` for MVP;
    /// a user-supplied passphrase is a documented later extension.
    public func exportEncrypted(to url: URL) throws
}

/// Stateless AES-GCM helpers, separated so the crypto round-trip is unit-testable without
/// any filesystem. The key never appears in `seal`'s output beyond the AES-GCM combined box.
public enum DatabaseCrypto {
    /// Fetch the key from `SecretStore`, generating + storing a 256-bit key on first use.
    public static func loadOrCreateKey(_ store: any SecretStore) throws -> SymmetricKey
    /// `AES.GCM.seal(plaintext, using: key).combined` (nonce ‖ ciphertext ‖ tag).
    public static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data
    /// Inverse of `seal`; throws `PersistenceError.decryptionFailed` on auth failure.
    public static func open(_ box: Data, key: SymmetricKey) throws -> Data
}
```

### Storage conventions (migration `v1`)
- **UUID** → `TEXT` (`uuidString`). **Enums** → `TEXT` (`rawValue`). **Date** → GRDB's
  default (ISO-8601 `TEXT` via its `DatabaseValueConvertible` conformance).
- **JSON `TEXT`** for `CalendarEvent.attendees` (`[EventAttendee]`), `PrepBrief.sources`
  (`[SourceRef]`), `TriageItem.candidateBuckets` (`[ScoredBucket]`).
- **`item_embeddings`**: `itemId TEXT PRIMARY KEY`, `vector BLOB`
  (FK `itemId → items.id ON DELETE CASCADE`).
- Foreign keys declared where natural (`items.homeBucketId`, `triage_items.itemId`,
  `bucket_links.from/toBucketId`); `PRAGMA foreign_keys = ON`.

## 3. Dependencies

- `PrepOSCore` — domain value types, `SecretStore`/`SecretKey`, `ScoredBucket`.
- `GRDB` (7.11.0, already in `Package.swift`) — `DatabaseQueue`, `DatabaseMigrator`, record
  protocols.
- `CryptoKit` (system) — `AES.GCM`, `SymmetricKey`.
- **No** new package deps, **no** network, **no** Altify/Graph imports.

## 4. Test list (`Tests/PrepOSPersistenceTests/`)

All tests use an **in-memory GRDB queue** (`DatabaseQueue()` with no path → SQLite
`:memory:`) for migrations + repository CRUD, an **in-memory `SecretStore` fake**, and an
in-memory `Data` round-trip for crypto — no real files, no Xcode-only frameworks, no
network.

**Migrations**
1. *happy* — `PrepOSSchema.migrate` on a fresh in-memory queue creates all nine tables
   (`buckets … assets`, `item_embeddings`); assert each exists via `db.tableExists`.
2. *idempotent / boundary* — running the migrator twice does not throw and leaves schema
   unchanged.
3. *columns* — spot-check column names/types for a JSON-bearing table (e.g.
   `calendar_events.attendees` is `TEXT`).

**Repository CRUD round-trips**
4. *happy* — `BucketRepository.upsert` then `fetch(id:)` returns an `Equatable`-identical
   `Bucket` (enums + optional `sfdcId`/`altifyOppId` survive).
5. *happy* — `ItemRepository.upsert` + `items(inBucket:)` returns only that bucket's items,
   newest-first.
6. *happy* — `ItemRepository.setEmbedding` / `embedding(forItem:)` round-trips the `[Double]`
   vector through the BLOB column with bit-for-bit equality.
7. *happy* — `TriageRepository.pending()` returns only `status == .pending` items and decodes
   the JSON `candidateBuckets` ( `[ScoredBucket]` ) intact.
8. *happy (JSON columns)* — `CalendarEvent` with multiple `attendees` and a `PrepBrief` with
   multiple `sources` round-trip equal (JSON encode/decode).
9. *edge* — `upsert` of an existing id updates in place (no duplicate row); `fetch` on a
   missing id returns `nil`; `delete` removes the row.
10. *boundary* — FK cascade: deleting an `Item` removes its `item_embeddings` row.

**Encryption round-trip**
11. *happy* — `DatabaseCrypto.seal` then `open` with the same key yields **identical bytes**.
12. *edge* — `open` with a different key (or a 1-byte-flipped box) throws
    `PersistenceError.decryptionFailed` (AES-GCM auth).
13. *key lifecycle* — `loadOrCreateKey` generates + stores a key on first call (fake
    `SecretStore` now has `SecretKey.databaseKey`) and returns the **same** key on the
    second call.
14. *file round-trip* — `EncryptedDatabase.open` → write via a repo → `close`, then reopen
    from the same `cipherURL`+store and read the row back; assert the on-disk `cipherURL`
    bytes are **not** valid UTF-8 / contain none of the plaintext field values.
15. *export (C8.4)* — `exportEncrypted(to:)` produces a file that `DatabaseCrypto.open`
    decrypts to a valid SQLite DB containing the written rows.

**Constitution boundary**
16. *secrets only via SecretStore* — the AES-GCM **key bytes never appear** in `seal`'s
    output: seal a known plaintext, assert the raw key `Data` is not a subrange of the
    ciphertext box (and is absent from the on-disk `cipherURL` in test 14).
17. *encrypted at rest* — the persisted `cipherURL` is **not** a readable SQLite file
    (header bytes `"SQLite format 3\0"` absent) while the plaintext working file is removed
    after `close()`.
18. *no write/network affordance* — a source-text assertion (mirroring the existing
    `ConstitutionBoundaryTests` in other targets) that `Sources/PrepOSPersistence/` imports
    no networking/Altify/Graph symbol and references no write-MCP host; secret access is
    exclusively through `SecretStore`.

## 5. Build / verify

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PrepOSPersistenceTests`

The whole package must still compile. **Failure rule:** if either is red and cannot be made
green, revert `Sources/PrepOSPersistence/` and `Tests/PrepOSPersistenceTests/` to the
original single placeholder file each (namespace `enum PrepOSPersistence {}` +
`PlaceholderTests`) so the tree stays buildable, and report exactly what blocked.
```
