import Foundation
import AppKit

enum BrowserCookieError: LocalizedError {
    case noBrowsersRunning
    case browserNotRunning(String)
    case tabNotFound(String)
    case javaScriptDisabled(String)
    case invalidSessionKey
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .noBrowsersRunning:
            return "실행 중인 지원 브라우저(Chrome, Safari, Brave, Arc)가 없습니다. 브라우저를 열고 claude.ai에 로그인한 뒤 다시 시도해 주세요."
        case .browserNotRunning(let browser):
            return "\(browser) 브라우저가 실행 중이 아닙니다."
        case .tabNotFound(let browser):
            return "\(browser)에서 'claude.ai'가 열린 탭을 찾을 수 없습니다. 로그인된 탭이 열려있는지 확인해 주세요."
        case .javaScriptDisabled(let browser):
            return "\(browser) 브라우저의 설정에서 'Apple Events의 자바스크립트 허용' 옵션이 활성화되어 있지 않거나 권한이 거부되었습니다.\n\n해결 방법:\n* Chrome/Brave: 상단 메뉴바의 [보기] -> [개발자] -> [Apple Events의 자바스크립트 허용] 체크\n* Safari: [설정] -> [고급] -> [메뉴 막대에서 Develop 메뉴 보기] 체크 후, 상단 [Develop] -> [Allow JavaScript from Apple Events] 체크\n* Arc: [View] -> [Developer] -> [Allow JavaScript from Apple Events] 체크\n* macOS 보안 팝업이 뜰 경우 '확인'을 선택해 제어 권한을 허용해 주셔야 합니다."
        case .invalidSessionKey:
            return "쿠키에서 sessionKey를 찾을 수 없거나 만료되었습니다. claude.ai에 로그인되어 있는지 확인해 주세요."
        case .unknown(let msg):
            return "오류 발생: \(msg)\n\n브라우저에서 자바스크립트 허용 설정이 켜져 있고 claude.ai 탭이 열려있는지 확인해 주세요."
        }
    }
}

class BrowserCookieService {
    struct BrowserInfo {
        let name: String
        let bundleId: String
        let script: String
    }

    static func fetchSessionKey(completion: @escaping (Result<String, BrowserCookieError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let runningApps = NSWorkspace.shared.runningApplications
            
            // Supported browsers configuration
            let browsers = [
                BrowserInfo(
                    name: "Google Chrome",
                    bundleId: "com.google.Chrome",
                    script: """
                    tell application "Google Chrome"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if URL of t contains "claude.ai" then
                                    try
                                        return execute t javascript "document.cookie"
                                    on error err
                                        return "ERROR: " & err
                                    end try
                                end if
                            end repeat
                        end repeat
                        return "NOT_FOUND"
                    end tell
                    """
                ),
                BrowserInfo(
                    name: "Brave Browser",
                    bundleId: "com.brave.Browser",
                    script: """
                    tell application "Brave Browser"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if URL of t contains "claude.ai" then
                                    try
                                        return execute t javascript "document.cookie"
                                    on error err
                                        return "ERROR: " & err
                                    end try
                                end if
                            end repeat
                        end repeat
                        return "NOT_FOUND"
                    end tell
                    """
                ),
                BrowserInfo(
                    name: "Safari",
                    bundleId: "com.apple.Safari",
                    script: """
                    tell application "Safari"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if URL of t contains "claude.ai" then
                                    try
                                        return do JavaScript "document.cookie" in t
                                    on error err
                                        return "ERROR: " & err
                                    end try
                                end if
                            end repeat
                        end repeat
                        return "NOT_FOUND"
                    end tell
                    """
                ),
                BrowserInfo(
                    name: "Arc",
                    bundleId: "company.thebrowser.Browser",
                    script: """
                    tell application "Arc"
                        try
                            set theUrl to URL of active tab of front window
                            if theUrl contains "claude.ai" then
                                return execute active tab of front window javascript "document.cookie"
                            end if
                        on error err
                            return "ERROR: " & err
                        end try
                        return "NOT_FOUND"
                    end tell
                    """
                )
            ]
            
            // Filter only running browsers
            let runningBrowsers = browsers.filter { browser in
                runningApps.contains { app in
                    guard let bundleId = app.bundleIdentifier else { return false }
                    return bundleId.lowercased() == browser.bundleId.lowercased()
                }
            }
            
            if runningBrowsers.isEmpty {
                DispatchQueue.main.async {
                    completion(.failure(.noBrowsersRunning))
                }
                return
            }
            
            var lastError: BrowserCookieError? = nil
            
            for browser in runningBrowsers {
                guard let appleScript = NSAppleScript(source: browser.script) else {
                    continue
                }
                
                var errorInfo: NSDictionary?
                let resultEvent = appleScript.executeAndReturnError(&errorInfo)
                
                if let err = errorInfo {
                    let errMsg = err[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    print("AppleScript error on \(browser.name): \(errMsg)")
                    if errMsg.contains("not allowed") || errMsg.contains("권한") || errMsg.contains("-1743") {
                        lastError = .javaScriptDisabled(browser.name)
                    } else {
                        lastError = .unknown(errMsg)
                    }
                    continue
                }
                
                guard let resultString = resultEvent.stringValue else {
                    continue
                }
                
                if resultString == "NOT_FOUND" {
                    lastError = .tabNotFound(browser.name)
                    continue
                }
                
                if resultString.hasPrefix("ERROR:") {
                    if resultString.contains("자바스크립트") || resultString.contains("JavaScript") || resultString.contains("Apple Events") || resultString.contains("-1743") || resultString.contains("not allowed") {
                        lastError = .javaScriptDisabled(browser.name)
                    } else {
                        lastError = .unknown(resultString)
                    }
                    continue
                }
                
                // Parse sessionKey from cookies
                if let sessionKey = parseSessionKey(from: resultString) {
                    DispatchQueue.main.async {
                        completion(.success(sessionKey))
                    }
                    return
                } else {
                    lastError = .invalidSessionKey
                }
            }
            
            let finalError = lastError ?? .noBrowsersRunning
            DispatchQueue.main.async {
                completion(.failure(finalError))
            }
        }
    }
    
    private static func parseSessionKey(from cookieString: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "sessionKey=([^;\\s]+)", options: []) else {
            return nil
        }
        
        let nsRange = NSRange(cookieString.startIndex..<cookieString.endIndex, in: cookieString)
        if let match = regex.firstMatch(in: cookieString, options: [], range: nsRange) {
            if let range = Range(match.range(at: 1), in: cookieString) {
                return String(cookieString[range])
            }
        }
        
        return nil
    }
}
