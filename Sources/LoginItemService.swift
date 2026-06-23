import Foundation

/// Manages whether AI.Mon launches at login.
///
/// Uses a per-user LaunchAgent plist instead of SMAppService: this app is
/// ad-hoc signed and run from a build folder, for which SMAppService reports
/// `.notFound` and refuses to register. A LaunchAgent works regardless of code
/// signature or install location. macOS surfaces it in
/// System Settings → General → Login Items → "Allow in the Background".
enum LoginItem {
    private static let label = "com.seanyoon.AIMon.launchatlogin"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// True if the login agent is currently installed.
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Install / remove the login agent. Returns true on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let fm = FileManager.default

        if enabled {
            guard let exec = Bundle.main.executablePath else { return false }
            do {
                try fm.createDirectory(at: plistURL.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                let plist: [String: Any] = [
                    "Label": label,
                    // "--at-login" lets the app know it was started by the login
                    // agent, so it can stay in the menu bar instead of opening a
                    // window (manual launches omit it and show the window).
                    "ProgramArguments": [exec, "--at-login"],
                    "RunAtLoad": true,
                    "LimitLoadToSessionType": "Aqua", // GUI session only
                    "ProcessType": "Interactive"
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                              format: .xml, options: 0)
                try data.write(to: plistURL)
                return true
            } catch {
                print("LoginItem enable failed: \(error.localizedDescription)")
                return false
            }
        } else {
            guard fm.fileExists(atPath: plistURL.path) else { return true }
            do {
                try fm.removeItem(at: plistURL)
                return true
            } catch {
                print("LoginItem disable failed: \(error.localizedDescription)")
                return false
            }
        }
    }
}
