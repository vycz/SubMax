import Foundation

public struct ProbeBundle: Sendable {
    public var result: NodeProbeResult
    public var unlockResults: [UnlockResult]

    public init(result: NodeProbeResult, unlockResults: [UnlockResult]) {
        self.result = result
        self.unlockResults = unlockResults
    }
}

public struct ExitIPInfo: Codable, Equatable, Sendable {
    public var ip: String?
    public var country: String?
    public var region: String?
    public var city: String?
    public var org: String?

    public init(ip: String? = nil, country: String? = nil, region: String? = nil, city: String? = nil, org: String? = nil) {
        self.ip = ip
        self.country = country
        self.region = region
        self.city = city
        self.org = org
    }
}

private struct LatencyMeasurement: Sendable {
    var bestMilliseconds: Double
    var packetLossRate: Double
}

public struct ProbeEngine: Sendable {
    private let runtime: SingBoxRuntime

    public init(runtime: SingBoxRuntime = SingBoxRuntime()) {
        self.runtime = runtime
    }

    public var coreStatus: CoreStatus { runtime.status }

    public func probe(node: NodeRecord, runID: UUID, profile: ProbeProfile) async throws -> ProbeBundle {
        do {
            return try await runtime.runWithProxy(for: node, timeoutSeconds: profile.timeoutSeconds) { session in
                let deadline = Date().addingTimeInterval(profile.timeoutSeconds)
                try Task.checkCancellation()
                let latency = try await Self.measureLatency(
                    url: profile.latencyURL,
                    session: session,
                    sampleCount: profile.latencySampleCount
                )
                try Task.checkCancellation()
                let exitIPInfo = try await Self.fetchExitIPInfo(
                    session: session,
                    timeoutSeconds: min(Self.remainingSeconds(until: deadline), 3)
                )

                if Self.remainingSeconds(until: deadline) <= 0 {
                    let result = NodeProbeResult(
                        runID: runID,
                        nodeID: node.id,
                        success: false,
                        outcome: .timedOut,
                        latencyMilliseconds: latency.bestMilliseconds,
                        packetLossRate: latency.packetLossRate,
                        exitIP: exitIPInfo.ip,
                        exitCountry: exitIPInfo.country,
                        exitRegion: exitIPInfo.region,
                        exitCity: exitIPInfo.city,
                        exitOrg: exitIPInfo.org,
                        failureReason: "检测超时，已保留延迟/丢包/出口信息，未判定为节点失败。"
                    )
                    return ProbeBundle(result: result, unlockResults: [])
                }

                let speed: Double
                do {
                    try Task.checkCancellation()
                    speed = try await Self.measureDownloadSpeed(
                        url: profile.downloadURL,
                        session: session,
                        limitBytes: profile.downloadLimitBytes,
                        durationSeconds: min(profile.downloadDurationSeconds, Self.remainingSeconds(until: deadline)),
                        noDataTimeoutSeconds: min(profile.downloadNoDataTimeoutSeconds, max(Self.remainingSeconds(until: deadline), 1))
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    let result = NodeProbeResult(
                        runID: runID,
                        nodeID: node.id,
                        success: false,
                        outcome: .failed,
                        latencyMilliseconds: latency.bestMilliseconds,
                        packetLossRate: latency.packetLossRate,
                        exitIP: exitIPInfo.ip,
                        exitCountry: exitIPInfo.country,
                        exitRegion: exitIPInfo.region,
                        exitCity: exitIPInfo.city,
                        exitOrg: exitIPInfo.org,
                        failureReason: "下载测速失败：\(message)"
                    )
                    return ProbeBundle(result: result, unlockResults: [])
                }

                var result = NodeProbeResult(
                    runID: runID,
                    nodeID: node.id,
                    success: true,
                    outcome: .succeeded,
                    latencyMilliseconds: latency.bestMilliseconds,
                    downloadMBps: speed,
                    packetLossRate: latency.packetLossRate,
                    exitIP: exitIPInfo.ip,
                    exitCountry: exitIPInfo.country,
                    exitRegion: exitIPInfo.region,
                    exitCity: exitIPInfo.city,
                    exitOrg: exitIPInfo.org
                )

                let remaining = Self.remainingSeconds(until: deadline)
                guard remaining > 0 else {
                    result.outcome = .timedOut
                    result.failureReason = "检测超时，已保留延迟/丢包/下载速度/出口信息，未判定为节点失败。"
                    return ProbeBundle(result: result, unlockResults: [])
                }

                do {
                    let resultID = result.id
                    let unlocks = try await Self.withTimeout(seconds: remaining) {
                        try Task.checkCancellation()
                        return try await Self.checkUnlocks(
                            resultID: resultID,
                            providers: profile.enabledUnlockProviders,
                            session: session,
                            timeoutSeconds: remaining
                        )
                    }
                    return ProbeBundle(result: result, unlockResults: unlocks)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    result.outcome = .timedOut
                    result.failureReason = "解锁检测超时，已保留延迟/丢包/下载速度/出口信息，未判定为节点失败。"
                    let unlocks = profile.enabledUnlockProviders.map {
                        UnlockResult(resultID: result.id, provider: $0, status: .unknown, detail: "检测超时，未完成解锁检查。")
                    }
                    return ProbeBundle(result: result, unlockResults: unlocks)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let isTimeout = (error as? ProbeRuntimeError) == .probeTimedOut(timeoutSeconds: profile.timeoutSeconds)
            let result = NodeProbeResult(
                runID: runID,
                nodeID: node.id,
                success: false,
                outcome: isTimeout ? .timedOut : .failed,
                failureReason: isTimeout
                    ? "检测超时，结果未判定为节点失败。"
                    : ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription),
                logExcerpt: String(describing: error)
            )
            let unlocks = profile.enabledUnlockProviders.map {
                UnlockResult(resultID: result.id, provider: $0, status: .unknown, detail: "节点探测失败，未执行解锁检测。")
            }
            return ProbeBundle(result: result, unlockResults: unlocks)
        }
    }

    private static func remainingSeconds(until deadline: Date) -> TimeInterval {
        max(deadline.timeIntervalSinceNow, 0)
    }

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(max(seconds, 1) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw ProbeRuntimeError.probeTimedOut(timeoutSeconds: seconds)
            }

            guard let value = try await group.next() else {
                throw ProbeRuntimeError.probeTimedOut(timeoutSeconds: seconds)
            }
            group.cancelAll()
            return value
        }
    }

