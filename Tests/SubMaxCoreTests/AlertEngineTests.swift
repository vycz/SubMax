import Foundation
import Testing
@testable import SubMaxCore

@Test func alertEngineDetectsNodeDownAndRegressions() {
    let node = NodeRecord(
        sourceID: UUID(),
        protocolType: .vmess,
        displayName: "Regression Node",
        host: "node.example.com",
        port: 443,
        rawURI: "vmess://abc",
        stableKey: "node"
    )
    let runID = UUID()
    let previous = NodeProbeResult(runID: runID, nodeID: node.id, success: true, latencyMilliseconds: 100, downloadMBps: 10)
    let current = NodeProbeResult(runID: runID, nodeID: node.id, success: false, latencyMilliseconds: 900, downloadMBps: 3, failureReason: "timeout")

    let alerts = AlertEngine().evaluate(node: node, previous: previous, current: current)

    #expect(alerts.map(\.kind).contains(.nodeDown))
    #expect(alerts.map(\.kind).contains(.latencyRegression))
    #expect(alerts.map(\.kind).contains(.speedRegression))
}

@Test func alertEngineDoesNotTreatTimeoutAsNodeDown() {
    let node = NodeRecord(
        sourceID: UUID(),
        protocolType: .trojan,
        displayName: "Timeout Node",
        host: "node.example.com",
        port: 443,
        rawURI: "trojan://password@node.example.com:443#Timeout",
        stableKey: "timeout"
    )
    let runID = UUID()
    let previous = NodeProbeResult(runID: runID, nodeID: node.id, success: true, latencyMilliseconds: 100, downloadMBps: 10)
    let current = NodeProbeResult(runID: runID, nodeID: node.id, success: false, outcome: .timedOut, failureReason: "timeout")

    let alerts = AlertEngine().evaluate(node: node, previous: previous, current: current)

    #expect(!alerts.map(\.kind).contains(.nodeDown))
}
