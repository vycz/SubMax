import Foundation
import SubMaxCore
import UserNotifications

enum NodeSortMetric: String, CaseIterable, Identifiable {
    case name
    case bandwidth
    case latency
    case packetLoss

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "默认"
        case .bandwidth: return "带宽"
        case .latency: return "延迟"
        case .packetLoss: return "丢包率"
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var subscriptionURL = ""
    @Published var refreshIntervalMinutes = 60
    @Published var nodes: [NodeRecord] = []
    @Published var latestResults: [UUID: NodeProbeResult] = [:]
    @Published var selectedNode: NodeRecord?
    @Published var selectedHistory: [NodeProbeResult] = []
    @Published var selectedUnlocks: [UUID: [UnlockResult]] = [:]
    @Published var alerts: [AlertEvent] = []
    @Published var statusMessage = "准备导入订阅"
    @Published var coreStatus = CoreStatus(binaryPath: nil, message: "正在检测 sing-box 内核...")
    @Published var isRefreshing = false
    @Published var isProbing = false
    @Published var probeConcurrency = 3
    @Published var probingNodeIDs: Set<UUID> = []
    @Published var latencySampleCount = 5
    @Published var probeTimeoutSeconds = 20
    @Published var downloadNoDataTimeoutSeconds = 5
    @Published var downloadSizeMB = 50
    @Published var sortMetric: NodeSortMetric = .name
    @Published var sortDescending = false

    private var database: SubMaxDatabase?
    private var source: SubscriptionSource?
    private let fetcher = SubscriptionFetcher()
    private let parser = SubscriptionParser()
    private let probeEngine = ProbeEngine()
    private let alertEngine = AlertEngine()
    private var schedulerTask: Task<Void, Never>?
    private var activeProbeTask: Task<Void, Never>?
    private var activeProbeToken: UUID?

    deinit {
        activeProbeTask?.cancel()
        schedulerTask?.cancel()
    }

    func bootstrap() async {
        do {
            loadProbeSettings()
            database = try SubMaxDatabase.appSupportDatabase()
            source = try database?.loadSubscriptionSource()
            if let source {
                subscriptionURL = source.url
                refreshIntervalMinutes = source.refreshIntervalMinutes
                nodes = try database?.fetchNodes(sourceID: source.id) ?? []
                latestResults = try database?.fetchLatestResults(sourceID: source.id) ?? [:]
                alerts = try database?.fetchAlerts() ?? []
                selectedNode = nodes.first
                await loadSelectedNodeDetails()
                statusMessage = nodes.isEmpty ? "已加载订阅配置，尚未导入节点" : "已加载 \(nodes.count) 个节点"
            }
            coreStatus = probeEngine.coreStatus
            await requestNotificationPermission()
            startScheduler()
        } catch {
            statusMessage = "初始化失败：\(error.localizedDescription)"
        }
    }

    func updateProbeConcurrency(_ value: Int) {
        probeConcurrency = min(max(value, 1), 16)
        saveProbeSettings()
    }

    func updateLatencySampleCount(_ value: Int) {
        latencySampleCount = min(max(value, 1), 20)
        saveProbeSettings()
    }

    func updateProbeTimeoutSeconds(_ value: Int) {
        probeTimeoutSeconds = min(max(value, 5), 120)
        if downloadNoDataTimeoutSeconds >= probeTimeoutSeconds {
            downloadNoDataTimeoutSeconds = max(probeTimeoutSeconds - 1, 1)
        }
        saveProbeSettings()
    }

    func updateDownloadNoDataTimeoutSeconds(_ value: Int) {
        downloadNoDataTimeoutSeconds = min(max(value, 1), max(probeTimeoutSeconds - 1, 1))
        saveProbeSettings()
    }

    func updateDownloadSizeMB(_ value: Int) {
        downloadSizeMB = min(max(value, 1), 500)
        saveProbeSettings()
    }

    func updateSortMetric(_ metric: NodeSortMetric) {
        sortMetric = metric
        switch metric {
        case .name, .latency, .packetLoss:
            sortDescending = false
        case .bandwidth:
            sortDescending = true
        }
        saveProbeSettings()
    }

    func toggleSortDirection() {
        sortDescending.toggle()
        saveProbeSettings()
    }

    var sortedNodes: [NodeRecord] {
        nodes.sorted { left, right in
            compare(left, right)
        }
    }

