import XCTest
import SQLite3
@testable import SqliteVec

final class SqliteVecTests: XCTestCase {

    var db: OpaquePointer?

    override func setUp() {
        super.setUp()
        XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK)
        XCTAssertNoThrow(try SqliteVec.register(db: db!))
    }

    override func tearDown() {
        sqlite3_close(db)
        db = nil
        super.tearDown()
    }

    func testVersion() {
        let version = SqliteVec.version
        XCTAssertFalse(version.isEmpty)
        XCTAssertTrue(version.contains("."))
    }

    func testCreateVec0Table() throws {
        let sql = """
            CREATE VIRTUAL TABLE test_vec USING vec0(
                embedding float[4]
            )
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    func testInsertAndQuery() throws {
        // Create table
        let createSQL = """
            CREATE VIRTUAL TABLE test_vec USING vec0(
                id INTEGER PRIMARY KEY,
                embedding float[4]
            )
        """
        XCTAssertEqual(sqlite3_exec(db, createSQL, nil, nil, nil), SQLITE_OK)

        // Insert vectors
        let insertSQL = "INSERT INTO test_vec (id, embedding) VALUES (?, ?)"
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil), SQLITE_OK)

        let vectors: [[Float]] = [
            [1.0, 0.0, 0.0, 0.0],
            [0.0, 1.0, 0.0, 0.0],
            [0.0, 0.0, 1.0, 0.0],
            [0.9, 0.1, 0.0, 0.0]  // Similar to first
        ]

        for (id, vector) in vectors.enumerated() {
            sqlite3_reset(stmt)
            sqlite3_bind_int64(stmt, 1, Int64(id + 1))
            SqliteVec.bindVector(stmt!, index: 2, vector: vector)
            XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
        }
        sqlite3_finalize(stmt)

        // Query for vectors similar to [1, 0, 0, 0]
        let querySQL = """
            SELECT id, distance
            FROM test_vec
            WHERE embedding MATCH ?
            ORDER BY distance
            LIMIT 2
        """
        XCTAssertEqual(sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil), SQLITE_OK)

        let queryVector: [Float] = [1.0, 0.0, 0.0, 0.0]
        SqliteVec.bindVector(stmt!, index: 1, vector: queryVector)

        var results: [(Int64, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let distance = sqlite3_column_double(stmt, 1)
            results.append((id, distance))
        }
        sqlite3_finalize(stmt)

        // First result should be id=1 (exact match)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].0, 1)
        XCTAssertEqual(results[0].1, 0.0, accuracy: 0.001)

        // Second should be id=4 (most similar)
        XCTAssertEqual(results[1].0, 4)
    }

    func testFloatVectorConversion() throws {
        let original: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let blob = SqliteVec.floatVectorToBlob(original)
        let recovered = try SqliteVec.blobToFloatVector(blob, dimensions: 5)

        XCTAssertEqual(original.count, recovered.count)
        for (a, b) in zip(original, recovered) {
            XCTAssertEqual(a, b, accuracy: 0.0001)
        }
    }

    func testDimensionMismatch() {
        let vector: [Float] = [1.0, 2.0, 3.0]
        let blob = SqliteVec.floatVectorToBlob(vector)

        XCTAssertThrowsError(try SqliteVec.blobToFloatVector(blob, dimensions: 5)) { error in
            guard case SqliteVecError.dimensionMismatch(let expected, let got) = error else {
                XCTFail("Expected dimensionMismatch error")
                return
            }
            XCTAssertEqual(expected, 5)
            XCTAssertEqual(got, 3)
        }
    }

    func testByteSizeCalculations() {
        XCTAssertEqual(SqliteVec.float32ByteSize(dimensions: 384), 384 * 4)
        XCTAssertEqual(SqliteVec.int8ByteSize(dimensions: 384), 384)
        XCTAssertEqual(SqliteVec.binaryByteSize(dimensions: 8), 1)
        XCTAssertEqual(SqliteVec.binaryByteSize(dimensions: 9), 2)
    }
}
