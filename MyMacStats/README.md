# MyMacStats

MyMacStats는 macOS 시스템 상태를 한 화면에서 확인하는 SwiftUI 유틸리티입니다. CPU, RAM, Disk, Network, Battery, Processes 상태를 왼쪽 사이드바에 요약하고, 선택한 항목의 원인 목록과 상세 정보를 가운데/오른쪽 패널에 보여줍니다.

핵심 목표는 단순히 수치를 보여주는 것이 아니라, 상태가 나쁠 때 무엇이 원인인지 바로 보이게 하는 것입니다. 예를 들어 RAM이 critical 상태가 되면 사이드바 RAM 항목이 빨간색으로 표시되고, RAM 화면 상단에는 메모리를 많이 쓰는 앱 요약이 나타납니다.

## 다운로드

- macOS 테스트 빌드 zip: [MyMacStats-test-build.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacStats/MyMacStats-test-build.zip)

> 현재 배포 파일은 개발/테스트용 ad-hoc signed 빌드입니다. macOS 보안 경고가 나오면 Finder에서 우클릭 후 열기를 사용하거나 소스에서 직접 빌드하세요.

## 주요 기능

- 메뉴바 상주 앱 + 대시보드 창
- 메뉴바 미니 팝오버: CPU/RAM/Disk 요약과 Top Culprits 표시
- 3-column 대시보드: 왼쪽 요약, 가운데 목록, 오른쪽 상세
- CPU/RAM/Disk/Network/Battery/Processes 자동 갱신
- 앱 단위 프로세스 그룹화
- CPU/RAM 원인 요약 배너
- CPU 1분/5분 sparkline
- RAM used/free/compressed/cached/swap/pressure 표시
- Disk 메인 볼륨 정보와 공간 후보 표시
- Network 활성 인터페이스, 다운로드/업로드 속도, 누적 전송량 표시
- Battery 충전 상태, 전원 소스, 사이클 수 표시 시도
- Processes 검색 및 CPU/RAM/Name/PID 정렬
- Quit / Force Quit 2단계 프로세스 종료 흐름
- 보호 프로세스 종료 차단
- 전체 사이드바 row 클릭 영역 지원

## UI 구조

```text
┌──────────────┬──────────────────────────┬──────────────────────────┐
│ Sidebar      │ Metric List              │ Detail                   │
├──────────────┼──────────────────────────┼──────────────────────────┤
│ CPU          │ Top CPU apps/processes   │ CPU split, history, PID  │
│ RAM          │ Top memory apps          │ memory details, culprit  │
│ Disk         │ volume + cleanup hints   │ capacity and candidates  │
│ Network      │ interface values         │ throughput and totals    │
│ Battery      │ power status             │ charge/service details   │
│ Processes    │ searchable app groups    │ selected process details │
│ Settings     │ refresh controls         │                          │
└──────────────┴──────────────────────────┴──────────────────────────┘
```

사이드바는 상태 요약에 집중합니다. 가운데 목록은 비교 가능한 행 폭을 유지하고, 오른쪽 상세 패널은 선택된 앱 그룹이나 프로세스의 PID, CPU, 메모리, 경로, 번들 ID를 보여줍니다.

## 상태 색상

- `normal`: 기본 텍스트 / 초록 상태 점
- `warning`: 노란색
- `critical`: 빨간색
- `unavailable`: 회색

CPU 상태는 70%/90% 임계값이 10초 이상 유지될 때 warning/critical로 바뀝니다. RAM, Disk, Battery, Network는 각 샘플러 결과와 HealthEvaluator 규칙에 따라 상태가 정해집니다.

## 프로세스 종료

오른쪽 상세 패널에서 선택된 프로세스에 대해 `Quit Process`를 요청할 수 있습니다.

- 일반 Quit은 `SIGTERM`을 보냅니다.
- Quit 후 같은 프로세스가 계속 남아 있으면 `Force Quit` 경로를 사용할 수 있습니다.
- Force Quit은 `SIGKILL`을 보냅니다.
- `launchd`, `WindowServer`, 앱 자신, 시스템 경로 프로세스 등은 보호 대상으로 처리되어 버튼이 비활성화됩니다.

## 디스크 공간 후보

Disk 화면은 용량 부족 원인 후보를 보여줍니다.

기본 후보:

- Downloads
- Trash
- Caches
- Xcode DerivedData

후보 스캔은 UI를 막지 않도록 백그라운드에서 수행되며, 오래 걸리는 대상은 timeout 후 다음 갱신으로 넘깁니다.

## 메뉴바 팝오버

앱 실행 중 메뉴바에는 다음 형태의 요약이 표시됩니다.

```text
CPU 12% RAM 15.4G / 16G
```

메뉴바 항목을 클릭하면 미니 팝오버가 열리고 CPU/RAM/Disk 요약과 Top Culprits를 확인할 수 있습니다. `Open Dashboard` 버튼으로 대시보드 창을 다시 열 수 있습니다.

## 개발 환경

- macOS 14 이상
- Xcode Command Line Tools
- Swift 6 이상

## 실행

```bash
cd MyMacStats
swift run MyMacStatsApp
```

## 테스트

```bash
cd MyMacStats
swift test
```

현재 테스트 범위:

- HealthEvaluator 상태 판정
- metric formatter
- process sorting/grouping
- Quit / Force Quit signal 선택
- dashboard view model 선택/정렬/검색/히스토리
- system metrics snapshot 구성
- disk space candidate scanner
- cause summary builder

## 앱 번들 및 zip 생성

```bash
cd MyMacStats
./scripts/build-app-bundle.sh
open dist/MyMacStats.app
```

스크립트 결과:

- `dist/MyMacStats.app`
- `dist/MyMacStats-test-build.zip`

스크립트는 release 빌드 후 앱 아이콘과 Info.plist를 포함한 `.app` 번들을 만들고, 가능한 경우 ad-hoc codesign 검증까지 수행합니다.

## 폴더 구조

```text
MyMacStats/
├── Package.swift
├── Sources/
│   ├── MyMacStatsCore/
│   │   ├── Disk/
│   │   ├── Health/
│   │   ├── Models/
│   │   ├── Processes/
│   │   ├── Samplers/
│   │   └── Support/
│   ├── MyMacStatsAppSupport/
│   └── MyMacStatsApp/
│       ├── Resources/
│       └── Views/
├── Tests/
├── scripts/
└── dist/
```

## 주요 모듈

- `MyMacStatsCore`: 데이터 모델, 포맷터, health 판정, system samplers, process grouping/termination
- `MyMacStatsAppSupport`: refresh service, dashboard view model, cause summary builder
- `MyMacStatsApp`: SwiftUI 앱 진입점, 메뉴바 팝오버, 3-column dashboard views

## 현재 제한

- 팬 속도, 온도 센서, GPU 세부 센서는 아직 지원하지 않습니다.
- Dock 아이콘 숨김 설정은 아직 없습니다.
- 알림센터 위젯과 iCloud 동기화는 없습니다.
- 프로세스별 네트워크 사용량은 아직 표시하지 않습니다.
- 시스템 API가 값을 제공하지 않거나 권한상 읽을 수 없는 항목은 unavailable로 표시됩니다.

## 설계 문서

상세 기획은 [docs/MyMacStats-design.md](../docs/MyMacStats-design.md)를 참고하세요.
