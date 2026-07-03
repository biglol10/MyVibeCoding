# FlowPilot_mac

FlowPilot은 활동 추적, 생산성 분류, 리포트 앱입니다. macOS는 SwiftUI 네이티브 앱으로 전환 중이며, 기존 Tauri/React/Rust 앱과 Windows 빌드는 유지합니다. 데스크톱 앱이 로컬에서 앱/창 사용량을 수집하고, 브라우저 확장은 탭 제목/URL 신호를 보조로 전달합니다. 수집한 데이터로 일간/주간 생산성 리포트, 차트, 타임라인, 분류 규칙, 제외 규칙, 표시 alias를 로컬에서 관리합니다.

현재 구성:

- Tauri v2 + React + Rust 데스크톱 앱
- `macos-native/` 아래 SwiftUI 네이티브 macOS 앱
- `browser-extension/` 아래 Chromium 브라우저 확장

## 다운로드

- macOS Swift Native 개인 설치 zip (권장): [FlowPilot_native_mac_arm64.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_native_mac_arm64.zip)
- macOS Swift Native DMG: [FlowPilot_native_mac_arm64.dmg](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_native_mac_arm64.dmg)
- macOS Tauri 개인 설치 zip: [FlowPilot_personal_mac_arm64.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_personal_mac_arm64.zip)
- macOS Tauri DMG: [FlowPilot_0.1.0_aarch64.dmg](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_0.1.0_aarch64.dmg)
- Windows setup: [FlowPilot_0.1.0_x64-setup.exe](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_0.1.0_x64-setup.exe)
- Windows portable: [FlowPilot-0.1.0-portable.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot-0.1.0-portable.zip)

현재 개인 설치 zip은 Apple Developer ID 서명과 공증이 없는 빌드입니다. GitHub에서 다운로드한 `FlowPilot.app`을 바로 실행하면 macOS Gatekeeper가 "손상되었으므로 휴지통으로 이동" 경고를 표시할 수 있습니다. 개인 Mac에서는 zip에 포함된 `install-flowpilot-native.command` 또는 `install-flowpilot-personal.command`로 설치하세요.

### macOS 처음 실행 방법

방법 1: Swift Native 개인 설치 zip 사용 (권장)

1. `FlowPilot_native_mac_arm64.zip` 압축을 풉니다.
2. `install-flowpilot-native.command`를 Finder에서 우클릭합니다.
3. `열기`를 선택합니다. 일반 더블클릭이 막히면 우클릭 `열기`를 사용해야 합니다.
4. 설치 스크립트가 `/Applications/FlowPilot.app`을 교체하고 격리 속성을 제거한 뒤 실행합니다.
5. 다음부터는 Applications에서 `FlowPilot`을 바로 실행합니다.

방법 2: 터미널에서 격리 속성 직접 제거

```bash
xattr -dr com.apple.quarantine /path/to/FlowPilot.app
open /path/to/FlowPilot.app
```

예를 들어 다운로드 폴더에서 zip 압축을 풀었다면 다음처럼 실행할 수 있습니다.

```bash
xattr -dr com.apple.quarantine ~/Downloads/FlowPilot_native_mac_arm64/FlowPilot.app
open ~/Downloads/FlowPilot_native_mac_arm64/FlowPilot.app
```

방법 3: 소스에서 직접 실행

```bash
git clone https://github.com/biglol10/MyVibeCoding.git
cd MyVibeCoding/FlowPilot_mac
cd macos-native
swift run FlowPilotNative
```

## 개발 환경

- Node.js 22 LTS 권장
- npm
- Rust stable toolchain
- Tauri CLI
- macOS Swift 앱 빌드 시 Xcode Command Line Tools 또는 Xcode

## 실행

SwiftUI 네이티브 macOS 앱:

```bash
cd macos-native
swift run FlowPilotNative
```

기존 Tauri 앱:

```bash
npm ci
npm run tauri -- dev
```

## macOS 권한

FlowPilot은 기본 실행 앱 정보는 추가 권한 없이 수집할 수 있지만, 더 정확한 macOS 활동 수집에는 사용자 승인이 필요합니다.

