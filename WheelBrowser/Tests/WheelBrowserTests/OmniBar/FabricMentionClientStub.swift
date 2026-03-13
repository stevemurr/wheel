import Fabric
import Foundation
@testable import WheelBrowser

final class FabricMentionClientStub: WheelFabricMentionClient {
    var resources: [FabricResourceDescriptor]
    var contexts: [FabricContextPayload]
    var resolveDelay: Duration?
    private(set) var resolveCallCount = 0

    init(
        resources: [FabricResourceDescriptor] = [],
        contexts: [FabricContextPayload] = [],
        resolveDelay: Duration? = nil
    ) {
        self.resources = resources
        self.contexts = contexts
        self.resolveDelay = resolveDelay
    }

    func discoverResources(
        callerAppID: String,
        query: String?
    ) async throws -> [FabricResourceDescriptor] {
        resources
    }

    func resolveContexts(
        callerAppID: String,
        uris: [FabricURI]
    ) async throws -> [FabricContextPayload] {
        resolveCallCount += 1
        if let resolveDelay {
            try await Task.sleep(for: resolveDelay)
        }
        let requestedURIs = Set(uris.map(\.rawValue))
        return contexts.filter { requestedURIs.contains($0.uri.rawValue) }
    }
}
