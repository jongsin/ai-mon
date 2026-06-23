import SwiftUI
import AppKit

struct MainView: View {
    // true when hosted in the standalone window, false when in the menu bar popover.
    var isWindowMode: Bool = false

    @ObservedObject var configManager = ConfigManager.shared
    @ObservedObject var claudeService = ClaudeService.shared

    @State private var showSettings = false
    @State private var claudeKeyInput = ""
    @State private var claudePlanInput = ""

    // Account connection / manual fallback states
    @State private var isConnecting = false
    @State private var showManualEntry = false
    @State private var showHelpPopover = false
    @State private var isFetchingKey = false
    @State private var cookieError: BrowserCookieError? = nil
    @State private var showCookieAlert = false
    @State private var successAlert = false
    @State private var launchAtLogin = false
    @State private var loginItemError = false

    private var isConnected: Bool { !configManager.config.claudeSessionKey.isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            header

            if showSettings {
                settingsPanel
            } else {
                dashboard
            }

            Spacer()
            footer
        }
        .padding(16)
        .alert(isPresented: $showCookieAlert, error: cookieError) { _ in
            Button("확인", role: .cancel) {}
        } message: { error in
            if let desc = error.errorDescription { Text(desc) }
        }
        .alert("연동 완료 🎉", isPresented: $successAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("Claude 계정이 성공적으로 연동되었어요!")
        }
        .alert("자동 시작 설정 실패", isPresented: $loginItemError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("로그인 항목 등록에 실패했어요. AI.Mon을 응용 프로그램(Applications) 폴더로 옮긴 뒤 다시 시도하거나, 시스템 설정 > 일반 > 로그인 항목에서 직접 추가해 주세요.")
        }
        .onAppear {
            claudeKeyInput = configManager.config.claudeSessionKey
            claudePlanInput = configManager.config.claudePlan
            launchAtLogin = LoginItem.isEnabled
            refreshAll()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                if let imagePath = Bundle.main.path(forResource: "app_icon", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .cornerRadius(4)
                } else {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.orange)
                }
                Text("AI.Mon")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }

            Spacer()

            // Window <-> status bar toggle
            Button(action: {
                NotificationCenter.default.post(
                    name: isWindowMode ? .hideToStatusBar : .showAsWindow,
                    object: nil
                )
            }) {
                Image(systemName: isWindowMode ? "menubar.rectangle" : "macwindow")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help(isWindowMode ? "상태바로 접기" : "독립 창으로 보기")

            Button(action: { withAnimation { showSettings.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: showSettings ? "chevron.up.circle.fill" : "gearshape.fill")
                    Text(showSettings ? "닫기" : "설정")
                        .font(.system(size: 11, weight: .medium))
                }
            }

            Button(action: { refreshAll() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
            }
            .help("즉시 새로고침")
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    // MARK: - Settings panel

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("⚙️ 설정")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                accountSection

                Divider()

                // Subscription plan (auto-detected, with manual override)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Claude 구독 모델")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("자동 감지", isOn: Binding(
                            get: { configManager.config.autoDetectPlan },
                            set: { on in
                                configManager.updateAutoDetectPlan(on)
                                if on { claudeService.fetchPlan() }
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 10))
                    }

                    if configManager.config.autoDetectPlan {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                            Text(configManager.config.claudePlan.isEmpty ? "감지 중…" : configManager.config.claudePlan)
                                .font(.system(size: 12, weight: .semibold))
                            Text("(연동 시 자동 감지)")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        TextField("예: Pro, Max, Team", text: $claudePlanInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .onSubmit { configManager.updateClaudePlan(claudePlanInput) }
                    }
                }

                // Alarm settings (toggle + adjustable threshold)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { configManager.config.alarmEnabled },
                        set: { configManager.updateAlarmEnabled($0) }
                    )) {
                        Text("사용량 알람")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if configManager.config.alarmEnabled {
                        HStack {
                            Text("알람 기준")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int((configManager.config.alarmThreshold * 100).rounded()))% 초과")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        Slider(value: Binding(
                            get: { configManager.config.alarmThreshold },
                            set: { configManager.updateAlarmThreshold($0) }
                        ), in: 0.5...0.95, step: 0.05)
                        Text("5시간·주간 중 하나라도 이 값을 넘으면 상태바 아이콘이 빨갛게 깜빡여요")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Launch at login
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            if !LoginItem.setEnabled(newValue) {
                                loginItemError = true
                            }
                            launchAtLogin = LoginItem.isEnabled
                        }
                    )) {
                        Text("로그인 시 자동 시작")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Text("Mac을 켜면 메뉴바에 자동으로 떠요 (부팅 시엔 창은 안 뜸)")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }

                // Window opacity
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("창 투명도 (Opacity)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", configManager.config.windowOpacity * 100))
                            .font(.system(size: 10))
                    }
                    Slider(value: Binding(
                        get: { configManager.config.windowOpacity },
                        set: { configManager.updateWindowOpacity($0) }
                    ), in: 0.3...1.0)
                }

                Divider()

                HStack {
                    Button("초기화") {
                        claudePlanInput = "Pro"
                        configManager.updateClaudePlan("Pro")
                        configManager.updateWindowOpacity(1.0)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("완료") {
                        configManager.updateClaudePlan(claudePlanInput)
                        withAnimation { showSettings = false }
                        refreshAll()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
        .transition(.opacity)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude 계정")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            if isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("연동됨")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button(isConnecting ? "연동 중…" : "다시 연동") { connectAccount() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isConnecting)
                    Button("해제") { disconnectAccount() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                Button(action: { connectAccount() }) {
                    HStack(spacing: 6) {
                        if isConnecting {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        } else {
                            Image(systemName: "link")
                        }
                        Text(isConnecting ? "로그인 창에서 로그인해 주세요…" : "Claude 계정 연동하기")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting)

                Text("버튼을 누르면 Claude 로그인 창이 열려요. 로그인만 하면 키를 자동으로 가져와 연동해요.")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Manual / advanced fallback
            DisclosureGroup(isExpanded: $showManualEntry) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Button(action: { autoFetchSessionKey() }) {
                            HStack(spacing: 3) {
                                if isFetchingKey {
                                    ProgressView().controlSize(.small).scaleEffect(0.5)
                                        .frame(width: 10, height: 10)
                                } else {
                                    Image(systemName: "safari.fill").font(.system(size: 9))
                                }
                                Text("열려있는 브라우저에서 가져오기")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isFetchingKey)

                        Button(action: { showHelpPopover.toggle() }) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showHelpPopover, arrowEdge: .top) {
                            ManualGuideView()
                        }
                    }

                    TextField("sessionKey 직접 입력 (sk-ant-sid01-...)", text: $claudeKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))

                    Button("이 키로 저장") {
                        configManager.updateClaudeSessionKey(claudeKeyInput)
                        configManager.updateClaudeOrgId("")
                        refreshAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 6)
            } label: {
                Text("수동 입력 / 고급")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
            }
        }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.85, green: 0.45, blue: 0.25))
                    Text("Claude [\(configManager.config.claudePlan)]")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                if claudeService.isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else if let error = claudeService.errorMessage {
                    Text("에러 ⚠️")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .help(error)
                } else if !isConnected {
                    Text("설정 필요")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            if isConnected {
                usageBar(title: "5시간 사용량",
                         value: claudeService.utilization5h,
                         resets: claudeService.resetsAt5h,
                         colors: [Color(red: 0.95, green: 0.6, blue: 0.3),
                                  Color(red: 0.85, green: 0.45, blue: 0.25)])

                usageBar(title: "주간 사용량",
                         value: claudeService.utilization7d,
                         resets: claudeService.resetsAt7d,
                         colors: [Color(red: 0.95, green: 0.7, blue: 0.4),
                                  Color(red: 0.85, green: 0.5, blue: 0.3)])

                // Extra credit / overage — appears only when enabled on the account
                if claudeService.extraCreditActive {
                    extraCreditView
                }
            } else {
                Text("아직 연동된 계정이 없어요.\n설정에서 'Claude 계정 연동하기'를 눌러줘!")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.gridColor).opacity(0.3), lineWidth: 1)
        )
    }

    private func usageBar(title: String, value: Double, resets: String, colors: [Color]) -> some View {
        let isHigh = value >= configManager.config.alarmThreshold
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if isHigh {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                Spacer()
                Text(String(format: "%.1f%%", value * 100))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isHigh ? .red : .primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(NSColor.gridColor).opacity(0.5))
                        .frame(height: 8)
                    Capsule()
                        .fill(LinearGradient(
                            colors: isHigh ? [Color.red.opacity(0.8), Color.red] : colors,
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0.0), 1.0)), height: 8)
                }
            }
            .frame(height: 8)

            if !resets.isEmpty && claudeService.errorMessage == nil {
                HStack {
                    Spacer()
                    Text("리셋: \(resets)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var extraCreditView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                    Text("추가 크레딧 사용")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !claudeService.extraSpendText.isEmpty {
                    Text(claudeService.extraSpendText)
                        .font(.system(size: 12, weight: .semibold))
                }
            }

            if claudeService.extraPercent > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(NSColor.gridColor).opacity(0.5))
                            .frame(height: 8)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.purple.opacity(0.7), Color.purple],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(min(max(claudeService.extraPercent, 0.0), 1.0)), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Spacer()
                    Text("한도의 \(Int((claudeService.extraPercent * 100).rounded()))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("30초마다 자동 갱신 중")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: { NotificationCenter.default.post(name: .quitApp, object: nil) }) {
                Text("종료")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("AI.Mon 종료")

            Text("AI.Mon v1.4")
                .font(.system(size: 10, weight: .light))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 2)
    }

    // MARK: - Actions

    private func connectAccount() {
        isConnecting = true
        ClaudeLoginController.shared.start { key in
            isConnecting = false
            if let key = key, !key.isEmpty {
                configManager.updateClaudeSessionKey(key)
                configManager.updateClaudeOrgId("") // reset org for the (possibly new) account
                claudeKeyInput = key
                successAlert = true
                refreshAll()
            }
        }
    }

    private func disconnectAccount() {
        configManager.updateClaudeSessionKey("")
        configManager.updateClaudeOrgId("")
        claudeKeyInput = ""
        claudeService.utilization5h = 0
        claudeService.utilization7d = 0
        claudeService.resetsAt5h = ""
        claudeService.resetsAt7d = ""
        claudeService.errorMessage = nil
    }

    private func autoFetchSessionKey() {
        isFetchingKey = true
        BrowserCookieService.fetchSessionKey { result in
            isFetchingKey = false
            switch result {
            case .success(let key):
                self.claudeKeyInput = key
                self.configManager.updateClaudeSessionKey(key)
                self.configManager.updateClaudeOrgId("")
                self.successAlert = true
                self.refreshAll()
            case .failure(let error):
                self.cookieError = error
                self.showCookieAlert = true
            }
        }
    }

    private func refreshAll() {
        claudeService.fetchUsage(sessionKey: configManager.config.claudeSessionKey)
    }
}

// Manual Guide Popover View
struct ManualGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🔑 Claude Session Key 수동 복사 방법")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. 브라우저에서 [claude.ai](https://claude.ai)에 접속하여 로그인합니다.")
                Text("2. 페이지 빈 곳 우클릭 후 **[검사]** 선택 또는 키보드 **F12**를 누릅니다.")
                Text("3. 개발자 도구 상단 메뉴 중 **[Application]**(또는 **[애플리케이션]**, Safari의 경우 **[저장 공간]**) 탭을 선택합니다.")
                Text("4. 좌측 사이드바의 **[Cookies]** (또는 **[쿠키]**) -> `https://claude.ai`를 확장 및 클릭합니다.")
                Text("5. 쿠키 목록 중 **`sessionKey`** 라는 이름을 찾습니다.")
                Text("6. 해당 항목의 **Value**(값, `sk-ant-sid01-...`으로 시작) 부분을 더블 클릭하여 복사한 후 설정 창에 붙여넣습니다.")
            }
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
            .lineSpacing(3)
        }
        .padding(14)
        .frame(width: 320)
    }
}
