import Foundation

class ClaudeService: ObservableObject {
    static let shared = ClaudeService()

    @Published var utilization5h: Double = 0.0 // 0.0 ~ 1.0
    @Published var resetsAt5h: String = ""
    @Published var utilization7d: Double = 0.0
    @Published var resetsAt7d: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // Prepaid "usage credits" balance + auto-reload (claude.ai billing).
    // Source: GET /api/organizations/{org}/prepaid/credits
    @Published var creditActive: Bool = false
    @Published var creditBalanceText: String = ""  // e.g. "$91.01"
    @Published var creditAutoReload: String = ""    // e.g. "자동충전: $5 이하 시 $15까지"

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private init() {}

    // The usage API returns utilization as a 0–100 percentage. Always divide by
    // 100 and clamp — the old `if > 1.0` heuristic broke at exactly 1% (1 > 1.0
    // is false → shown as 100%).
    static func normalize(_ utilization: Double?) -> Double {
        let v = (utilization ?? 0.0) / 100.0
        return min(max(v, 0.0), 1.0)
    }

    /// Formats a minor-unit money amount (e.g. cents) as a currency string.
    static func formatMoney(amountMinor: Int, exponent: Int, currency: String) -> String {
        let amount = Double(amountMinor) / pow(10.0, Double(exponent))
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = currency
        fmt.maximumFractionDigits = exponent
        return fmt.string(from: NSNumber(value: amount)) ?? String(format: "%.2f %@", amount, currency)
    }

    /// Maps org capabilities + rate-limit tier to a friendly plan label.
    static func planName(capabilities: [String], rateLimitTier: String?) -> String {
        let caps = Set(capabilities)
        var base = "Claude"
        if caps.contains("claude_max") { base = "Max" }
        else if caps.contains("claude_pro") { base = "Pro" }
        else if caps.contains("claude_team") { base = "Team" }
        else if caps.contains("claude_enterprise") { base = "Enterprise" }
        else if caps.contains("claude_free") { base = "Free" }

        // Max comes in 5x / 20x tiers — surface that from rate_limit_tier.
        if base == "Max", let t = rateLimitTier {
            if t.contains("20x") { base = "Max 20x" }
            else if t.contains("5x") { base = "Max 5x" }
        }
        return base
    }

    private struct OrgInfo: Codable {
        let uuid: String
        let capabilities: [String]?
        let rate_limit_tier: String?
    }

    // MARK: - Public API

    func fetchUsage(sessionKey: String, completion: @escaping () -> Void = {}) {
        guard !sessionKey.isEmpty else {
            DispatchQueue.main.async {
                self.errorMessage = "Session Key가 입력되지 않았습니다."
                completion()
            }
            return
        }

        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }

