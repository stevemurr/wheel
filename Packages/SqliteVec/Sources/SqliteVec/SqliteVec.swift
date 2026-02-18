import Foundation
import SQLite3
import CSqliteVec

// MARK: - Public API

/// Swift wrapper for sqlite-vec vector search extension
public enum SqliteVec {

    /// Register sqlite-vec with a database connection.
    ///
    /// Call this after opening the database, before creating or querying vec0 tables.
    ///
    /// ```swift
    /// var db: OpaquePointer?
    /// sqlite3_open(":memory:", &db)
    /// try SqliteVec.register(db: db!)
    /// ```
    ///
    /// - Parameter db: An open SQLite database connection
    /// - Throws: `SqliteVecError.registrationFailed` if initialization fails
    public static func register(db: OpaquePointer) throws {
        let result = sqlite_vec_register(db)
        guard result == SQLITE_OK else {
            throw SqliteVecError.registrationFailed(
                code: result,
                message: "sqlite3_vec_init returned \(result)"
            )
        }
    }

    /// Get the sqlite-vec version string.
    public static var version: String {
        String(cString: sqlite_vec_version())
    }
}

// MARK: - Errors

public enum SqliteVecError: Error, LocalizedError {
    case registrationFailed(code: Int32, message: String)
    case invalidVector(message: String)
    case dimensionMismatch(expected: Int, got: Int)

    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let code, let message):
            return "sqlite-vec registration failed (code \(code)): \(message)"
        case .invalidVector(let message):
            return "Invalid vector: \(message)"
        case .dimensionMismatch(let expected, let got):
            return "Vector dimension mismatch: expected \(expected), got \(got)"
        }
    }
}

// MARK: - Vector Helpers

public extension SqliteVec {

    /// Convert a Float array to Data for binding as a BLOB parameter.
    ///
    /// ```swift
    /// let embedding: [Float] = [0.1, 0.2, 0.3, ...]
    /// let blob = SqliteVec.floatVectorToBlob(embedding)
    /// sqlite3_bind_blob(stmt, 1, blob.bytes, Int32(blob.count), SQLITE_TRANSIENT)
    /// ```
    static func floatVectorToBlob(_ vector: [Float]) -> Data {
        vector.withUnsafeBytes { Data($0) }
    }

    /// Convert BLOB data back to a Float array.
    ///
    /// - Parameters:
    ///   - data: The raw blob data
    ///   - dimensions: Expected number of dimensions (for validation)
    /// - Returns: Array of Float values
    static func blobToFloatVector(_ data: Data, dimensions: Int? = nil) throws -> [Float] {
        let floatSize = MemoryLayout<Float>.size
        guard data.count % floatSize == 0 else {
            throw SqliteVecError.invalidVector(
                message: "Data size \(data.count) is not a multiple of \(floatSize)"
            )
        }

        let count = data.count / floatSize
        if let expected = dimensions, count != expected {
            throw SqliteVecError.dimensionMismatch(expected: expected, got: count)
        }

        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    /// Calculate the byte size for a float32 vector.
    static func float32ByteSize(dimensions: Int) -> Int {
        Int(sqlite_vec_float32_byte_size(Int32(dimensions)))
    }

    /// Calculate the byte size for an int8 vector.
    static func int8ByteSize(dimensions: Int) -> Int {
        Int(sqlite_vec_int8_byte_size(Int32(dimensions)))
    }

    /// Calculate the byte size for a binary (bit) vector.
    static func binaryByteSize(dimensions: Int) -> Int {
        Int(sqlite_vec_binary_byte_size(Int32(dimensions)))
    }
}

// MARK: - Statement Helpers

public extension SqliteVec {

    /// Bind a float vector to a prepared statement parameter.
    ///
    /// ```swift
    /// let embedding: [Float] = [...]
    /// try SqliteVec.bindVector(stmt, index: 1, vector: embedding)
    /// ```
    @discardableResult
    static func bindVector(
        _ stmt: OpaquePointer,
        index: Int32,
        vector: [Float]
    ) -> Int32 {
        vector.withUnsafeBytes { buffer in
            sqlite3_bind_blob(
                stmt,
                index,
                buffer.baseAddress,
                Int32(buffer.count),
                unsafeBitCast(-1, to: sqlite3_destructor_type.self) // SQLITE_TRANSIENT
            )
        }
    }

    /// Read a float vector from a statement column.
    ///
    /// ```swift
    /// let embedding = try SqliteVec.columnVector(stmt, index: 0, dimensions: 384)
    /// ```
    static func columnVector(
        _ stmt: OpaquePointer,
        index: Int32,
        dimensions: Int
    ) throws -> [Float] {
        let bytes = sqlite3_column_bytes(stmt, index)
        guard bytes > 0 else {
            throw SqliteVecError.invalidVector(message: "Column contains no data")
        }

        guard let blob = sqlite3_column_blob(stmt, index) else {
            throw SqliteVecError.invalidVector(message: "Failed to read blob")
        }

        let data = Data(bytes: blob, count: Int(bytes))
        return try blobToFloatVector(data, dimensions: dimensions)
    }
}
