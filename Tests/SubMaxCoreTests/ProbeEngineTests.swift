import Foundation
import Testing
@testable import SubMaxCore

@Test func probeEngineReportsMissingCoreAsActionableFailure() async throws {
    let runtime = SingBoxRuntime(binaryURL: URL(fileURLWithPath: "/definitely/not/sing-box"))
    let engine = ProbeEngine(runtime: runtime)
    let node = NodeRecord(
        sourceID: UUID(),
        protocolType: .trojan,
        displayName: "Missing Core Node",
        host: "node.example.com",
        port: 443,
        rawURI: "trojan://password@node.example.com:443#Missing",
        stableKey: "missing"
    )

    let bundle = try await engine.probe(node: node, runID: UUID(), profile: ProbeProfile(timeoutSeconds: 1, enabledUnlockProviders: [.openAI]))

    #expect(bundle.result.success == false)
    #expect(bundle.result.failureReason?.contains("sing-box") == true)
    #expect(bundle.unlockResults.first?.status == .unknown)
}
