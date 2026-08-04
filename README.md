# MyVibeCoding

바이브 코딩으로 만든 개인 프로그램들을 정리하는 프로젝트입니다. 루트에는 이 저장소에 포함된 프로그램 폴더와 다운로드용 빌드 파일을 둡니다.

## 프로그램

| 프로그램 | 설명 | 소스 | 다운로드 |
| --- | --- | --- | --- |
| MyCaptureProgram | 사각형/윈도우/전체 화면 캡처와 녹화, 편집, OCR, 빠른 가리기, 히스토리/프리셋을 제공하는 macOS 앱 | [MyCaptureProgram](./MyCaptureProgram) | [개인 설치 zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyCaptureProgram/CaptureStudio-personal-mac.zip) |
| MyMacClean | 앱 삭제, 고아 파일, 대용량 파일, 개발 캐시, 시작 항목을 권한 안내와 삭제 실패 로그까지 검토 후 정리하는 SwiftUI 유틸리티 | [MyMacClean](./MyMacClean) | [개인 설치 DMG](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacClean/MyMacClean-dev.dmg) |
| MyMacFinder | 듀얼 패널, 경로/빈 영역 Terminal 명령, Smart 프리뷰, 안전한 파일 작업/Undo를 갖춘 SwiftUI/AppKit 로컬 파일 관리자 | [MyMacFinder](./MyMacFinder) | [개인 설치 zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacFinder/MyMacFinder-personal-mac.zip) |
| MyMacStats | CPU, RAM, Disk I/O, Network, Battery, Processes 상태와 RAM 알림을 보여주는 SwiftUI 시스템 모니터 | [MyMacStats](./MyMacStats) | [MyMacStats-test-build.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacStats/MyMacStats-test-build.zip) |
| MyMacCalendar | 로컬 우선 일정 관리, 반복 일정, 검색, 알림, 휴일, 메뉴바/플로팅 위젯을 제공하는 SwiftUI 캘린더 | [MyMacCalendar](./MyMacCalendar) | [개인 설치 zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacCalendar/MyMacCalendar-personal-mac.zip) |
| FlowPilot_mac | SwiftUI 네이티브 macOS 활동 추적 앱, 기존 Tauri/Windows 소스 포함 | [FlowPilot_mac](./FlowPilot_mac) | [Swift Native zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_native_mac_arm64.zip), [Swift Native DMG](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/FlowPilot_mac/FlowPilot_native_mac_arm64.dmg) |

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

MyMacFinder:

```bash
cd MyMacFinder
swift run MyMacFinder
```

MyMacStats:

```bash
cd MyMacStats
swift run MyMacStatsApp
```

MyMacCalendar:

```bash
cd MyMacCalendar
swift run MyMacCalendar
```

FlowPilot_mac:

```bash
cd FlowPilot_mac
cd macos-native
swift run FlowPilotNative
```

FlowPilot_mac Tauri legacy:

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
├── MyMacFinder/          # SwiftUI/AppKit macOS 파일 관리자 앱
├── MyMacStats/           # SwiftUI macOS 시스템 모니터 앱
├── MyMacCalendar/        # SwiftUI macOS 캘린더 앱
├── FlowPilot_mac/        # SwiftUI native + Tauri/React/Rust 활동 추적 앱
└── downloads/            # GitHub README에서 연결하는 다운로드 파일
```

## 개발 환경 요약

- Swift 프로젝트: Xcode Command Line Tools, Swift 6 이상
- MyCaptureProgram: macOS 15 이상
- MyMacClean: macOS 14 이상
- MyMacFinder: macOS 15 이상, Xcode 16.4 또는 Swift 6.1 호환 toolchain, ZIPFoundation
- MyMacStats: macOS 14 이상
- MyMacCalendar: macOS 14 이상
- FlowPilot_mac: Swift 5.9+/Xcode Command Line Tools, Node.js 22 LTS/npm, Rust 1.77.2 이상, Tauri 2
- 캡처/활동 추적/정리/캘린더/파일 관리자 프로그램은 macOS 개인정보 보호 권한이 필요할 수 있습니다.

각 프로그램의 자세한 기능, 테스트, 빌드, 배포 파일 갱신 방법은 해당 폴더의 README를 확인하세요.

## 다운로드 파일 관리

다운로드 파일은 `downloads/` 아래에 함께 커밋합니다. 새 빌드를 만들면 같은 파일명으로 교체한 뒤 커밋/푸시하면 README의 GitHub raw 링크가 그대로 최신 파일을 가리킵니다.

macOS 앱을 다른 Mac에서 앱 더블클릭만으로 실행할 수 있게 공개 배포하려면 Apple Developer ID 서명과 notarization이 필요합니다. 개인 Mac에 설치하는 용도라면 각 앱 zip에 포함된 설치 스크립트를 사용하세요.

- CaptureStudio 개인용 zip: `MyCaptureProgram/scripts/package_personal.sh`
- MyMacClean 개인 설치 DMG: `MyMacClean/scripts/create-dmg.sh`
- MyMacFinder 개인용 zip: `MyMacFinder/scripts/package_personal.sh`
- MyMacStats 개인용 zip: `MyMacStats/scripts/build-app-bundle.sh --deploy-personal`
- MyMacCalendar 개인용 zip: `MyMacCalendar/scripts/package_personal.sh`
- FlowPilot Swift Native 개인용 zip/DMG: `FlowPilot_mac`에서 `npm run package:macos:native`, `npm run package:macos:native:dmg`