    func startProbeAll() {
        launchProbeTask { store in
            await store.probeAll(trigger: .manual)
        }
    }

    func startProbeSelectedNode() {
        launchProbeTask { store in
            await store.probeSelectedNode()
        }
    }

    func stopProbing() {
        guard isProbing else { return }
        statusMessage = "正在停止检测..."
        activeProbeTask?.cancel()
    }

    func refreshSubscription() async {
        guard !subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请先输入订阅链接"
            return
        }
        guard let database else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            var current = source ?? SubscriptionSource(url: subscriptionURL)
            current.url = subscriptionURL
            current.refreshIntervalMinutes = refreshIntervalMinutes
            current.updatedAt = Date()
            try database.saveSubscriptionSource(current)
            source = current

            statusMessage = "正在拉取订阅..."
            let body = try await fetcher.fetch(urlString: current.url)
            let parsed = try parser.parse(sourceID: current.id, body: body)
            try database.saveSnapshot(parsed.snapshot)
            nodes = try database.upsertNodes(parsed.nodes, sourceID: current.id)
            latestResults = try database.fetchLatestResults(sourceID: current.id)
            selectedNode = nodes.first
            await loadSelectedNodeDetails()
            statusMessage = "订阅刷新完成：\(nodes.count) 个有效节点，忽略 \(parsed.snapshot.ignoredLineCount) 行说明，\(parsed.snapshot.invalidLineCount) 行无效"
        } catch {
            statusMessage = "订阅刷新失败：\(error.localizedDescription)"
        }
    }

    func probeAll(trigger: RunTrigger = .manual) async {
        guard let database, let source else {
            statusMessage = "请先导入订阅"
            return
        }
        guard !nodes.isEmpty else {
            statusMessage = "没有可检测节点"
            return
        }
        guard !isProbing else { return }

        isProbing = true
        probingNodeIDs = []
        defer {
            isProbing = false
            probingNodeIDs = []
        }

        let run = ProbeRun(sourceID: source.id, trigger: trigger)
        saveProbeSettings()
        let profile = makeProbeProfile()
        var successCount = 0
        var failedCount = 0
        var timeoutCount = 0
        var completedCount = 0
        do {
            try database.createProbeRun(run)

            var pendingIterator = nodes.makeIterator()
            try await withThrowingTaskGroup(of: (NodeRecord, ProbeBundle).self) { group in
                for _ in 0..<min(max(profile.concurrency, 1), nodes.count) {
                    if let node = pendingIterator.next() {
                        probingNodeIDs.insert(node.id)
                        let engine = probeEngine
                        group.addTask {
                            let bundle = try await engine.probe(node: node, runID: run.id, profile: profile)
                            return (node, bundle)
                        }
                    }
                }

                while let (node, bundle) = try await group.next() {
                    try Task.checkCancellation()
                    completedCount += 1
                    statusMessage = "正在检测 \(completedCount)/\(nodes.count)：\(node.displayName)"
                    try persistProbeBundle(bundle, node: node, database: database)
                    probingNodeIDs.remove(node.id)

                    if bundle.result.outcome == .succeeded {
                        successCount += 1
                    } else if bundle.result.outcome == .failed {
                        failedCount += 1
                    } else {
                        timeoutCount += 1
                    }

                    if let nextNode = pendingIterator.next() {
                        try Task.checkCancellation()
                        probingNodeIDs.insert(nextNode.id)
                        let engine = probeEngine
                        group.addTask {
                            let bundle = try await engine.probe(node: nextNode, runID: run.id, profile: profile)
                            return (nextNode, bundle)
                        }
                    }
                }
            }

            let status: RunStatus = failedCount == 0 ? .succeeded : (successCount == 0 && timeoutCount == 0 ? .failed : .partial)
            try database.finishProbeRun(
                id: run.id,
                status: status,
                summary: "成功 \(successCount)，失败 \(failedCount)，超时 \(timeoutCount)"
            )
            alerts = try database.fetchAlerts()
            await loadSelectedNodeDetails()
            statusMessage = "检测完成：成功 \(successCount)，失败 \(failedCount)，超时 \(timeoutCount)"
        } catch is CancellationError {
            let interrupted = max(nodes.count - completedCount, 0)
            try? database.finishProbeRun(
                id: run.id,
                status: .partial,
                summary: "已停止：成功 \(successCount)，失败 \(failedCount)，超时 \(timeoutCount)，未完成 \(interrupted)"
            )
            alerts = (try? database.fetchAlerts()) ?? alerts
            await loadSelectedNodeDetails()
            statusMessage = "检测已停止：成功 \(successCount)，失败 \(failedCount)，超时 \(timeoutCount)，未完成 \(interrupted)"
        } catch {
            try? database.finishProbeRun(id: run.id, status: .failed, summary: error.localizedDescription)
            statusMessage = "检测失败：\(error.localizedDescription)"
        }
    }

    func probeSelectedNode() async {
        guard let selectedNode, let database, let source else { return }
        guard !isProbing else { return }

        isProbing = true
        probingNodeIDs = [selectedNode.id]
        defer {
            isProbing = false
            probingNodeIDs.remove(selectedNode.id)
        }

        let run = ProbeRun(sourceID: source.id, trigger: .manual)
        do {
            try database.createProbeRun(run)
            statusMessage = "正在检测：\(selectedNode.displayName)"
            let bundle = try await probeEngine.probe(node: selectedNode, runID: run.id, profile: makeProbeProfile())
            try persistProbeBundle(bundle, node: selectedNode, database: database)
            try database.finishProbeRun(
                id: run.id,
                status: bundle.result.outcome == .failed ? .failed : .succeeded,
                summary: probeSummary(for: bundle.result)
            )
            alerts = try database.fetchAlerts()
            await loadSelectedNodeDetails()
            statusMessage = probeSummary(for: bundle.result)
        } catch is CancellationError {
            try? database.finishProbeRun(id: run.id, status: .partial, summary: "已停止：\(selectedNode.displayName)")
            alerts = (try? database.fetchAlerts()) ?? alerts
            await loadSelectedNodeDetails()
            statusMessage = "已停止检测：\(selectedNode.displayName)"
        } catch {
            statusMessage = "单节点检测失败：\(error.localizedDescription)"
        }
    }

    func select(_ node: NodeRecord) {
        selectedNode = node
        Task { await loadSelectedNodeDetails() }
    }

    func loadSelectedNodeDetails() async {
        guard let database, let selectedNode else {
            selectedHistory = []
            selectedUnlocks = [:]
            return
        }
        do {
            let history = try database.fetchResults(nodeID: selectedNode.id, limit: 120)
            var unlocks: [UUID: [UnlockResult]] = [:]
            for result in history.prefix(8) {
                unlocks[result.id] = try database.fetchUnlockResults(resultID: result.id)
            }
            selectedHistory = history
            selectedUnlocks = unlocks
        } catch {
            statusMessage = "加载节点历史失败：\(error.localizedDescription)"
        }
    }

    private func startScheduler() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.runScheduledProbeIfNeeded()
            }
        }
    }

    private func runScheduledProbeIfNeeded() async {
        guard let source, source.isEnabled, !isRefreshing, !isProbing else { return }
        guard let latest = latestResults.values.map(\.createdAt).max() else { return }
        let interval = TimeInterval(max(refreshIntervalMinutes, 5) * 60)
        if Date().timeIntervalSince(latest) >= interval {
            launchProbeTask { store in
                await store.probeAll(trigger: .scheduled)
            }
        }
    }

    private func launchProbeTask(operation: @escaping @MainActor (AppStore) async -> Void) {
        guard activeProbeTask == nil else { return }
        let token = UUID()
        activeProbeToken = token
        let task = Task { [weak self] in
            guard let self else { return }
            await operation(self)
            await MainActor.run {
                if self.activeProbeToken == token {
                    self.activeProbeTask = nil
                    self.activeProbeToken = nil
                }
            }
        }
        activeProbeTask = task
    }

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func notify(alert: AlertEvent) {
        let content = UNMutableNotificationContent()
        content.title = "SubMax 节点异常"
        content.body = alert.message
        content.sound = .default
        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func persistProbeBundle(_ bundle: ProbeBundle, node: NodeRecord, database: SubMaxDatabase) throws {
        try database.saveProbeResult(bundle.result)
        try database.saveUnlockResults(bundle.unlockResults)
        let previous = try database.previousResult(before: bundle.result)
        let newAlerts = alertEngine.evaluate(node: node, previous: previous, current: bundle.result)
        for alert in newAlerts {
            try database.saveAlert(alert)
            notify(alert: alert)
        }
        latestResults[node.id] = bundle.result
    }

    private func probeSummary(for result: NodeProbeResult) -> String {
        switch result.outcome {
        case .succeeded:
            return "单节点检测成功"
        case .failed:
            return "单节点检测失败：\(result.failureReason ?? "未知错误")"
        case .timedOut:
            return "单节点检测超时：未判定为节点失败"
        }
    }

    private func loadProbeSettings() {
        let defaults = UserDefaults.standard
        let savedConcurrency = defaults.integer(forKey: "probeConcurrency")
        if savedConcurrency > 0 {
            probeConcurrency = min(max(savedConcurrency, 1), 16)
        }
        let savedLatencySampleCount = defaults.integer(forKey: "latencySampleCount")
        if savedLatencySampleCount > 0 {
            latencySampleCount = min(max(savedLatencySampleCount, 1), 20)
        }
        let savedProbeTimeout = defaults.integer(forKey: "probeTimeoutSeconds")
        if savedProbeTimeout > 0 {
            probeTimeoutSeconds = min(max(savedProbeTimeout, 5), 120)
        }
        let savedNoDataTimeout = defaults.integer(forKey: "downloadNoDataTimeoutSeconds")
        if savedNoDataTimeout > 0 {
            downloadNoDataTimeoutSeconds = min(max(savedNoDataTimeout, 1), max(probeTimeoutSeconds - 1, 1))
        }
        let savedDownloadSize = defaults.integer(forKey: "downloadSizeMB")
        if savedDownloadSize > 0 {
            downloadSizeMB = min(max(savedDownloadSize, 1), 500)
        }
        if let rawSortMetric = defaults.string(forKey: "sortMetric"),
           let metric = NodeSortMetric(rawValue: rawSortMetric) {
            sortMetric = metric
        }
        if defaults.object(forKey: "sortDescending") != nil {
            sortDescending = defaults.bool(forKey: "sortDescending")
        }
    }

    private func saveProbeSettings() {
        let defaults = UserDefaults.standard
        defaults.set(probeConcurrency, forKey: "probeConcurrency")
        defaults.set(latencySampleCount, forKey: "latencySampleCount")
        defaults.set(probeTimeoutSeconds, forKey: "probeTimeoutSeconds")
        defaults.set(downloadNoDataTimeoutSeconds, forKey: "downloadNoDataTimeoutSeconds")
        defaults.set(downloadSizeMB, forKey: "downloadSizeMB")
        defaults.set(sortMetric.rawValue, forKey: "sortMetric")
        defaults.set(sortDescending, forKey: "sortDescending")
    }

    private func makeProbeProfile() -> ProbeProfile {
        let bytes = downloadSizeMB * 1_000_000
        let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)")!
        return ProbeProfile(
            downloadURL: downloadURL,
            timeoutSeconds: TimeInterval(probeTimeoutSeconds),
            downloadLimitBytes: bytes,
            downloadNoDataTimeoutSeconds: TimeInterval(downloadNoDataTimeoutSeconds),
            latencySampleCount: latencySampleCount,
            concurrency: probeConcurrency
        )
    }

    private func compare(_ left: NodeRecord, _ right: NodeRecord) -> Bool {
        let leftResult = latestResults[left.id]
        let rightResult = latestResults[right.id]

        switch sortMetric {
        case .name:
            return compareStrings(left.displayName, right.displayName)
        case .bandwidth:
            return compareOptionalValues(
                leftResult?.downloadMBps,
                rightResult?.downloadMBps,
                tieLeft: left.displayName,
                tieRight: right.displayName
            )
        case .latency:
            return compareOptionalValues(
                leftResult?.latencyMilliseconds,
                rightResult?.latencyMilliseconds,
                tieLeft: left.displayName,
                tieRight: right.displayName
            )
        case .packetLoss:
            return compareOptionalValues(
                leftResult?.packetLossRate,
                rightResult?.packetLossRate,
                tieLeft: left.displayName,
                tieRight: right.displayName
            )
        }
    }

    private func compareOptionalValues(_ left: Double?, _ right: Double?, tieLeft: String, tieRight: String) -> Bool {
        switch (left, right) {
        case let (left?, right?) where left == right:
            return compareStrings(tieLeft, tieRight)
        case let (left?, right?):
            return sortDescending ? left > right : left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return compareStrings(tieLeft, tieRight)
        }
    }

    private func compareStrings(_ left: String, _ right: String) -> Bool {
        sortDescending
            ? left.localizedStandardCompare(right) == .orderedDescending
            : left.localizedStandardCompare(right) == .orderedAscending
    }
}
