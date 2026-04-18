import Darwin
import Foundation

public struct CoreStatus: Equatable, Sendable {
    public var binaryPath: String?
    public var message: String

    public var isAvailable: Bool { binaryPath != nil }

    public init(binaryPath: String?, message: String) {
        self.binaryPath = binaryPath
        self.message = message
    }
}

public struct SingBoxRuntime: Sendable {
    public let binaryURL: URL?

    public init(binaryURL: URL? = nil) {
        self.binaryURL = binaryURL ?? Self.discoverBinary()
    }

    public var status: CoreStatus {
        if let binaryURL {
            return CoreStatus(binaryPath: binaryURL.path, message: "已发现 sing-box: \(binaryURL.path)")
        }
        return CoreStatus(binaryPath: nil, message: "未发现 sing-box 内核。可运行 script/install_sing_box.sh 安装到 .submax/bin。")
    }

    public static func discoverBinary() -> URL? {
        let fileManager = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("sing-box"),
           fileManager.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        if let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("SubMax/bin/sing-box"),
           fileManager.isExecutableFile(atPath: appSupport.path) {
            return appSupport
        }

        let candidates = [
            URL(fileURLWithPath: ".submax/bin/sing-box").standardizedFileURL,
            URL(fileURLWithPath: "/opt/homebrew/bin/sing-box"),
            URL(fileURLWithPath: "/usr/local/bin/sing-box")
        ]
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("sing-box")
                if fileManager.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    public func runWithProxy<T>(
        for node: NodeRecord,
        timeoutSeconds: TimeInterval,
        operation: @escaping @Sendable (URLSession) async throws -> T
    ) async throws -> T {
        guard let binaryURL else {
            throw ProbeRuntimeError.coreMissing
        }

        let port = try Self.freePort()
        let config = try SingBoxConfigBuilder().makeConfig(for: node, listenPort: port)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubMax-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let configURL = tempDirectory.appendingPathComponent("sing-box.json")
        try config.write(to: configURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["run", "-c", configURL.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try await Task.sleep(nanoseconds: 700_000_000)
        if !process.isRunning {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "sing-box exited before probe"
            throw ProbeRuntimeError.coreLaunchFailed(output)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPSPort as String: port
        ]
        let session = URLSession(configuration: configuration)
        return try await operation(session)
    }

    private static func freePort() throws -> Int {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw ProbeRuntimeError.noFreePort }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_port = 0

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw ProbeRuntimeError.noFreePort }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &length)
            }
        }
        guard nameResult == 0 else { throw ProbeRuntimeError.noFreePort }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

public enum ProbeRuntimeError: Error, LocalizedError, Equatable {
    case coreMissing
    case coreLaunchFailed(String)
    case unsupportedNode(String)
    case noFreePort
    case noDownloadData(timeoutSeconds: TimeInterval)
    case probeTimedOut(timeoutSeconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .coreMissing:
            return "缺少 sing-box 内核，请运行 script/install_sing_box.sh 后重试。"
        case .coreLaunchFailed(let output):
            return "sing-box 启动失败：\(output.prefix(400))"
        case .unsupportedNode(let detail):
            return "节点暂不支持：\(detail)"
        case .noFreePort:
            return "无法分配本地代理端口。"
        case .noDownloadData(let timeoutSeconds):
            return "\(Int(timeoutSeconds)) 秒内没有下载到任何数据。"
        case .probeTimedOut(let timeoutSeconds):
            return "单节点检测超过 \(Int(timeoutSeconds)) 秒，已终止。"
        }
    }
}

struct SingBoxConfigBuilder {
    func makeConfig(for node: NodeRecord, listenPort: Int) throws -> String {
        let proxy: [String: Any]
        switch node.protocolType {
        case .trojan:
            proxy = try makeTrojanOutbound(node)
        case .vmess:
            proxy = try makeVmessOutbound(node)
        }

        let object: [String: Any] = [
            "log": ["level": "warn"],
            "inbounds": [[
                "type": "mixed",
                "tag": "mixed-in",
                "listen": "127.0.0.1",
                "listen_port": listenPort
            ]],
            "outbounds": [
                proxy,
                ["type": "direct", "tag": "direct"]
            ],
            "route": ["final": "proxy"]
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func makeTrojanOutbound(_ node: NodeRecord) throws -> [String: Any] {
        guard let components = URLComponents(string: node.rawURI),
              let password = components.user,
              let host = components.host,
              let port = components.port else {
            throw ProbeRuntimeError.unsupportedNode("Trojan URI 缺少密码、主机或端口")
        }

        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let sni = query["sni"] ?? query["peer"] ?? host
        let allowInsecure = query["allowInsecure"] == "1" || query["allowInsecure"] == "true"
        return [
            "type": "trojan",
            "tag": "proxy",
            "server": host,
            "server_port": port,
            "password": password,
            "tls": [
                "enabled": true,
                "server_name": sni,
                "insecure": allowInsecure
            ]
        ]
    }

    private func makeVmessOutbound(_ node: NodeRecord) throws -> [String: Any] {
        let encoded = String(node.rawURI.dropFirst("vmess://".count))
        guard let decoded = SubscriptionParser.decodeBase64String(encoded),
              let data = decoded.data(using: .utf8),
              let payload = try? JSONDecoder().decode(VmessPayload.self, from: data),
              let port = Int(payload.port) else {
            throw ProbeRuntimeError.unsupportedNode("VMess URI 无法解析")
        }

        var outbound: [String: Any] = [
            "type": "vmess",
            "tag": "proxy",
            "server": payload.add,
            "server_port": port,
            "uuid": payload.id,
            "security": payload.scy?.isEmpty == false ? payload.scy! : "auto",
            "alter_id": Int(payload.aid ?? "0") ?? 0
        ]

        if payload.tls == "tls" {
            outbound["tls"] = [
                "enabled": true,
                "server_name": payload.sni?.isEmpty == false ? payload.sni! : (payload.host ?? payload.add)
            ]
        }

        if let net = payload.net, net != "tcp", !net.isEmpty {
            switch net {
            case "ws":
                var transport: [String: Any] = ["type": "ws"]
                if let path = payload.path, !path.isEmpty {
                    transport["path"] = path
                }
                if let host = payload.host, !host.isEmpty {
                    transport["headers"] = ["Host": host]
                }
                outbound["transport"] = transport
            case "grpc":
                outbound["transport"] = [
                    "type": "grpc",
                    "service_name": payload.path ?? ""
                ]
            default:
                outbound["transport"] = ["type": net]
            }
        }
        return outbound
    }
}
