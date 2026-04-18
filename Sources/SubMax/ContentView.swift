import SubMaxCore
import Charts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            nodeList
            Divider()
            detailPanel
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("SubMax")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                Text("订阅健康、节点速度与解锁能力，一眼看清。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 12) {
                Text("主订阅")
                    .font(.headline)
                TextField("粘贴订阅链接", text: $store.subscriptionURL)
                    .textFieldStyle(.roundedBorder)
                Stepper("巡检间隔：\(store.refreshIntervalMinutes) 分钟", value: $store.refreshIntervalMinutes, in: 5...360, step: 5)
                Stepper(
                    "并发检测：\(store.probeConcurrency)",
                    value: Binding(
                        get: { store.probeConcurrency },
                        set: { store.updateProbeConcurrency($0) }
                    ),
                    in: 1...16,
                    step: 1
                )
                Stepper(
                    "延迟采样：\(store.latencySampleCount) 次",
                    value: Binding(
                        get: { store.latencySampleCount },
                        set: { store.updateLatencySampleCount($0) }
                    ),
                    in: 1...20,
                    step: 1
                )
                Stepper(
                    "单节点超时：\(store.probeTimeoutSeconds) 秒",
                    value: Binding(
                        get: { store.probeTimeoutSeconds },
                        set: { store.updateProbeTimeoutSeconds($0) }
                    ),
                    in: 5...120,
                    step: 5
                )
                Stepper(
                    "下载无数据：\(store.downloadNoDataTimeoutSeconds) 秒",
                    value: Binding(
                        get: { store.downloadNoDataTimeoutSeconds },
                        set: { store.updateDownloadNoDataTimeoutSeconds($0) }
                    ),
                    in: 1...30,
                    step: 1
                )
                Stepper(
                    "下载样本：\(store.downloadSizeMB) MB",
                    value: Binding(
                        get: { store.downloadSizeMB },
                        set: { store.updateDownloadSizeMB($0) }
                    ),
                    in: 1...500,
                    step: 10
                )
                HStack {
                    Button {
                        Task { await store.refreshSubscription() }
                    } label: {
                        Label("导入/刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isRefreshing)

                    Button {
                        store.startProbeAll()
                    } label: {
                        Label("全量检测", systemImage: "speedometer")
                    }
                    .disabled(store.isProbing || store.nodes.isEmpty)

                    if store.isProbing {
                        Button(role: .destructive) {
                            store.stopProbing()
                        } label: {
                            Label("停止检测", systemImage: "stop.fill")
                        }
                    }
                }
            }
            .padding()
            .background(cardBackground)

            VStack(alignment: .leading, spacing: 10) {
                Text("运行状态")
                    .font(.headline)
                Label(store.coreStatus.message, systemImage: store.coreStatus.isAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(store.coreStatus.isAvailable ? .green : .orange)
                    .font(.caption)
                Text(store.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(cardBackground)

            VStack(alignment: .leading, spacing: 10) {
                Text("最近告警")
                    .font(.headline)
                if store.alerts.isEmpty {
                    Text("暂无异常。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.alerts.prefix(5)) { alert in
                        Text(alert.message)
                            .font(.caption)
                            .lineLimit(2)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding()
            .background(cardBackground)

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(width: 330)
        .background(
            LinearGradient(
                colors: [Color(red: 0.93, green: 0.98, blue: 0.96), Color(red: 0.86, green: 0.93, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var nodeList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("节点")
                    .font(.title2.bold())
                Spacer()
                Text("\(store.nodes.count)")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Picker("排序", selection: Binding(
                    get: { store.sortMetric },
                    set: { store.updateSortMetric($0) }
                )) {
                    ForEach(NodeSortMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    store.toggleSortDirection()
                } label: {
                    Image(systemName: store.sortDescending ? "arrow.down" : "arrow.up")
                }
                .buttonStyle(.bordered)
                .help(store.sortDescending ? "降序" : "升序")
            }

            if store.nodes.isEmpty {
                ContentUnavailableView("还没有节点", systemImage: "antenna.radiowaves.left.and.right", description: Text("先导入订阅，然后开始检测。"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.sortedNodes) { node in
                            NodeRow(
                                node: node,
                                result: store.latestResults[node.id],
                                isSelected: store.selectedNode?.id == node.id,
                                isProbing: store.probingNodeIDs.contains(node.id)
                            )
                            .onTapGesture {
                                store.select(node)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .padding(20)
        .frame(width: 430)
    }

    private var detailPanel: some View {
        Group {
            if let node = store.selectedNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(node.displayName)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                Text("\(node.protocolType.rawValue.uppercased()) · \(node.host):\(node.port)")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Button {
                                    store.startProbeSelectedNode()
                                } label: {
                                    Label("重测节点", systemImage: "bolt.horizontal.circle")
                                }
                                .disabled(store.isProbing)

                                if store.isProbing {
                                    Button(role: .destructive) {
                                        store.stopProbing()
                                    } label: {
                                        Label("停止检测", systemImage: "stop.fill")
                                    }
                                }
                            }
                        }

                        MetricStrip(result: store.latestResults[node.id])

                        ExitIPCard(result: store.latestResults[node.id])

                        VStack(alignment: .leading, spacing: 10) {
                            Text("解锁状态")
                                .font(.headline)
                            if let latest = store.latestResults[node.id],
                               let unlocks = store.selectedUnlocks[latest.id],
                               !unlocks.isEmpty {
                                HStack {
                                    ForEach(unlocks) { unlock in
                                        UnlockPill(unlock: unlock)
                                    }
                                }
                            } else {
                                Text("暂无解锁检测结果。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(cardBackground)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("巡检趋势")
                                .font(.headline)
                            if store.selectedHistory.count < 2 {
                                Text("至少需要两次检测后才会形成趋势图。")
                                    .foregroundStyle(.secondary)
                            } else {
                                ProbeTrendChart(results: store.selectedHistory)
                                    .frame(height: 190)
                            }
                        }
                        .padding()
                        .background(cardBackground)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("历史记录")
                                .font(.headline)
                            if store.selectedHistory.isEmpty {
                                Text("暂无历史检测。")
                                    .foregroundStyle(.secondary)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(store.selectedHistory.prefix(3)) { result in
                                        HistoryRow(result: result, unlocks: store.selectedUnlocks[result.id] ?? [])
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(cardBackground)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("选择一个节点", systemImage: "point.3.connected.trianglepath.dotted", description: Text("节点详情、历史趋势和解锁状态会显示在这里。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.white.opacity(0.72))
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}

private struct NodeRow: View {
    var node: NodeRecord
    var result: NodeProbeResult?
    var isSelected: Bool
    var isProbing: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isProbing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 48, height: 24)
            } else {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(
                        Capsule(style: .continuous)
                            .fill(statusColor.opacity(0.14))
                    )
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(node.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(isProbing ? "正在测试..." : "\(node.protocolType.rawValue.uppercased()) · \(node.host):\(node.port)")
                    .font(.caption)
                    .foregroundStyle(isProbing ? .blue : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(isProbing ? "测试中" : latencyText)
                    .font(.subheadline.bold())
                    .foregroundStyle(isProbing ? .blue : .primary)
                Text(isProbing ? "等待结果" : speedText)
                    .font(.caption)
                    .foregroundStyle(metricTextColor)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
        )
    }

    private var statusText: String {
        guard let result else { return "未测" }
        switch result.outcome {
        case .succeeded: return "成功"
        case .failed: return "失败"
        case .timedOut: return "超时"
        }
    }

    private var statusColor: Color {
        guard let result else { return .secondary }
        switch result.outcome {
        case .succeeded: return .green
        case .failed: return .red
        case .timedOut: return .orange
        }
    }

    private var metricTextColor: Color {
        guard let result else { return .secondary }
        switch result.outcome {
        case .succeeded: return .secondary
        case .failed: return .red
        case .timedOut: return .orange
        }
    }

    private var latencyText: String {
        guard let latency = result?.latencyMilliseconds else { return "-- ms" }
        return "\(Int(latency)) ms"
    }

    private var speedText: String {
        guard let speed = result?.downloadMBps else { return "-- MB/s" }
        return String(format: "%.2f MB/s", speed)
    }
}

private struct MetricStrip: View {
    var result: NodeProbeResult?

    var body: some View {
        HStack(spacing: 12) {
            metric("状态", value: statusText, color: statusColor)
            metric("延迟", value: latencyText, color: .blue)
            metric("下载", value: speedText, color: .teal)
            metric("丢包", value: packetLossText, color: .orange)
            metric("最近检测", value: timeText, color: .indigo)
        }
    }

    private func metric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color.opacity(0.10))
        )
    }

    private var statusText: String {
        guard let result else { return "未检测" }
        switch result.outcome {
        case .succeeded: return "可用"
        case .failed: return "异常"
        case .timedOut: return "超时"
        }
    }

    private var statusColor: Color {
        guard let result else { return .gray }
        switch result.outcome {
        case .succeeded: return .green
        case .failed: return .red
        case .timedOut: return .orange
        }
    }

    private var latencyText: String {
        guard let latency = result?.latencyMilliseconds else { return "-- ms" }
        return "\(Int(latency)) ms"
    }

    private var speedText: String {
        guard let speed = result?.downloadMBps else { return "-- MB/s" }
        return String(format: "%.2f", speed)
    }

    private var packetLossText: String {
        guard let loss = result?.packetLossRate else { return "--" }
        return "\(Int((loss * 100).rounded()))%"
    }

    private var timeText: String {
        guard let date = result?.createdAt else { return "--" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct ExitIPCard: View {
    var result: NodeProbeResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("出口 IP")
                .font(.headline)
            if let result, result.exitIP != nil || result.exitCountry != nil || result.exitOrg != nil {
                HStack(alignment: .top, spacing: 14) {
                    Label(result.exitIP ?? "--", systemImage: "network")
                        .font(.callout.bold())
                    Text([result.exitCountry, result.exitRegion, result.exitCity].compactMap { $0 }.joined(separator: " / "))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if let org = result.exitOrg, !org.isEmpty {
                    Text(org)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("暂无出口 IP 信息。下一次检测会记录。")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct ProbeTrendChart: View {
    var results: [NodeProbeResult]

    private var points: [ChartPoint] {
        results
            .reversed()
            .flatMap { result -> [ChartPoint] in
                var output: [ChartPoint] = []
                if let latency = result.latencyMilliseconds {
                    output.append(ChartPoint(resultID: result.id, date: result.createdAt, metric: "延迟(ms)", value: latency))
                }
                if let speed = result.downloadMBps {
                    output.append(ChartPoint(resultID: result.id, date: result.createdAt, metric: "下载(MB/s)", value: speed))
                }
                if let loss = result.packetLossRate {
                    output.append(ChartPoint(resultID: result.id, date: result.createdAt, metric: "丢包(%)", value: loss * 100))
                }
                return output
            }
    }

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("时间", point.date),
                y: .value("值", point.value)
            )
            .foregroundStyle(by: .value("指标", point.metric))
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value("时间", point.date),
                y: .value("值", point.value)
            )
            .foregroundStyle(by: .value("指标", point.metric))
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
}

private struct ChartPoint: Identifiable {
    var resultID: UUID
    var date: Date
    var metric: String
    var value: Double

    var id: String { "\(resultID.uuidString)-\(metric)" }
}

private struct UnlockPill: View {
    var unlock: UnlockResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(unlock.provider.displayName)
                .font(.caption.bold())
            Text(unlock.status.rawValue)
                .font(.caption2)
            if let region = unlock.region {
                Text(region)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(color.opacity(0.14))
        )
        .foregroundStyle(color)
    }

    private var color: Color {
        switch unlock.status {
        case .available: return .green
        case .reachable: return .blue
        case .restricted: return .orange
        case .error: return .red
        case .unknown: return .gray
        }
    }
}

private struct HistoryRow: View {
    var result: NodeProbeResult
    var unlocks: [UnlockResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(statusLabel, systemImage: statusIcon)
                    .foregroundStyle(statusColor)
                Spacer()
                Text(result.createdAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if result.outcome == .succeeded || result.outcome == .timedOut {
                Text("延迟 \(latencyText) · 下载 \(speedText) · 丢包 \(packetLossText)")
                    .font(.callout)
                if let warning = result.failureReason {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(result.outcome == .timedOut ? .orange : .secondary)
                        .lineLimit(2)
                }
                if result.outcome == .timedOut, let exitText {
                    Text(exitText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text([result.failureReason, exitText].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !unlocks.isEmpty {
                Text(unlocks.map { "\($0.provider.displayName): \($0.status.rawValue)" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var latencyText: String {
        guard let latency = result.latencyMilliseconds else { return "-- ms" }
        return "\(Int(latency)) ms"
    }

    private var speedText: String {
        guard let speed = result.downloadMBps else { return "-- MB/s" }
        return String(format: "%.2f MB/s", speed)
    }

    private var statusLabel: String {
        switch result.outcome {
        case .succeeded: return "成功"
        case .failed: return "失败"
        case .timedOut: return "超时"
        }
    }

    private var statusIcon: String {
        switch result.outcome {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .timedOut: return "clock.badge.exclamationmark.fill"
        }
    }

    private var statusColor: Color {
        switch result.outcome {
        case .succeeded: return .green
        case .failed: return .red
        case .timedOut: return .orange
        }
    }

    private var packetLossText: String {
        guard let loss = result.packetLossRate else { return "--" }
        return "\(Int((loss * 100).rounded()))%"
    }

    private var exitText: String? {
        guard let ip = result.exitIP else { return nil }
        return "出口 \(ip)"
    }
}
