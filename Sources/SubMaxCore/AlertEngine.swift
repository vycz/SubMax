import Foundation

public struct AlertEngine: Sendable {
    public init() {}

    public func evaluate(node: NodeRecord, previous: NodeProbeResult?, current: NodeProbeResult) -> [AlertEvent] {
        guard let previous else { return [] }
        var alerts: [AlertEvent] = []

        if previous.outcome == .succeeded && current.outcome == .failed {
            alerts.append(AlertEvent(
                nodeID: node.id,
                resultID: current.id,
                kind: .nodeDown,
                message: "\(node.displayName) 从可用变为不可用：\(current.failureReason ?? "未知错误")"
            ))
        }

        if let oldLatency = previous.latencyMilliseconds,
           let newLatency = current.latencyMilliseconds,
           oldLatency > 0,
           newLatency > max(oldLatency * 2, oldLatency + 500) {
            alerts.append(AlertEvent(
                nodeID: node.id,
                resultID: current.id,
                kind: .latencyRegression,
                message: "\(node.displayName) 延迟从 \(Int(oldLatency))ms 升高到 \(Int(newLatency))ms"
            ))
        }

        if let oldSpeed = previous.downloadMBps,
           let newSpeed = current.downloadMBps,
           oldSpeed >= 1,
           newSpeed < oldSpeed * 0.5 {
            alerts.append(AlertEvent(
                nodeID: node.id,
                resultID: current.id,
                kind: .speedRegression,
                message: "\(node.displayName) 下载速度从 \(String(format: "%.2f", oldSpeed)) MB/s 降到 \(String(format: "%.2f", newSpeed)) MB/s"
            ))
        }

        return alerts
    }
}
