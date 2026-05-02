import Foundation

public enum NodeProtocol: String, Codable, CaseIterable, Sendable {
    case trojan
    case vmess
    case vless
}

public enum RunTrigger: String, Codable, CaseIterable, Sendable {
    case manual
    case scheduled
}

public enum RunStatus: String, Codable, CaseIterable, Sendable {
    case running
    case succeeded
    case partial
    case failed
}

public enum UnlockProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case netflix
    case openAI
    case gemini
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .netflix: return "Netflix"
        case .openAI: return "GPT"
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        }
    }
}

public enum UnlockStatus: String, Codable, CaseIterable, Sendable {
    case available
    case reachable
    case restricted
    case error
    case unknown
}

public enum AlertKind: String, Codable, CaseIterable, Sendable {
    case nodeDown
    case latencyRegression
    case speedRegression
}

public enum ProbeOutcome: String, Codable, CaseIterable, Sendable {
    case succeeded
    case failed
    case timedOut
}

public struct SubscriptionSource: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    public var refreshIntervalMinutes: Int
    public var isEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "主订阅",
        url: String,
        refreshIntervalMinutes: Int = 60,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct SubscriptionSnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var sourceID: UUID
    public var fetchedAt: Date
    public var rawHash: String
    public var rawLineCount: Int
    public var parsedNodeCount: Int
    public var ignoredLineCount: Int
    public var invalidLineCount: Int

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        fetchedAt: Date = Date(),
        rawHash: String,
        rawLineCount: Int,
        parsedNodeCount: Int,
        ignoredLineCount: Int,
        invalidLineCount: Int
    ) {
        self.id = id
        self.sourceID = sourceID
        self.fetchedAt = fetchedAt
        self.rawHash = rawHash
        self.rawLineCount = rawLineCount
        self.parsedNodeCount = parsedNodeCount
        self.ignoredLineCount = ignoredLineCount
        self.invalidLineCount = invalidLineCount
    }
}

public struct NodeRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var sourceID: UUID
    public var protocolType: NodeProtocol
    public var displayName: String
    public var host: String
    public var port: Int
    public var rawURI: String
    public var stableKey: String
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        protocolType: NodeProtocol,
        displayName: String,
        host: String,
        port: Int,
        rawURI: String,
        stableKey: String,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.protocolType = protocolType
        self.displayName = displayName
        self.host = host
        self.port = port
        self.rawURI = rawURI
        self.stableKey = stableKey
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ProbeProfile: Codable, Equatable, Sendable {
    public var latencyURL: URL
    public var downloadURL: URL
    public var timeoutSeconds: TimeInterval
    public var downloadLimitBytes: Int
    public var downloadDurationSeconds: TimeInterval
    public var downloadNoDataTimeoutSeconds: TimeInterval
    public var latencySampleCount: Int
    public var concurrency: Int
    public var enabledUnlockProviders: [UnlockProvider]

    public init(
        latencyURL: URL = URL(string: "http://www.gstatic.com/generate_204")!,
        downloadURL: URL = URL(string: "https://speed.cloudflare.com/__down?bytes=50000000")!,
        timeoutSeconds: TimeInterval = 20,
        downloadLimitBytes: Int = 50_000_000,
        downloadDurationSeconds: TimeInterval = 8,
        downloadNoDataTimeoutSeconds: TimeInterval = 5,
        latencySampleCount: Int = 5,
        concurrency: Int = 3,
        enabledUnlockProviders: [UnlockProvider] = UnlockProvider.allCases
    ) {
        self.latencyURL = latencyURL
        self.downloadURL = downloadURL
        self.timeoutSeconds = timeoutSeconds
        self.downloadLimitBytes = downloadLimitBytes
        self.downloadDurationSeconds = downloadDurationSeconds
        self.downloadNoDataTimeoutSeconds = downloadNoDataTimeoutSeconds
        self.latencySampleCount = latencySampleCount
        self.concurrency = concurrency
        self.enabledUnlockProviders = enabledUnlockProviders
    }
}

public struct ProbeRun: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var sourceID: UUID
    public var trigger: RunTrigger
    public var status: RunStatus
    public var startedAt: Date
    public var finishedAt: Date?
    public var summary: String?

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        trigger: RunTrigger,
        status: RunStatus = .running,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.trigger = trigger
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.summary = summary
    }
}

public struct NodeProbeResult: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var runID: UUID
    public var nodeID: UUID
    public var success: Bool
    public var outcome: ProbeOutcome
    public var latencyMilliseconds: Double?
    public var downloadMBps: Double?
    public var packetLossRate: Double?
    public var exitIP: String?
    public var exitCountry: String?
    public var exitRegion: String?
    public var exitCity: String?
    public var exitOrg: String?
    public var failureReason: String?
    public var logExcerpt: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        runID: UUID,
        nodeID: UUID,
        success: Bool,
        outcome: ProbeOutcome? = nil,
        latencyMilliseconds: Double? = nil,
        downloadMBps: Double? = nil,
        packetLossRate: Double? = nil,
        exitIP: String? = nil,
        exitCountry: String? = nil,
        exitRegion: String? = nil,
        exitCity: String? = nil,
        exitOrg: String? = nil,
        failureReason: String? = nil,
        logExcerpt: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.runID = runID
        self.nodeID = nodeID
        self.success = success
        self.outcome = outcome ?? (success ? .succeeded : .failed)
        self.latencyMilliseconds = latencyMilliseconds
        self.downloadMBps = downloadMBps
        self.packetLossRate = packetLossRate
        self.exitIP = exitIP
        self.exitCountry = exitCountry
        self.exitRegion = exitRegion
        self.exitCity = exitCity
        self.exitOrg = exitOrg
        self.failureReason = failureReason
        self.logExcerpt = logExcerpt
        self.createdAt = createdAt
    }
}

public struct UnlockResult: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var resultID: UUID
    public var provider: UnlockProvider
    public var status: UnlockStatus
    public var region: String?
    public var detail: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        resultID: UUID,
        provider: UnlockProvider,
        status: UnlockStatus,
        region: String? = nil,
        detail: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.resultID = resultID
        self.provider = provider
        self.status = status
        self.region = region
        self.detail = detail
        self.createdAt = createdAt
    }
}

public struct AlertEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var nodeID: UUID
    public var resultID: UUID
    public var kind: AlertKind
    public var message: String
    public var createdAt: Date
    public var acknowledgedAt: Date?

    public init(
        id: UUID = UUID(),
        nodeID: UUID,
        resultID: UUID,
        kind: AlertKind,
        message: String,
        createdAt: Date = Date(),
        acknowledgedAt: Date? = nil
    ) {
        self.id = id
        self.nodeID = nodeID
        self.resultID = resultID
        self.kind = kind
        self.message = message
        self.createdAt = createdAt
        self.acknowledgedAt = acknowledgedAt
    }
}

public struct ParsedSubscription: Equatable, Sendable {
    public var snapshot: SubscriptionSnapshot
    public var nodes: [NodeRecord]

    public init(snapshot: SubscriptionSnapshot, nodes: [NodeRecord]) {
        self.snapshot = snapshot
        self.nodes = nodes
    }
}
