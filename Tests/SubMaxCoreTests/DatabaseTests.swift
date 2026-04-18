import Foundation
import Testing
@testable import SubMaxCore

@Test func databasePersistsSourceNodesResultsUnlocksAndAlerts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let database = try SubMaxDatabase(path: directory.appendingPathComponent("test.sqlite").path)
    let source = SubscriptionSource(url: "https://example.com/sub")
    try database.saveSubscriptionSource(source)
    #expect(try database.loadSubscriptionSource()?.url == "https://example.com/sub")

    let node = NodeRecord(
        sourceID: source.id,
        protocolType: .trojan,
        displayName: "Test Node",
        host: "node.example.com",
        port: 443,
        rawURI: "trojan://password@node.example.com:443#Test",
        stableKey: "stable"
    )
    let savedNodes = try database.upsertNodes([node], sourceID: source.id)
    #expect(savedNodes.count == 1)
    #expect(try database.fetchNodes(sourceID: source.id).count == 1)

    let run = ProbeRun(sourceID: source.id, trigger: .manual)
    try database.createProbeRun(run)
    let result = NodeProbeResult(
        runID: run.id,
        nodeID: savedNodes[0].id,
        success: true,
        latencyMilliseconds: 120,
        downloadMBps: 8.5,
        packetLossRate: 0.2,
        exitIP: "203.0.113.10",
        exitCountry: "Japan",
        exitRegion: "Tokyo",
        exitCity: "Tokyo",
        exitOrg: "Example ISP"
    )
    try database.saveProbeResult(result)
    try database.saveUnlockResults([
        UnlockResult(resultID: result.id, provider: .openAI, status: .reachable, region: "US", detail: "HTTP 200")
    ])
    try database.saveAlert(AlertEvent(nodeID: savedNodes[0].id, resultID: result.id, kind: .latencyRegression, message: "slow"))

    let latest = try database.fetchLatestResults(sourceID: source.id)[savedNodes[0].id]
    #expect(latest?.latencyMilliseconds == 120)
    #expect(latest?.packetLossRate == 0.2)
    #expect(latest?.exitIP == "203.0.113.10")
    #expect(latest?.exitOrg == "Example ISP")
    #expect(try database.fetchUnlockResults(resultID: result.id).first?.provider == .openAI)
    #expect(try database.fetchAlerts().first?.message == "slow")
}