        if ConfigManager.shared.config.claudeOrgId.isEmpty {
            fetchOrgs(sessionKey: sessionKey) { org in
                if let org = org {
                    ConfigManager.shared.updateClaudeOrgId(org.uuid)
                    self.applyDetectedPlan(org)
                    self.fetchUsageWithOrg(sessionKey: sessionKey, orgId: org.uuid, completion: completion)
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Claude Org ID 조회에 실패했습니다. (세션 만료 가능성)"
                        self.isLoading = false
                        completion()
                    }
                }
            }
        } else {
            let orgId = ConfigManager.shared.config.claudeOrgId
            self.fetchUsageWithOrg(sessionKey: sessionKey, orgId: orgId, completion: completion)
        }
    }

    /// Refreshes only the subscription plan (used at launch / on connect when the
    /// org id is already cached, so plan stays current without re-deriving usage).
    func fetchPlan() {
        let key = ConfigManager.shared.config.claudeSessionKey
        guard !key.isEmpty, ConfigManager.shared.config.autoDetectPlan else { return }
        fetchOrgs(sessionKey: key) { org in
            if let org = org { self.applyDetectedPlan(org) }
        }
    }

    // MARK: - Internal

    private func applyDetectedPlan(_ org: OrgInfo) {
        guard ConfigManager.shared.config.autoDetectPlan else { return }
        let plan = Self.planName(capabilities: org.capabilities ?? [], rateLimitTier: org.rate_limit_tier)
        DispatchQueue.main.async {
            if ConfigManager.shared.config.autoDetectPlan {
                ConfigManager.shared.updateClaudePlan(plan)
            }
        }
    }

    private func fetchOrgs(sessionKey: String, completion: @escaping (OrgInfo?) -> Void) {
        guard let url = URL(string: "https://claude.ai/api/organizations") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let orgs = try? JSONDecoder().decode([OrgInfo].self, from: data), !orgs.isEmpty else {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
                    print("Claude API returned 403. Session key invalid or Cloudflare blocked.")
                }
                completion(nil)
                return
            }

            // Prefer the consumer (claude.ai) org over API-only orgs.
            let chosen = orgs.first(where: { org in
                (org.capabilities ?? []).contains { $0 == "chat" || $0.hasPrefix("claude_") }
            }) ?? orgs.first
            completion(chosen)
        }.resume()
    }

    private func fetchUsageWithOrg(sessionKey: String, orgId: String, completion: @escaping () -> Void) {
        fetchCredits(sessionKey: sessionKey, orgId: orgId) // refresh prepaid balance alongside usage

        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else {
            DispatchQueue.main.async {
                self.errorMessage = "잘못된 URL 설정"
                self.isLoading = false
                completion()
            }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { self.isLoading = false }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    completion()
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "데이터 수신 오류"
                    completion()
                }
                return
            }

            let rawJson = String(data: data, encoding: .utf8) ?? ""

            struct UsageResponse: Codable {
                struct Window: Codable {
                    let utilization: Double?
                    let resets_at: String?
                }
                let five_hour: Window?
                let seven_day: Window?
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
                DispatchQueue.main.async {
                    self.errorMessage = "인증 오류 (403). 세션 키를 다시 확인해주세요."
                    ConfigManager.shared.updateClaudeOrgId("") // force re-fetch next time
                    completion()
                }
                return
            }

            do {
                let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
                DispatchQueue.main.async {
                    if let fiveHour = usage.five_hour {
                        self.utilization5h = Self.normalize(fiveHour.utilization)
                        self.resetsAt5h = self.formatResetTime(fiveHour.resets_at)
                    }

                    if let sevenDay = usage.seven_day {
                        self.utilization7d = Self.normalize(sevenDay.utilization)
                        self.resetsAt7d = self.formatResetTimeWithDate(sevenDay.resets_at)
                    }

                    if usage.five_hour == nil && usage.seven_day == nil {
                        print("Unexpected response structure: \(rawJson)")
                        self.errorMessage = "사용량 정보를 파싱할 수 없습니다."
                    }
                    completion()
                }
            } catch {
                DispatchQueue.main.async {
                    print("JSON Parse error: \(error). Raw JSON: \(rawJson)")
                    self.errorMessage = "데이터 파싱 에러"
                    completion()
                }
            }
        }.resume()
    }

    // MARK: - Prepaid usage credits

    private func fetchCredits(sessionKey: String, orgId: String) {
        guard !sessionKey.isEmpty,
              let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/prepaid/credits") else { return }

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            struct AutoReload: Codable {
                let enabled: Bool?
                let threshold_in_minor_units: Int?
                let reload_to_in_minor_units: Int?
            }
            struct CreditsResponse: Codable {
                let amount: Int?
                let currency: String?
                let auto_reload_settings: AutoReload?
            }

            guard let data = data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let credits = try? JSONDecoder().decode(CreditsResponse.self, from: data),
                  let amount = credits.amount else {
                // No prepaid credits on this account (e.g. 404) — hide the section.
                DispatchQueue.main.async { self.creditActive = false }
                return
            }

            let currency = credits.currency ?? "USD"
            let balance = Self.formatMoney(amountMinor: amount, exponent: 2, currency: currency)

            var reload = ""
            if let ar = credits.auto_reload_settings, ar.enabled == true,
               let threshold = ar.threshold_in_minor_units,
               let reloadTo = ar.reload_to_in_minor_units {
                let t = Self.formatMoney(amountMinor: threshold, exponent: 2, currency: currency)
                let r = Self.formatMoney(amountMinor: reloadTo, exponent: 2, currency: currency)
                reload = "자동충전: \(t) 이하 시 \(r)까지"
            }

            DispatchQueue.main.async {
                self.creditActive = true
                self.creditBalanceText = balance
                self.creditAutoReload = reload
            }
        }.resume()
    }

    // MARK: - Date formatting

    private func formatResetTime(_ dateStr: String?) -> String {
        guard let dateStr = dateStr else { return "N/A" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var date = formatter.date(from: dateStr)
        if date == nil {
            let fallbackFormatter = ISO8601DateFormatter()
            date = fallbackFormatter.date(from: dateStr)
        }

        guard let validDate = date else { return dateStr }

        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(identifier: "ko_KR")
        outputFormatter.dateFormat = "a h시 m분" // e.g. "오후 3시 30분"
        return outputFormatter.string(from: validDate)
    }

    private func formatResetTimeWithDate(_ dateStr: String?) -> String {
        guard let dateStr = dateStr else { return "N/A" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var date = formatter.date(from: dateStr)
        if date == nil {
            let fallbackFormatter = ISO8601DateFormatter()
            date = fallbackFormatter.date(from: dateStr)
        }

        guard let validDate = date else { return dateStr }

        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(identifier: "ko_KR")
        outputFormatter.dateFormat = "M월 d일 a h시 m분" // e.g. "6월 24일 오후 4시 00분"
        return outputFormatter.string(from: validDate)
    }
}
