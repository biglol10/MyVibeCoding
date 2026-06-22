# MyVibeCoding

바이브 코딩으로 만든 개인 프로그램들을 한 저장소에 모아둔 프로젝트입니다. 루트에는 각 프로그램 폴더와 다운로드용 빌드 파일을 두고, 각 폴더에는 소스 실행과 빌드 방법을 정리했습니다.

## 프로그램

| 프로그램 | 설명 | 소스 | 다운로드 |
| --- | --- | --- | --- |
| MyCaptureProgram | macOS 스크린샷/화면 녹화, 편집, OCR, 빠른 가리기 앱 | [MyCaptureProgram](./MyCaptureProgram) | [CaptureStudio-macos-arm64.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyCaptureProgram/CaptureStudio-macos-arm64.zip) |
| MyMacClean | macOS 앱 삭제와 잔여 파일 정리를 돕는 SwiftUI 유틸리티 | [MyMacClean](./MyMacClean) | [MyMacClean-test-build.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacClean/MyMacClean-test-build.zip) |
| MyMacStats | CPU, RAM, Disk, Network, Battery, Processes 상태와 원인 앱을 보여주는 SwiftUI 시스템 모니터 | [MyMacStats](./MyMacStats) | [MyMacStats-test-build.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacStats/MyMacStats-test-build.zip) |
| FlowPilot_mac | Tauri 기반 활동 추적, 생산성 분류, 리포트 앱 | [FlowPilot_mac](./FlowPilot_mac) | [macOS DMG](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_0.1.0_aarch64.dmg), [macOS zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_mac_arm64.zip), [Windows setup](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_0.1.0_x64-setup.exe), [Windows portable](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot-0.1.0-portable.zip), [Windows exe](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/flowpilot.exe) |

## 클론

```bash
git clone https://github.com/biglol10/MyVibeCoding.git
cd MyVibeCoding
```

## 빠른 실행

MyCaptureProgram:

```bash
cd MyCaptureProgram
swift run CaptureStudio
```

MyMacClean:

```bash
cd MyMacClean
swift run MyMacCleanApp
```

MyMacStats:

```bash
cd MyMacStats
swift run MyMacStatsApp
```

FlowPilot_mac:

```bash
cd FlowPilot_mac
npm ci
npm run tauri -- dev
```

## 저장소 구조

```text
.
├── MyCaptureProgram/     # SwiftUI macOS 캡처 앱
├── MyMacClean/           # SwiftUI macOS 정리 앱
├── MyMacStats/           # SwiftUI macOS 시스템 모니터 앱
├── FlowPilot_mac/        # Tauri + React + Rust 활동 추적 앱
└── downloads/            # GitHub README에서 연결하는 다운로드 파일
```

## 개발 환경 요약

- Swift 프로젝트: Xcode Command Line Tools, Swift 6 이상
- MyCaptureProgram: macOS 15 이상
- MyMacClean: macOS 14 이상
- MyMacStats: macOS 14 이상
- FlowPilot_mac: Node.js 22 LTS/npm, Rust 1.77.2 이상, Tauri 2
- 캡처/활동 추적/정리 프로그램은 macOS 개인정보 보호 권한이 필요할 수 있습니다.

각 프로그램의 자세한 기능, 테스트, 빌드, 배포 파일 갱신 방법은 해당 폴더의 README를 확인하세요.

## 다운로드 파일 관리

다운로드 파일은 `downloads/` 아래에 함께 커밋합니다. 새 빌드를 만들면 같은 파일명으로 교체한 뒤 커밋/푸시하면 README의 GitHub raw 링크가 그대로 최신 파일을 가리킵니다.
