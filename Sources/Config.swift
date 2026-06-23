import Foundation

struct AppConfig: Codable {
    var claudeSessionKey: String = ""
    var claudeOrgId: String = ""
    var updateInterval: Double = 30.0 // Default: 30 seconds
    var claudePlan: String = "Pro"
    var windowOpacity: Double = 1.0
    var alarmEnabled: Bool = true // Flash menu bar icon when usage exceeds threshold
    var alarmThreshold: Double = 0.8 // 0.0 ~ 1.0, default 80%
    var autoDetectPlan: Bool = true // Read subscription plan from the API automatically

    init() {}

    enum CodingKeys: String, CodingKey {
        case claudeSessionKey, claudeOrgId, updateInterval, claudePlan, windowOpacity, alarmEnabled, alarmThreshold, autoDetectPlan
    }

    // Tolerant decoding: missing keys fall back to defaults so adding new
    // config fields never wipes a user's existing config.json.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claudeSessionKey = try c.decodeIfPresent(String.self, forKey: .claudeSessionKey) ?? ""
        claudeOrgId = try c.decodeIfPresent(String.self, forKey: .claudeOrgId) ?? ""
        updateInterval = try c.decodeIfPresent(Double.self, forKey: .updateInterval) ?? 30.0
        claudePlan = try c.decodeIfPresent(String.self, forKey: .claudePlan) ?? "Pro"
        windowOpacity = try c.decodeIfPresent(Double.self, forKey: .windowOpacity) ?? 1.0
        alarmEnabled = try c.decodeIfPresent(Bool.self, forKey: .alarmEnabled) ?? true
        alarmThreshold = try c.decodeIfPresent(Double.self, forKey: .alarmThreshold) ?? 0.8
        autoDetectPlan = try c.decodeIfPresent(Bool.self, forKey: .autoDetectPlan) ?? true
    }
}

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published var config: AppConfig
    private let fileURL: URL

    private init() {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let configDirectory = homeDirectory.appendingPathComponent(".config/ai-mon", isDirectory: true)

        // Ensure directory exists
        try? fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true, attributes: nil)

        self.fileURL = configDirectory.appendingPathComponent("config.json")

        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.config = decoded
            if self.config.updateInterval == 300.0 {
                self.config.updateInterval = 30.0
            }
        } else {
            self.config = AppConfig()
        }
    }

    func save() {
        objectWillChange.send()
        if let data = try? JSONEncoder().encode(self.config) {
            try? data.write(to: self.fileURL)
        }
    }

    func updateClaudeSessionKey(_ key: String) {
        config.claudeSessionKey = key
        save()
    }

    func updateClaudeOrgId(_ orgId: String) {
        config.claudeOrgId = orgId
        save()
    }

    func updateInterval(_ interval: Double) {
        config.updateInterval = interval
        save()
    }

    func updateClaudePlan(_ plan: String) {
        config.claudePlan = plan
        save()
    }

    func updateWindowOpacity(_ opacity: Double) {
        config.windowOpacity = opacity
        save()
    }

    func updateAlarmEnabled(_ enabled: Bool) {
        config.alarmEnabled = enabled
        save()
    }

    func updateAlarmThreshold(_ threshold: Double) {
        config.alarmThreshold = threshold
        save()
    }

    func updateAutoDetectPlan(_ enabled: Bool) {
        config.autoDetectPlan = enabled
        save()
    }
}
