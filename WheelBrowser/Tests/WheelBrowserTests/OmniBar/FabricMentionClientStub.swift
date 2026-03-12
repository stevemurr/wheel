import Fabric
import Foundation
@testable import WheelBrowser

final class FabricMentionClientStub: WheelFabricMentionClient {
    var resources: [FabricResourceDescriptor]
    var contexts: [FabricContextPayload]

    init(
        resources: [FabricResourceDescriptor] = [],
        contexts: [FabricContextPayload] = []
    ) {
        self.resources = resources
        self.contexts = contexts
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
        let requestedURIs = Set(uris.map(\.rawValue))
        return contexts.filter { requestedURIs.contains($0.uri.rawValue) }
    }
}