- Accessibility: 앱/창 메타데이터와 focused window title
- Screen Recording: 화면 이미지 저장 없이 visible window 목록과 제목
- Automation for Safari: Safari가 전면 앱일 때 active tab URL/title

권한은 실제로 실행하는 `/Applications/FlowPilot.app` 번들에 부여한 뒤 FlowPilot을 재시작하세요. 자세한 개발 메모는 [docs/macos-development.md](docs/macos-development.md)를 참고하세요.

## 브라우저 도메인 추적

Chrome과 Edge는 `browser-extension/`의 unpacked extension을 사용합니다. 확장은 활성 탭 도메인을 로컬 bridge인 `http://127.0.0.1:17321/browser-event`로 보냅니다.

Chrome 개발 중 확장 로드:

1. `chrome://extensions`를 엽니다.
2. Developer mode를 켭니다.
3. `browser-extension/` 폴더를 Load unpacked로 추가합니다.

Safari는 권한이 있을 때 네이티브 앱의 macOS Automation으로 처리합니다. active tab URL을 읽을 수 없으면 앱/창 추적으로 fallback합니다.

## 테스트

```bash
npm test
npm run build
npm test --prefix browser-extension
npm run e2e
cargo test --manifest-path src-tauri/Cargo.toml
swift test --package-path macos-native
```

브라우저 확장:

```bash
cd browser-extension
npm ci
npm test
```

## 빌드

프론트엔드 빌드:

```bash
npm run build
```

Tauri 앱 빌드:

```bash
npm run tauri -- build
```

Swift Native 개인 설치 zip/DMG 다시 만들기:

```bash
npm run package:macos:native
npm run package:macos:native:dmg
cp release/FlowPilot_native_mac_arm64.zip ../downloads/FlowPilot_mac/FlowPilot_native_mac_arm64.zip
cp release/FlowPilot_native_mac_arm64.dmg ../downloads/FlowPilot_mac/FlowPilot_native_mac_arm64.dmg
```

macOS 개인 설치 zip 다시 만들기:

```bash
npm ci
npm --prefix browser-extension ci
npm --prefix browser-extension run build
npm run package:macos:personal
cp release/FlowPilot_personal_mac_arm64.zip ../downloads/FlowPilot_mac/FlowPilot_personal_mac_arm64.zip
cp src-tauri/target/release/bundle/dmg/FlowPilot_0.1.0_aarch64.dmg ../downloads/FlowPilot_mac/FlowPilot_0.1.0_aarch64.dmg
```

스크립트 결과:

- `release/FlowPilot_personal_mac_arm64.zip`
- `downloads/FlowPilot_mac/FlowPilot_0.1.0_aarch64.dmg`

공개 배포용 DMG/zip은 Developer ID 서명과 Apple notarization이 필요합니다.

```bash
FLOWPILOT_DEVELOPER_ID="Developer ID Application: Your Name (TEAMID1234)" \
APPLE_NOTARY_KEYCHAIN_PROFILE="FlowPilotNotary" \
npm run package:macos:release
npm run package:macos:distribution
```

개인용 ad-hoc 빌드는 자신의 Mac 설치 용도입니다. 공개 다운로드나 외부 배포용으로 올리려면 Developer ID 서명과 notarization이 필요합니다. 자세한 배포 메모는 [docs/macos-distribution.md](docs/macos-distribution.md)를 참고하세요.

## 폴더 구조

- `src`: React UI
- `src-tauri`: Tauri/Rust 데스크톱 앱
- `macos-native`: SwiftUI 네이티브 macOS 앱
- `browser-extension`: Chrome 확장
- `scripts`: 배포 패키징 스크립트
- `docs`: 설계 문서와 작업 계획

## 안전 메모

- 브라우저 bridge는 loopback에서만 listen합니다.
- macOS idle time은 지원되는 환경에서 active usage에서 제외합니다.
- 브라우저/창 관찰 데이터는 무한히 커지지 않도록 pruning합니다.
- Rule list는 add, edit, disable, delete 흐름을 지원합니다.
