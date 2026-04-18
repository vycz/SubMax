import Foundation
import Testing
@testable import SubMaxCore

@Test func vmessGrpcTransportMapsPathToServiceName() throws {
    let payload = """
    {"v":"2","ps":"grpc-node","add":"grpc.example.com","port":"443","id":"78671e2d-7788-4a6e-9a55-6dc80c6766bb","aid":"0","scy":"auto","net":"grpc","type":"gun","host":"","path":"grpc-service","tls":"tls","sni":"grpc.example.com"}
    """
    let raw = "vmess://\(Data(payload.utf8).base64EncodedString())"
    let node = NodeRecord(
        sourceID: UUID(),
        protocolType: .vmess,
        displayName: "grpc-node",
        host: "grpc.example.com",
        port: 443,
        rawURI: raw,
        stableKey: "grpc-node"
    )

    let config = try SingBoxConfigBuilder().makeConfig(for: node, listenPort: 18080)

    #expect(config.contains("\"type\" : \"grpc\""))
    #expect(config.contains("\"service_name\" : \"grpc-service\""))
    #expect(!config.contains("\"path\" : \"grpc-service\""))
}
