import Foundation
import SQLite3

public final class SubMaxDatabase {
    private let db: OpaquePointer?
    private static let probeResultProjection = """
        r.id, r.run_id, r.node_id, r.success, r.latency_ms, r.download_mbps,
        r.packet_loss_rate, r.exit_ip, r.exit_country, r.exit_region, r.exit_city, r.exit_org,
        r.failure_reason, r.log_excerpt, r.created_at, r.outcome
        """
    private static let probeResultProjectionBare = """
        id, run_id, node_id, success, latency_ms, download_mbps,
        packet_loss_rate, exit_ip, exit_country, exit_region, exit_city, exit_org,
        failure_reason, log_excerpt, created_at, outcome
        """

    public init(path: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            throw SQLiteStoreError.openFailed(Self.message(handle))
        }
        db = handle
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public static func appSupportDatabase() throws -> SubMaxDatabase {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("SubMax", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try SubMaxDatabase(path: root.appendingPathComponent("submax.sqlite").path)
    }

    private func migrate() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS subscription_sources (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                url TEXT NOT NULL,
                refresh_interval_minutes INTEGER NOT NULL,
                is_enabled INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS subscription_snapshots (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                fetched_at REAL NOT NULL,
                raw_hash TEXT NOT NULL,
                raw_line_count INTEGER NOT NULL,
                parsed_node_count INTEGER NOT NULL,
                ignored_line_count INTEGER NOT NULL,
                invalid_line_count INTEGER NOT NULL
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_snapshots_source ON subscription_snapshots(source_id)")
        try execute("""
            CREATE TABLE IF NOT EXISTS nodes (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                protocol TEXT NOT NULL,
                display_name TEXT NOT NULL,
                host TEXT NOT NULL,
                port INTEGER NOT NULL,
                raw_uri TEXT NOT NULL,
                stable_key TEXT NOT NULL UNIQUE,
                is_active INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_nodes_source ON nodes(source_id)")
        try execute("""
            CREATE TABLE IF NOT EXISTS probe_runs (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                trigger TEXT NOT NULL,
                status TEXT NOT NULL,
                started_at REAL NOT NULL,
                finished_at REAL,
                summary TEXT
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_runs_source ON probe_runs(source_id)")
        try execute("""
            CREATE TABLE IF NOT EXISTS node_probe_results (
                id TEXT PRIMARY KEY,
                run_id TEXT NOT NULL,
                node_id TEXT NOT NULL,
                success INTEGER NOT NULL,
                latency_ms REAL,
                download_mbps REAL,
                packet_loss_rate REAL,
                exit_ip TEXT,
                exit_country TEXT,
                exit_region TEXT,
                exit_city TEXT,
                exit_org TEXT,
                failure_reason TEXT,
                log_excerpt TEXT,
                created_at REAL NOT NULL,
                outcome TEXT
            )
            """)
        try addColumnIfMissing(table: "node_probe_results", name: "packet_loss_rate", definition: "REAL")
        try addColumnIfMissing(table: "node_probe_results", name: "exit_ip", definition: "TEXT")
        try addColumnIfMissing(table: "node_probe_results", name: "exit_country", definition: "TEXT")
        try addColumnIfMissing(table: "node_probe_results", name: "exit_region", definition: "TEXT")
        try addColumnIfMissing(table: "node_probe_results", name: "exit_city", definition: "TEXT")
        try addColumnIfMissing(table: "node_probe_results", name: "exit_org", definition: "TEXT")
        try addColumnIfMissing(table: "node_probe_results", name: "outcome", definition: "TEXT")
        try execute("CREATE INDEX IF NOT EXISTS idx_results_node ON node_probe_results(node_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_results_run ON node_probe_results(run_id)")
        try execute("""
            CREATE TABLE IF NOT EXISTS unlock_results (
                id TEXT PRIMARY KEY,
                result_id TEXT NOT NULL,
                provider TEXT NOT NULL,
                status TEXT NOT NULL,
                region TEXT,
                detail TEXT NOT NULL,
                created_at REAL NOT NULL
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_unlock_result ON unlock_results(result_id)")
        try execute("""
            CREATE TABLE IF NOT EXISTS alert_events (
                id TEXT PRIMARY KEY,
                node_id TEXT NOT NULL,
                result_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                message TEXT NOT NULL,
                created_at REAL NOT NULL,
                acknowledged_at REAL
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_alert_created ON alert_events(created_at)")
    }

    public func saveSubscriptionSource(_ source: SubscriptionSource) throws {
        try execute("""
            INSERT INTO subscription_sources
            (id, name, url, refresh_interval_minutes, is_enabled, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            url = excluded.url,
            refresh_interval_minutes = excluded.refresh_interval_minutes,
            is_enabled = excluded.is_enabled,
            updated_at = excluded.updated_at
            """, [
                .text(source.id.uuidString), .text(source.name), .text(source.url),
                .int(source.refreshIntervalMinutes), .bool(source.isEnabled),
                .double(source.createdAt.timeIntervalSince1970), .double(source.updatedAt.timeIntervalSince1970)
            ])
    }

    public func loadSubscriptionSource() throws -> SubscriptionSource? {
        try first("SELECT * FROM subscription_sources ORDER BY created_at LIMIT 1", []) { statement in
            Self.mapSource(statement)
        }
    }

    public func saveSnapshot(_ snapshot: SubscriptionSnapshot) throws {
        try execute("""
            INSERT INTO subscription_snapshots
            (id, source_id, fetched_at, raw_hash, raw_line_count, parsed_node_count, ignored_line_count, invalid_line_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .text(snapshot.id.uuidString), .text(snapshot.sourceID.uuidString),
                .double(snapshot.fetchedAt.timeIntervalSince1970), .text(snapshot.rawHash),
                .int(snapshot.rawLineCount), .int(snapshot.parsedNodeCount),
                .int(snapshot.ignoredLineCount), .int(snapshot.invalidLineCount)
            ])
    }

    public func upsertNodes(_ nodes: [NodeRecord], sourceID: UUID) throws -> [NodeRecord] {
        try execute("UPDATE nodes SET is_active = 0 WHERE source_id = ?", [.text(sourceID.uuidString)])
        var saved: [NodeRecord] = []
        for incoming in nodes {
            if let existing = try first("SELECT id, created_at FROM nodes WHERE stable_key = ?", [.text(incoming.stableKey)], { statement in
                (
                    id: Self.columnText(statement, 0),
                    createdAt: Self.columnDouble(statement, 1)
                )
            }) {
                var node = incoming
                node.id = UUID(uuidString: existing.id) ?? incoming.id
                node.createdAt = Date(timeIntervalSince1970: existing.createdAt)
                node.updatedAt = Date()
                try writeNode(node)
                saved.append(node)
            } else {
                try writeNode(incoming)
                saved.append(incoming)
            }
        }
        return saved
    }

    public func fetchNodes(sourceID: UUID) throws -> [NodeRecord] {
        try all(
            "SELECT * FROM nodes WHERE source_id = ? AND is_active = 1 ORDER BY display_name",
            [.text(sourceID.uuidString)],
            Self.mapNode
        )
    }

    public func createProbeRun(_ run: ProbeRun) throws {
        try execute("""
            INSERT INTO probe_runs (id, source_id, trigger, status, started_at, finished_at, summary)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [
                .text(run.id.uuidString), .text(run.sourceID.uuidString),
                .text(run.trigger.rawValue), .text(run.status.rawValue),
                .double(run.startedAt.timeIntervalSince1970),
                .optionalDouble(run.finishedAt?.timeIntervalSince1970), .optionalText(run.summary)
            ])
    }

    public func finishProbeRun(id: UUID, status: RunStatus, summary: String) throws {
        try execute(
            "UPDATE probe_runs SET status = ?, finished_at = ?, summary = ? WHERE id = ?",
            [.text(status.rawValue), .double(Date().timeIntervalSince1970), .text(summary), .text(id.uuidString)]
        )
    }

    public func saveProbeResult(_ result: NodeProbeResult) throws {
        try execute("""
            INSERT INTO node_probe_results
            (id, run_id, node_id, success, latency_ms, download_mbps, packet_loss_rate, exit_ip, exit_country, exit_region, exit_city, exit_org, failure_reason, log_excerpt, created_at, outcome)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .text(result.id.uuidString), .text(result.runID.uuidString), .text(result.nodeID.uuidString),
                .bool(result.success), .optionalDouble(result.latencyMilliseconds),
                .optionalDouble(result.downloadMBps), .optionalDouble(result.packetLossRate),
                .optionalText(result.exitIP), .optionalText(result.exitCountry),
                .optionalText(result.exitRegion), .optionalText(result.exitCity),
                .optionalText(result.exitOrg), .optionalText(result.failureReason),
                .optionalText(result.logExcerpt), .double(result.createdAt.timeIntervalSince1970),
                .text(result.outcome.rawValue)
            ])
    }

    public func fetchLatestResults(sourceID: UUID) throws -> [UUID: NodeProbeResult] {
        let results = try all("""
            SELECT \(Self.probeResultProjection)
            FROM node_probe_results r
            JOIN nodes n ON n.id = r.node_id
            WHERE n.source_id = ?
            AND r.created_at = (
                SELECT MAX(r2.created_at)
                FROM node_probe_results r2
                WHERE r2.node_id = r.node_id
            )
            """, [.text(sourceID.uuidString)], Self.mapProbeResult)
        return Dictionary(uniqueKeysWithValues: results.map { ($0.nodeID, $0) })
    }

    public func fetchResults(nodeID: UUID, limit: Int = 30) throws -> [NodeProbeResult] {
        try all(
            "SELECT \(Self.probeResultProjectionBare) FROM node_probe_results WHERE node_id = ? ORDER BY created_at DESC LIMIT ?",
            [.text(nodeID.uuidString), .int(limit)],
            Self.mapProbeResult
        )
    }

    public func previousResult(before result: NodeProbeResult) throws -> NodeProbeResult? {
        try first("""
            SELECT \(Self.probeResultProjectionBare) FROM node_probe_results
            WHERE node_id = ? AND created_at < ?
            ORDER BY created_at DESC LIMIT 1
            """, [.text(result.nodeID.uuidString), .double(result.createdAt.timeIntervalSince1970)], Self.mapProbeResult)
    }

    public func saveUnlockResults(_ results: [UnlockResult]) throws {
        for result in results {
            try execute("""
                INSERT INTO unlock_results (id, result_id, provider, status, region, detail, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, [
                    .text(result.id.uuidString), .text(result.resultID.uuidString),
                    .text(result.provider.rawValue), .text(result.status.rawValue),
                    .optionalText(result.region), .text(result.detail),
                    .double(result.createdAt.timeIntervalSince1970)
                ])
        }
    }

    public func fetchUnlockResults(resultID: UUID) throws -> [UnlockResult] {
        try all(
            "SELECT * FROM unlock_results WHERE result_id = ? ORDER BY provider",
            [.text(resultID.uuidString)],
            Self.mapUnlockResult
        )
    }

    public func saveAlert(_ alert: AlertEvent) throws {
        try execute("""
            INSERT INTO alert_events (id, node_id, result_id, kind, message, created_at, acknowledged_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [
                .text(alert.id.uuidString), .text(alert.nodeID.uuidString), .text(alert.resultID.uuidString),
                .text(alert.kind.rawValue), .text(alert.message),
                .double(alert.createdAt.timeIntervalSince1970),
                .optionalDouble(alert.acknowledgedAt?.timeIntervalSince1970)
            ])
    }

    public func fetchAlerts(limit: Int = 20) throws -> [AlertEvent] {
        try all("SELECT * FROM alert_events ORDER BY created_at DESC LIMIT ?", [.int(limit)], Self.mapAlert)
    }

    private func writeNode(_ node: NodeRecord) throws {
        try execute("""
            INSERT INTO nodes
            (id, source_id, protocol, display_name, host, port, raw_uri, stable_key, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(stable_key) DO UPDATE SET
            source_id = excluded.source_id,
            protocol = excluded.protocol,
            display_name = excluded.display_name,
            host = excluded.host,
            port = excluded.port,
            raw_uri = excluded.raw_uri,
            is_active = 1,
            updated_at = excluded.updated_at
            """, [
                .text(node.id.uuidString), .text(node.sourceID.uuidString), .text(node.protocolType.rawValue),
                .text(node.displayName), .text(node.host), .int(node.port), .text(node.rawURI),
                .text(node.stableKey), .bool(node.isActive), .double(node.createdAt.timeIntervalSince1970),
                .double(node.updatedAt.timeIntervalSince1970)
            ])
    }

    private func addColumnIfMissing(table: String, name: String, definition: String) throws {
        let existing = try all("PRAGMA table_info(\(table))", []) { statement in
            Self.columnText(statement, 1)
        }
        if !existing.contains(name) {
            try execute("ALTER TABLE \(table) ADD COLUMN \(name) \(definition)")
        }
    }

    private func execute(_ sql: String, _ values: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return
            }
            if result != SQLITE_ROW {
                throw SQLiteStoreError.executeFailed(Self.message(db))
            }
        }
    }

    private func first<T>(_ sql: String, _ values: [SQLiteValue], _ map: (OpaquePointer?) throws -> T) throws -> T? {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return try map(statement)
        }
        if result == SQLITE_DONE {
            return nil
        }
        throw SQLiteStoreError.executeFailed(Self.message(db))
    }

    private func all<T>(_ sql: String, _ values: [SQLiteValue], _ map: (OpaquePointer?) throws -> T) throws -> [T] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        var output: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                output.append(try map(statement))
            } else if result == SQLITE_DONE {
                return output
            } else {
                throw SQLiteStoreError.executeFailed(Self.message(db))
            }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(Self.message(db))
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case .text(let string):
                result = sqlite3_bind_text(statement, position, string, -1, SQLITE_TRANSIENT)
            case .optionalText(let string):
                if let string {
                    result = sqlite3_bind_text(statement, position, string, -1, SQLITE_TRANSIENT)
                } else {
                    result = sqlite3_bind_null(statement, position)
                }
            case .int(let int):
                result = sqlite3_bind_int64(statement, position, sqlite3_int64(int))
            case .bool(let bool):
                result = sqlite3_bind_int(statement, position, bool ? 1 : 0)
            case .double(let double):
                result = sqlite3_bind_double(statement, position, double)
            case .optionalDouble(let double):
                if let double {
                    result = sqlite3_bind_double(statement, position, double)
                } else {
                    result = sqlite3_bind_null(statement, position)
                }
            }
            guard result == SQLITE_OK else {
                throw SQLiteStoreError.bindFailed(Self.message(db))
            }
        }
    }

    private static func mapSource(_ statement: OpaquePointer?) -> SubscriptionSource {
        SubscriptionSource(
            id: UUID(uuidString: columnText(statement, 0)) ?? UUID(),
            name: columnText(statement, 1),
            url: columnText(statement, 2),
            refreshIntervalMinutes: columnInt(statement, 3),
            isEnabled: columnBool(statement, 4),
            createdAt: Date(timeIntervalSince1970: columnDouble(statement, 5)),
            updatedAt: Date(timeIntervalSince1970: columnDouble(statement, 6))
        )
    }

    private static func mapNode(_ statement: OpaquePointer?) -> NodeRecord {
        NodeRecord(
            id: UUID(uuidString: columnText(statement, 0)) ?? UUID(),
            sourceID: UUID(uuidString: columnText(statement, 1)) ?? UUID(),
            protocolType: NodeProtocol(rawValue: columnText(statement, 2)) ?? .trojan,
            displayName: columnText(statement, 3),
            host: columnText(statement, 4),
            port: columnInt(statement, 5),
            rawURI: columnText(statement, 6),
            stableKey: columnText(statement, 7),
            isActive: columnBool(statement, 8),
            createdAt: Date(timeIntervalSince1970: columnDouble(statement, 9)),
            updatedAt: Date(timeIntervalSince1970: columnDouble(statement, 10))
        )
    }

    private static func mapProbeResult(_ statement: OpaquePointer?) -> NodeProbeResult {
        let columnCount = sqlite3_column_count(statement)
        return NodeProbeResult(
            id: UUID(uuidString: columnText(statement, 0)) ?? UUID(),
            runID: UUID(uuidString: columnText(statement, 1)) ?? UUID(),
            nodeID: UUID(uuidString: columnText(statement, 2)) ?? UUID(),
            success: columnBool(statement, 3),
            outcome: mapOutcome(statement, success: columnBool(statement, 3), columnCount: columnCount),
            latencyMilliseconds: optionalDouble(statement, 4),
            downloadMBps: optionalDouble(statement, 5),
            packetLossRate: columnCount > 9 ? optionalDouble(statement, 6) : nil,
            exitIP: columnCount > 9 ? optionalText(statement, 7) : nil,
            exitCountry: columnCount > 9 ? optionalText(statement, 8) : nil,
            exitRegion: columnCount > 9 ? optionalText(statement, 9) : nil,
            exitCity: columnCount > 9 ? optionalText(statement, 10) : nil,
            exitOrg: columnCount > 9 ? optionalText(statement, 11) : nil,
            failureReason: columnCount > 9 ? optionalText(statement, 12) : optionalText(statement, 6),
            logExcerpt: columnCount > 9 ? optionalText(statement, 13) : optionalText(statement, 7),
            createdAt: Date(timeIntervalSince1970: columnCount > 9 ? columnDouble(statement, 14) : columnDouble(statement, 8))
        )
    }

    private static func mapOutcome(_ statement: OpaquePointer?, success: Bool, columnCount: Int32) -> ProbeOutcome {
        if columnCount > 15,
           let raw = optionalText(statement, 15),
           let outcome = ProbeOutcome(rawValue: raw) {
            return outcome
        }
        return success ? .succeeded : .failed
    }

    private static func mapUnlockResult(_ statement: OpaquePointer?) -> UnlockResult {
        UnlockResult(
            id: UUID(uuidString: columnText(statement, 0)) ?? UUID(),
            resultID: UUID(uuidString: columnText(statement, 1)) ?? UUID(),
            provider: UnlockProvider(rawValue: columnText(statement, 2)) ?? .openAI,
            status: UnlockStatus(rawValue: columnText(statement, 3)) ?? .unknown,
            region: optionalText(statement, 4),
            detail: columnText(statement, 5),
            createdAt: Date(timeIntervalSince1970: columnDouble(statement, 6))
        )
    }

    private static func mapAlert(_ statement: OpaquePointer?) -> AlertEvent {
        AlertEvent(
            id: UUID(uuidString: columnText(statement, 0)) ?? UUID(),
            nodeID: UUID(uuidString: columnText(statement, 1)) ?? UUID(),
            resultID: UUID(uuidString: columnText(statement, 2)) ?? UUID(),
            kind: AlertKind(rawValue: columnText(statement, 3)) ?? .nodeDown,
            message: columnText(statement, 4),
            createdAt: Date(timeIntervalSince1970: columnDouble(statement, 5)),
            acknowledgedAt: optionalDouble(statement, 6).map(Date.init(timeIntervalSince1970:))
        )
    }

    private static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private static func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : columnText(statement, index)
    }

    private static func columnInt(_ statement: OpaquePointer?, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    private static func columnBool(_ statement: OpaquePointer?, _ index: Int32) -> Bool {
        sqlite3_column_int(statement, index) != 0
    }

    private static func columnDouble(_ statement: OpaquePointer?, _ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    private static func optionalDouble(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : columnDouble(statement, index)
    }

    private static func message(_ db: OpaquePointer?) -> String {
        guard let pointer = sqlite3_errmsg(db) else { return "unknown SQLite error" }
        return String(cString: pointer)
    }
}

private enum SQLiteValue {
    case text(String)
    case optionalText(String?)
    case int(Int)
    case bool(Bool)
    case double(Double)
    case optionalDouble(Double?)
}

public enum SQLiteStoreError: Error, LocalizedError, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case executeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "SQLite 打开失败：\(message)"
        case .prepareFailed(let message): return "SQLite 语句准备失败：\(message)"
        case .bindFailed(let message): return "SQLite 参数绑定失败：\(message)"
        case .executeFailed(let message): return "SQLite 执行失败：\(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
