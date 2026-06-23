# FlowPilot_mac

FlowPilot은 Tauri 기반 활동 추적, 생산성 분류, 리포트 앱입니다. 데스크톱 앱이 로컬에서 활동 데이터를 수집하고, 브라우저 확장은 탭 제목/URL 신호를 보조로 전달합니다.

## 다운로드

- macOS DMG: [FlowPilot_0.1.0_aarch64.dmg](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_0.1.0_aarch64.dmg)
- macOS zip: [FlowPilot_mac_arm64.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_mac_arm64.zip)
- Windows setup: [FlowPilot_0.1.0_x64-setup.exe](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_0.1.0_x64-setup.exe)
- Windows portable: [FlowPilot-0.1.0-portable.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot-0.1.0-portable.zip)

현재 macOS 배포 파일은 Apple Developer ID 서명과 공증이 없는 개발/테스트용 빌드입니다. GitHub에서 다운로드한 앱을 바로 실행하면 macOS Gatekeeper가 "손상되었으므로 휴지통으로 이동" 경고를 표시할 수 있습니다.

### macOS 처음 실행 방법

방법 1: 동봉된 헬퍼 사용 (권장)

1. zip 압축을 풀거나 DMG를 엽니다.
2. `처음 실행하기.command`를 Finder에서 우클릭합니다.
3. `열기`를 선택합니다.
4. 헬퍼가 `FlowPilot.app`의 다운로드 격리 속성을 제거한 뒤 앱을 실행합니다.

방법 2: 터미널에서 격리 속성 직접 제거

```bash
xattr -dr com.apple.quarantine /path/to/FlowPilot.app
open /path/to/FlowPilot.app
```

예를 들어 다운로드 폴더에서 zip 압축을 풀었다면 다음처럼 실행할 수 있습니다.

```bash
xattr -dr com.apple.quarantine ~/Downloads/FlowPilot_mac_arm64/FlowPilot.app
open ~/Downloads/FlowPilot_mac_arm64/FlowPilot.app
```

방법 3: 소스에서 직접 실행

```bash
git clone https://github.com/biglol10/MyVibeCoding.git
cd MyVibeCoding/FlowPilot_mac
npm install
npm run dev
```

## 개발 환경

- Node.js 20 이상
- npm
- Rust stable toolchain
- Tauri CLI
- macOS 앱 빌드 시 Xcode Command Line Tools

## 실행

```bash
npm install
npm run dev
```

## 테스트

```bash
npm test
```

브라우저 확장:

```bash
cd browser-extension
npm install
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

macOS 다운로드 파일 다시 만들기:

```bash
npm run dist:macos
```

스크립트 결과:

- `downloads/FlowPilot_mac/FlowPilot_mac_arm64.zip`
- `downloads/FlowPilot_mac/FlowPilot_0.1.0_aarch64.dmg`

## 폴더 구조

- `src`: React UI
- `src-tauri`: Tauri/Rust 데스크톱 앱
- `browser-extension`: Chrome 확장
- `scripts`: 배포 패키징 스크립트
- `docs`: 설계 문서와 작업 계획
