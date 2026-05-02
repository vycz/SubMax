import Foundation
import Testing
@testable import SubMaxCore

@Test func parserDecodesBase64SubscriptionAndFiltersMetadata() throws {
    let sourceID = UUID()
    let vmessPayload = """
    {"v":"2","ps":"🇸🇬 Singapore - 2|东方|X2","add":"hk2.baiyundd.com","port":"45099","id":"78671e2d-7788-4a6e-9a55-6dc80c6766bb","aid":"0","net":"tcp","type":"none","host":"","path":"","tls":""}
    """
    let vmess = "vmess://\(Data(vmessPayload.utf8).base64EncodedString())"
    let trojanMeta = "trojan://password@example.com:443?allowInsecure=0#%E5%89%A9%E4%BD%99%E6%B5%81%E9%87%8F%EF%BC%9A439.37%20GB"
    let trojanNode = "trojan://password@hk1.example.com:49232?allowInsecure=1&sni=example.com#%F0%9F%87%B8%F0%9F%87%AC%20Singapore-1%7C%E5%B9%BF%E6%B8%AF%7CX2"
    let body = [trojanMeta, trojanNode, vmess].joined(separator: "\n")
    let encoded = Data(body.utf8).base64EncodedString()

    let parsed = try SubscriptionParser().parse(sourceID: sourceID, body: encoded)

    #expect(parsed.snapshot.rawLineCount == 3)
    #expect(parsed.snapshot.parsedNodeCount == 2)
    #expect(parsed.snapshot.ignoredLineCount == 1)
    #expect(parsed.nodes.map(\.protocolType).sorted { $0.rawValue < $1.rawValue } == [.trojan, .vmess])
    #expect(parsed.nodes.contains { $0.displayName.contains("Singapore-1") })
    #expect(parsed.nodes.contains { $0.host == "hk2.baiyundd.com" && $0.port == 45099 })
}

@Test func parserFallsBackToReadableNameWhenNodeNameIsEmpty() throws {
    let sourceID = UUID()
    let line = "trojan://password@node.example.com:443?allowInsecure=0#"

    let parsed = try SubscriptionParser().parse(sourceID: sourceID, body: line)

    #expect(parsed.nodes.count == 1)
    #expect(parsed.nodes[0].displayName == "Trojan node.example.com:443")
}

@Test func parserSupportsBase64VlessRealitySubscription() throws {
    let sourceID = UUID()
    let vless = "vless://11111111-2222-3333-4444-555555555555@node.example.com:37794?encryption=none&flow=xtls-rprx-vision&fp=chrome&pbk=exampleRealityPublicKey&security=reality&sid=5b86e1cc&sni=www.example.com&spx=%2Fexample&type=tcp#reality-node"
    let encoded = Data(vless.utf8).base64EncodedString()

    let parsed = try SubscriptionParser().parse(sourceID: sourceID, body: encoded)

    #expect(parsed.snapshot.rawLineCount == 1)
    #expect(parsed.snapshot.parsedNodeCount == 1)
    #expect(parsed.snapshot.invalidLineCount == 0)
    #expect(parsed.nodes[0].protocolType == .vless)
    #expect(parsed.nodes[0].displayName == "reality-node")
    #expect(parsed.nodes[0].host == "node.example.com")
    #expect(parsed.nodes[0].port == 37794)
}
