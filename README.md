# AI.Mon

> macOS 메뉴바에서 Claude 사용량(5시간·주간)을 실시간으로 모니터링하는 가벼운 네이티브 앱

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-orange)
![license](https://img.shields.io/badge/license-MIT-green)

AI.Mon은 [claude.ai](https://claude.ai)의 사용량을 주기적으로 가져와 메뉴바와 대시보드에 표시합니다. 5시간 / 주간 한도에 가까워지면 메뉴바 아이콘이 깜빡여 알려줍니다.

> ⚠️ **비공식 도구입니다.** Anthropic과 무관하며, claude.ai의 문서화되지 않은 내부 엔드포인트를 사용합니다. 엔드포인트는 예고 없이 바뀔 수 있습니다. 개인 용도로만 사용하세요.

---

## ✨ 주요 기능

- 📊 **사용량 대시보드** — Claude 5시간 / 주간 사용률(%)과 리셋 시각 표시
- 🧭 **메뉴바 상주** — 메뉴바 아이콘에 현재 사용률(%)을 항상 표시
- 🪟 **윈도우 ↔ 메뉴바 하이브리드** — 독립 창으로 보거나, 창을 닫으면 메뉴바로 접힘 (클릭 시 팝오버)
- 🚨 **사용량 알람** — 5시간·주간 중 하나라도 임계값(기본 80%, 조정 가능)을 넘으면 메뉴바 아이콘이 빨갛게 깜빡임
- ✨ **구독 플랜 자동 감지** — 연동 시 플랜(Pro / Max / Max 5x 등)을 자동으로 인식
- 🔐 **인앱 로그인 연동** — 앱 안의 로그인 창에서 로그인하면 세션 키를 자동으로 가져와 연동 (수동 입력도 지원)
- 🚀 **로그인 시 자동 시작** — Mac 부팅 시 메뉴바에 조용히 자동 실행 (선택)
- 🎚️ **창 투명도 조절**

---

## 🧰 요구사항

- **macOS 14.0 (Sonoma) 이상**
- **Apple Silicon (arm64)** — 빌드 스크립트가 `arm64-apple-macos14.0`을 타깃으로 합니다
- **Xcode Command Line Tools** (`swiftc` 사용)
  ```bash
  xcode-select --install
  ```

---

## 🛠️ 빌드

저장소를 클론한 뒤 빌드 스크립트를 실행하면 됩니다. 별도의 Xcode 프로젝트는 필요 없습니다.

```bash
git clone <your-repo-url> ai-mon
cd ai-mon
./build.sh
```

빌드가 끝나면 현재 폴더에 **`AI.Mon.app`** 이 생성됩니다.

```bash
open "AI.Mon.app"
```

`build.sh`가 하는 일:
- `app_icon.png` → `.icns` 아이콘 생성
- `Info.plist` 작성 (메뉴바 앱: `LSUIElement = true`)
- `Sources/*.swift` 컴파일
- 로컬 실행용 **ad-hoc 코드 서명**

---

## 📦 설치 (선택)

`AI.Mon.app`을 원하는 위치에 두고 실행하면 됩니다. 응용 프로그램 폴더로 옮겨두면 편합니다.

```bash
mv "AI.Mon.app" /Applications/
```

> **Gatekeeper 안내**: ad-hoc 서명(미공증) 앱이라, 다른 곳에서 내려받아 처음 열 때 경고가 뜨면
> **앱을 우클릭 → "열기"** 로 한 번 실행하면 됩니다. (직접 빌드한 경우엔 보통 경고가 없습니다.)
>
> ⚠️ 로그인 자동 시작을 켰다면 **앱을 옮긴 뒤** 자동 시작 토글을 한 번 껐다 켜서 경로를 갱신하세요.

---

## 🚀 사용법

### 1) Claude 계정 연동

**설정(⚙️) → Claude 계정 → "Claude 계정 연동하기"** 를 누르면 앱 안에 Claude 로그인 창이 열립니다.
로그인만 하면 세션 키(`sessionKey`)를 자동으로 가져와 연동합니다. 개발자 도구나 별도 설정이 필요 없습니다.

> 자동 연동이 안 될 경우, 설정의 **"수동 입력 / 고급"** 에서
> 이미 로그인된 브라우저에서 가져오거나, `sessionKey` 값을 직접 붙여넣을 수 있습니다.

### 2) 메뉴바 ↔ 윈도우

- **메뉴바 아이콘 클릭** → 팝오버로 대시보드 보기
- **메뉴바 아이콘 우클릭** → 창으로 보기 / 새로고침 / 종료
- **창 헤더의 창 아이콘** → 독립 윈도우로 / **접기 아이콘** → 메뉴바로
- **창의 빨간 닫기 버튼** → 종료가 아니라 메뉴바로 접힘 (앱은 계속 실행)

### 3) 사용량 알람

**설정 → 사용량 알람** 토글을 켜고, **알람 기준** 슬라이더로 임계값(50%–95%, 기본 80%)을 지정합니다.
5시간·주간 중 하나라도 기준을 넘으면 메뉴바 아이콘이 빨간 경고로 깜빡입니다.

### 4) 로그인 시 자동 시작

**설정 → 로그인 시 자동 시작** 토글로 켜고 끕니다.

- **부팅/로그인 시 자동 실행** → 창 없이 **메뉴바에만 조용히** 상주
- **직접 실행**(Finder/Dock) → 평소처럼 **창 표시**

> 구현: 사용자 LaunchAgent(`~/Library/LaunchAgents/com.seanyoon.AIMon.launchatlogin.plist`)를 사용합니다.
> macOS의 **시스템 설정 → 일반 → 로그인 항목 → 백그라운드에서 허용** 에서도 확인/해제할 수 있습니다.

---

## 🔒 데이터 & 프라이버시

- 🔑 **세션 키는 로컬에만 저장됩니다.** 설정은 아래 경로에 보관되며, **이 저장소(repo) 밖**입니다.
  ```
  ~/.config/ai-mon/config.json
  ```
- 🌐 **외부 전송 없음.** 세션 키는 오직 `https://claude.ai` 공식 API 호출에만 사용됩니다. 분석/추적/서드파티 서버로의 전송이 일절 없습니다.
- 🚫 **git에 올라가지 않습니다.** `config.json`은 프로젝트 폴더 밖에 있고, `.gitignore`에도 안전장치로 포함되어 있어 인증 정보가 커밋될 일이 없습니다.

> 저장소를 공개하기 전, 만약을 위해 `git status`로 `config.json`이나 세션 키가 포함되지 않았는지 한 번 더 확인하세요.

### 설정 파일 형식 (`~/.config/ai-mon/config.json`)

> 아래는 **형식 예시**이며, 실제 키 값은 포함되어 있지 않습니다.

```json
{
  "claudeSessionKey": "sk-ant-sid01-...",
  "claudeOrgId": "00000000-0000-0000-0000-000000000000",
  "claudePlan": "Max",
  "autoDetectPlan": true,
  "alarmEnabled": true,
  "alarmThreshold": 0.8,
  "windowOpacity": 1.0,
  "updateInterval": 30.0
}
```

데이터 출처(비공식 엔드포인트):
- `GET https://claude.ai/api/organizations` — 조직 / 플랜 정보
- `GET https://claude.ai/api/organizations/{orgId}/usage` — 사용량

---

## 🗂️ 프로젝트 구조

```
ai-mon/
├── build.sh                       # 빌드 스크립트 (swiftc 컴파일 + 번들 생성)
├── app_icon.png                   # 앱 아이콘 원본
├── README.md
├── .gitignore
└── Sources/
    ├── App.swift                  # 앱 진입점 (AppDelegate 연결)
    ├── AppDelegate.swift          # 메뉴바·팝오버·윈도우 관리, 알람 깜빡임, 자동 갱신
    ├── Views.swift                # SwiftUI UI (대시보드 / 설정)
    ├── ClaudeService.swift        # 사용량·플랜 API 호출 및 파싱
    ├── ClaudeLoginService.swift   # 인앱 WKWebView 로그인 (세션 키 자동 캡처)
    ├── BrowserCookieService.swift # (폴백) 열려있는 브라우저 쿠키에서 세션 키 추출
    ├── LoginItemService.swift     # 로그인 시 자동 시작 (LaunchAgent)
    └── Config.swift               # 설정 저장/로드 (~/.config/ai-mon/config.json)
```

---

## 🩺 문제 해결

| 증상 | 해결 |
|------|------|
| **"인증 오류 (403)" / 사용량이 안 보임** | 세션이 만료됐을 수 있어요. 설정에서 **다시 연동**하세요. |
| **사용량이 0% 또는 갱신 안 됨** | 5시간 창이 막 리셋됐을 수 있어요(정상). 새로고침(↻) 후 확인하세요. |
| **자동 시작이 안 됨** | 앱을 옮겼다면 경로가 바뀐 거예요. 자동 시작 토글을 껐다 켜세요. |
| **"브라우저에서 가져오기" 실패** | 브라우저에서 `claude.ai`에 로그인한 탭을 연 뒤, 해당 브라우저의 *Apple Events용 JavaScript 허용* 설정을 켜야 합니다. 가장 쉬운 방법은 인앱 **"Claude 계정 연동하기"** 입니다. |
| **빌드 실패 (`swiftc: command not found`)** | `xcode-select --install` 로 Command Line Tools를 설치하세요. |

---

## 📄 라이선스

[MIT License](LICENSE) © 2026 Sean Yoon
