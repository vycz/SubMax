import CryptoKit
import Foundation

public enum SubscriptionParserError: Error, LocalizedError, Equatable {
    case unreadablePayload

    public var errorDescription: String? {
        switch self {
        case .unreadablePayload:
            return "订阅内容无法识别，既不是明文节点列表，也不是有效 Base64。"
        }
    }
}

public struct SubscriptionParser: Sendable {
    private let metadataMarkers = [
        "剩余流量", "套餐到期", "官网", "更新订阅", "用不了", "流量：", "到期："
    ]

    public init() {}

    public func parse(sourceID: UUID, body: String, fetchedAt: Date = Date()) throws -> ParsedSubscription {
        let decoded = try decodeIfNeeded(body)
        let lines = decoded
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var nodes: [NodeRecord] = []
        var ignored = 0
        var invalid = 0

        for line in lines {
            if let node = parseLine(line, sourceID: sourceID, fetchedAt: fetchedAt) {
                if isMetadataNode(node.displayName) {
                    ignored += 1
                } else {
                    nodes.append(node)
                }
            } else if isLikelyMetadataLine(line) {
                ignored += 1
            } else {
                invalid += 1
            }
        }

        let snapshot = SubscriptionSnapshot(
            sourceID: sourceID,
            fetchedAt: fetchedAt,
            rawHash: Self.sha256(decoded),
            rawLineCount: lines.count,
            parsedNodeCount: nodes.count,
            ignoredLineCount: ignored,
            invalidLineCount: invalid
        )
        return ParsedSubscription(snapshot: snapshot, nodes: nodes)
    }

    private func decodeIfNeeded(_ body: String) throws -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return trimmed
        }

        let compact = trimmed
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty, let decoded = Self.decodeBase64String(compact) else {
            throw SubscriptionParserError.unreadablePayload
        }
        return decoded
    }

    private func parseLine(_ line: String, sourceID: UUID, fetchedAt: Date) -> NodeRecord? {
        if line.hasPrefix("trojan://") {
            return parseTrojan(line, sourceID: sourceID, fetchedAt: fetchedAt)
        }
        if line.hasPrefix("vmess://") {
            return parseVmess(line, sourceID: sourceID, fetchedAt: fetchedAt)
        }
        return nil
    }

    private func parseTrojan(_ line: String, sourceID: UUID, fetchedAt: Date) -> NodeRecord? {
        guard let components = URLComponents(string: line),
              let host = components.host,
              let port = components.port else {
            return nil
        }

        let fragmentName = components.percentEncodedFragment?.removingPercentEncoding ?? components.fragment
        let name = normalizedName(fragmentName, fallback: "Trojan \(host):\(port)")
        return NodeRecord(
            sourceID: sourceID,
            protocolType: .trojan,
            displayName: name,
            host: host,
            port: port,
            rawURI: line,
            stableKey: Self.sha256(line),
            createdAt: fetchedAt,
            updatedAt: fetchedAt
        )
    }

    private func parseVmess(_ line: String, sourceID: UUID, fetchedAt: Date) -> NodeRecord? {
        let encoded = String(line.dropFirst("vmess://".count))
        guard let decoded = Self.decodeBase64String(encoded),
              let data = decoded.data(using: .utf8),
              let payload = try? JSONDecoder().decode(VmessPayload.self, from: data),
              let port = Int(payload.port),
              !payload.add.isEmpty else {
            return nil
        }

        let name = normalizedName(payload.ps, fallback: "VMess \(payload.add):\(port)")
        return NodeRecord(
            sourceID: sourceID,
            protocolType: .vmess,
            displayName: name,
            host: payload.add,
            port: port,
            rawURI: line,
            stableKey: Self.sha256(line),
            createdAt: fetchedAt,
            updatedAt: fetchedAt
        )
    }

    private func normalizedName(_ value: String?, fallback: String) -> String {
        let candidate = (value ?? "")
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return candidate.isEmpty ? fallback : candidate
    }

    private func isMetadataNode(_ name: String) -> Bool {
        metadataMarkers.contains { name.localizedCaseInsensitiveContains($0) }
    }

    private func isLikelyMetadataLine(_ line: String) -> Bool {
        metadataMarkers.contains { line.localizedCaseInsensitiveContains($0) }
    }

    public static func decodeBase64String(_ value: String) -> String? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: normalized, options: [.ignoreUnknownCharacters]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct VmessPayload: Codable, Equatable {
    var v: String?
    var ps: String?
    var add: String
    var port: String
    var id: String
    var aid: String?
    var scy: String?
    var net: String?
    var type: String?
    var host: String?
    var path: String?
    var tls: String?
    var sni: String?
}