    private static func measureLatency(url: URL, session: URLSession, sampleCount: Int) async throws -> LatencyMeasurement {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let attempts = max(sampleCount, 1)
        var samples: [Double] = []
        for _ in 0..<attempts {
            let start = Date()
            do {
                _ = try await session.data(for: request)
                samples.append(Date().timeIntervalSince(start) * 1000)
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                continue
            }
        }
        guard let best = samples.min() else {
            throw URLError(.cannotConnectToHost)
        }
        let lost = attempts - samples.count
        return LatencyMeasurement(
            bestMilliseconds: best,
            packetLossRate: Double(lost) / Double(attempts)
        )
    }

    private static func measureDownloadSpeed(
        url: URL,
        session: URLSession,
        limitBytes: Int,
        durationSeconds: TimeInterval,
        noDataTimeoutSeconds: TimeInterval
    ) async throws -> Double {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = noDataTimeoutSeconds
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        let start = Date()
        var received = 0
        for try await _ in bytes {
            received += 1
            let elapsed = Date().timeIntervalSince(start)
            if received >= limitBytes || (elapsed >= durationSeconds && received >= 128_000) {
                break
            }
        }

        if received == 0, Date().timeIntervalSince(start) >= noDataTimeoutSeconds {
            throw ProbeRuntimeError.noDownloadData(timeoutSeconds: noDataTimeoutSeconds)
        }
        guard received > 0 else {
            throw URLError(.zeroByteResource)
        }
        let elapsed = max(Date().timeIntervalSince(start), 0.001)
        return (Double(received) / 1_000_000.0) / elapsed
    }

    private static func checkUnlocks(
        resultID: UUID,
        providers: [UnlockProvider],
        session: URLSession,
        timeoutSeconds: TimeInterval
    ) async throws -> [UnlockResult] {
        var results: [UnlockResult] = []
        for provider in providers {
            try Task.checkCancellation()
            let result = try await check(
                provider: provider,
                resultID: resultID,
                session: session,
                timeoutSeconds: min(timeoutSeconds, 6)
            )
            results.append(result)
        }
        return results
    }

    private static func fetchExitIPInfo(session: URLSession, timeoutSeconds: TimeInterval) async throws -> ExitIPInfo {
        guard let url = URL(string: "http://ip-api.com/json/?fields=status,country,regionName,city,isp,org,query") else {
            return ExitIPInfo()
        }
        do {
            var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                return ExitIPInfo()
            }
            let payload = try JSONDecoder().decode(ExitIPPayload.self, from: data)
            return ExitIPInfo(
                ip: payload.query,
                country: payload.country,
                region: payload.regionName,
                city: payload.city,
                org: payload.org ?? payload.isp
            )
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            return ExitIPInfo()
        }
    }

    private static func check(
        provider: UnlockProvider,
        resultID: UUID,
        session: URLSession,
        timeoutSeconds: TimeInterval
    ) async throws -> UnlockResult {
        let url: URL
        switch provider {
        case .netflix:
            url = URL(string: "https://www.netflix.com/title/80018499")!
        case .openAI:
            url = URL(string: "https://chat.openai.com/cdn-cgi/trace")!
        case .gemini:
            url = URL(string: "https://gemini.google.com/")!
        case .claude:
            url = URL(string: "https://claude.ai/")!
        }

        do {
            var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
            request.httpMethod = "GET"
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
            let region = extractTraceRegion(body)
            let status = classify(provider: provider, statusCode: code, body: body)
            return UnlockResult(
                resultID: resultID,
                provider: provider,
                status: status,
                region: region,
                detail: "HTTP \(code)"
            )
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            return UnlockResult(
                resultID: resultID,
                provider: provider,
                status: .error,
                detail: error.localizedDescription
            )
        }
    }

    private static func classify(provider: UnlockProvider, statusCode: Int, body: String) -> UnlockStatus {
        if (200..<400).contains(statusCode) {
            return provider == .openAI ? .reachable : .available
        }
        if statusCode == 401 || statusCode == 403 || body.localizedCaseInsensitiveContains("not available") {
            return .restricted
        }
        if statusCode > 0 {
            return .reachable
        }
        return .unknown
    }

    private static func extractTraceRegion(_ body: String) -> String? {
        for line in body.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("loc=") {
                return String(line.dropFirst(4))
            }
        }
        return nil
    }
}

private struct ExitIPPayload: Decodable {
    var status: String?
    var country: String?
    var regionName: String?
    var city: String?
    var isp: String?
    var org: String?
    var query: String?
}
