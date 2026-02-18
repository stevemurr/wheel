# SqliteVec

Swift wrapper for [sqlite-vec](https://github.com/asg017/sqlite-vec), a vector search SQLite extension.

## Setup

Download the sqlite-vec source files before building:

```bash
cd Packages/SqliteVec
make download
```

This fetches `sqlite-vec.c` and `sqlite-vec.h` from the official releases.

## Usage

### Add to your Package.swift

```swift
dependencies: [
    .package(path: "../Packages/SqliteVec")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["SqliteVec"]
    )
]
```

### Register with SQLite

```swift
import SQLite3
import SqliteVec

var db: OpaquePointer?
sqlite3_open(":memory:", &db)

// Register sqlite-vec extension
try SqliteVec.register(db: db!)
```

### Create a vector table

```swift
let sql = """
    CREATE VIRTUAL TABLE embeddings USING vec0(
        page_id INTEGER PRIMARY KEY,
        embedding float[384]
    )
"""
sqlite3_exec(db, sql, nil, nil, nil)
```

### Insert vectors

```swift
let embedding: [Float] = [...] // Your 384-dim vector

var stmt: OpaquePointer?
sqlite3_prepare_v2(db, "INSERT INTO embeddings (page_id, embedding) VALUES (?, ?)", -1, &stmt, nil)
sqlite3_bind_int64(stmt, 1, pageId)
SqliteVec.bindVector(stmt!, index: 2, vector: embedding)
sqlite3_step(stmt)
sqlite3_finalize(stmt)
```

### Query for similar vectors

```swift
let querySQL = """
    SELECT page_id, distance
    FROM embeddings
    WHERE embedding MATCH ?
    ORDER BY distance
    LIMIT 10
"""

var stmt: OpaquePointer?
sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil)
SqliteVec.bindVector(stmt!, index: 1, vector: queryEmbedding)

while sqlite3_step(stmt) == SQLITE_ROW {
    let pageId = sqlite3_column_int64(stmt, 0)
    let distance = sqlite3_column_double(stmt, 1)
    print("Page \(pageId): distance \(distance)")
}
sqlite3_finalize(stmt)
```

## API Reference

### SqliteVec

| Method | Description |
|--------|-------------|
| `register(db:)` | Register sqlite-vec with a database connection |
| `version` | Get the sqlite-vec version string |
| `floatVectorToBlob(_:)` | Convert Float array to Data for BLOB binding |
| `blobToFloatVector(_:dimensions:)` | Convert BLOB data back to Float array |
| `bindVector(_:index:vector:)` | Bind a float vector to a prepared statement |
| `columnVector(_:index:dimensions:)` | Read a float vector from a result column |

### Vector types supported

| SQL Type | Description |
|----------|-------------|
| `float[N]` | 32-bit float vector with N dimensions |
| `int8[N]` | 8-bit integer vector (quantized) |
| `bit[N]` | Binary vector for hamming distance |

## License

sqlite-vec is dual-licensed under MIT and Apache 2.0.
