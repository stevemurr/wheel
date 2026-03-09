import Foundation

struct JSONCodingConfiguration {
    static let `default` = JSONCodingConfiguration()
    static let prettyPrintedSortedKeys = JSONCodingConfiguration(
        outputFormatting: [.prettyPrinted, .sortedKeys]
    )
    static let iso8601 = JSONCodingConfiguration(
        dateEncodingStrategy: .iso8601,
        dateDecodingStrategy: .iso8601
    )
    static let prettyPrintedSortedKeysISO8601 = JSONCodingConfiguration(
        outputFormatting: [.prettyPrinted, .sortedKeys],
        dateEncodingStrategy: .iso8601,
        dateDecodingStrategy: .iso8601
    )

    let outputFormatting: JSONEncoder.OutputFormatting
    let dateEncodingStrategy: JSONEncoder.DateEncodingStrategy
    let dateDecodingStrategy: JSONDecoder.DateDecodingStrategy

    init(
        outputFormatting: JSONEncoder.OutputFormatting = [],
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .deferredToDate,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate
    ) {
        self.outputFormatting = outputFormatting
        self.dateEncodingStrategy = dateEncodingStrategy
        self.dateDecodingStrategy = dateDecodingStrategy
    }

    func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        encoder.dateEncodingStrategy = dateEncodingStrategy
        return encoder
    }

    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecodingStrategy
        return decoder
    }
}

final class JSONBackedStore<Value: Codable>: @unchecked Sendable {
    private let backend: StoreBackend
    private let namespace: StoreNamespace
    private let key: StoreKey
    private let codingConfiguration: JSONCodingConfiguration

    init(
        backend: StoreBackend,
        namespace: StoreNamespace = .root,
        key: StoreKey,
        codingConfiguration: JSONCodingConfiguration = .default
    ) {
        self.backend = backend
        self.namespace = namespace
        self.key = key
        self.codingConfiguration = codingConfiguration
    }

    var fileURL: URL? {
        (backend as? FileSystemStoreBackend)?.url(for: namespace, key: key)
    }

    func load() throws -> Value? {
        guard let data = try backend.loadData(in: namespace, key: key) else {
            return nil
        }
        return try codingConfiguration.makeDecoder().decode(Value.self, from: data)
    }

    func rawData() throws -> Data? {
        try backend.loadData(in: namespace, key: key)
    }

    func save(_ value: Value) throws {
        let data = try codingConfiguration.makeEncoder().encode(value)
        try backend.saveData(data, in: namespace, key: key)
    }

    func delete() throws {
        try backend.deleteData(in: namespace, key: key)
    }
}

final class JSONBackedDirectoryStore<Value: Codable>: @unchecked Sendable {
    private let backend: StoreBackend
    private let namespace: StoreNamespace
    private let codingConfiguration: JSONCodingConfiguration

    init(
        backend: StoreBackend,
        namespace: StoreNamespace,
        codingConfiguration: JSONCodingConfiguration = .default
    ) {
        self.backend = backend
        self.namespace = namespace
        self.codingConfiguration = codingConfiguration
    }

    var directoryURL: URL? {
        (backend as? FileSystemStoreBackend)?.url(for: namespace)
    }

    func fileURL(for key: StoreKey) -> URL? {
        (backend as? FileSystemStoreBackend)?.url(for: namespace, key: key)
    }

    func load(key: StoreKey) throws -> Value? {
        guard let data = try backend.loadData(in: namespace, key: key) else {
            return nil
        }
        return try codingConfiguration.makeDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value, for key: StoreKey) throws {
        let data = try codingConfiguration.makeEncoder().encode(value)
        try backend.saveData(data, in: namespace, key: key)
    }

    func delete(key: StoreKey) throws {
        try backend.deleteData(in: namespace, key: key)
    }

    func keys() throws -> [StoreKey] {
        try backend.listKeys(in: namespace)
    }
}
