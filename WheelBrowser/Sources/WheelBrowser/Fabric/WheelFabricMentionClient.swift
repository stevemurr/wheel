import Fabric
import Foundation

protocol WheelFabricMentionClient: AnyObject {
    func discoverResources(
        callerAppID: String,
        query: String?
    ) async throws -> [FabricResourceDescriptor]

    func resolveContexts(
        callerAppID: String,
        uris: [FabricURI]
    ) async throws -> [FabricContextPayload]
}

extension FabricXPCClient: WheelFabricMentionClient {}
