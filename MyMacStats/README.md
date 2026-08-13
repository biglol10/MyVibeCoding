# MyMacStats

MyMacStats는 macOS 시스템 상태를 한 화면에서 확인하는 SwiftUI 유틸리티입니다. CPU, RAM, Disk, Network, Battery, Processes 상태를 왼쪽 사이드바에 요약하고, 선택한 항목의 원인 목록과 상세 정보를 가운데/오른쪽 패널에 보여줍니다.

핵심 목표는 단순히 수치를 보여주는 것이 아니라, 상태가 나쁠 때 무엇이 원인인지 바로 보이게 하는 것입니다. 예를 들어 RAM이 critical 상태가 되면 사이드바 RAM 항목이 빨간색으로 표시되고, RAM 화면 상단에는 메모리를 많이 쓰는 앱 요약이 나타납니다.

## 다운로드

- macOS 테스트 빌드 zip: [MyMacStats-test-build.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacStats/MyMacStats-test-build.zip)

GitHub에서 받은 zip을 압축 해제한 뒤 `MyMacStats.app`을 바로 더블클릭하려면 공개 배포 zip이 Apple Developer ID로 서명되고 Apple notarization/stapling까지 완료되어 있어야 합니다.

개인 맥북에 설치하는 용도라면 Developer ID 공증 없이도 동봉된 실행/설치 스크립트를 사용하면 됩니다. 앱을 직접 더블클릭하지 말고 아래 방법 중 하나로 처음 실행하세요.

### 다운로드 후 처음 실행하는 방법

방법 1: 동봉된 처음 실행 도우미 사용

1. zip 압축을 풉니다.
2. `MyMacStats` 폴더 안의 `처음 실행하기.command`를 Finder에서 우클릭합니다.
3. `열기`를 선택합니다. 일반 더블클릭이 막히면 우클릭 `열기`를 사용해야 합니다.
4. 스크립트가 다운로드 격리 속성을 제거하고 같은 폴더의 `MyMacStats.app`을 실행합니다.

선택: 개인 맥북에 설치

1. zip 압축을 풉니다.
2. `MyMacStats` 폴더 안의 `Install MyMacStats.command`를 Finder에서 우클릭합니다.
3. `열기`를 선택합니다.
4. 설치 스크립트가 `MyMacStats.app`을 `/Applications`에 설치하고 실행합니다.
5. 다음부터는 Applications에서 `MyMacStats`를 바로 실행합니다.

방법 2: 터미널에서 격리 속성 직접 제거

```bash
xattr -dr com.apple.quarantine /path/to/MyMacStats.app
open /path/to/MyMacStats.app
```

예를 들어 다운로드 폴더에서 압축을 풀었다면 다음처럼 실행할 수 있습니다.

```bash
xattr -dr com.apple.quarantine ~/Downloads/MyMacStats/MyMacStats.app
open ~/Downloads/MyMacStats/MyMacStats.app
```

방법 3: 소스에서 직접 실행

```bash
git clone https://github.com/biglol10/MyVibeCoding.git
cd MyVibeCoding/MyMacStats
swift run MyMacStatsApp
```

## 주요 기능

- 메뉴바 상주 앱 + 대시보드 창
- 메뉴바 미니 팝오버: CPU/RAM/Disk 요약과 Top Culprits 표시
- 3-column 대시보드: 왼쪽 요약, 가운데 목록, 오른쪽 상세
- CPU/RAM/Disk/Network/Battery/Processes 자동 갱신 및 metric별 sampling cadence
- 앱 단위 프로세스 그룹화
- CPU/RAM 원인 요약 배너
- CPU 1분/5분 sparkline
- RAM used/free/compressed/cached/swap/pressure 표시
- Disk 메인 볼륨 정보, 읽기/쓰기 속도, 공간 후보 표시
- Network 활성 인터페이스, 다운로드/업로드 속도, 누적 전송량 표시
- Battery 충전 상태, 전원 소스, 사이클 수 표시 시도
- Processes 검색 및 CPU/RAM/Name/PID 정렬, 동률 항목 이름/PID 기준 안정 정렬
- 프로세스 또는 앱 그룹 단위 Quit / Force Quit 2단계 종료 흐름
- 보호 프로세스 종료 차단
- RAM critical 상태가 30초 이상 지속되면 macOS 알림 전송 시도
- refresh interval 설정 저장 및 다음 실행 시 복원
- 전체 사이드바 row 클릭 영역 지원

## 신뢰성 점검 항목

시스템 모니터링 앱 특성상 단순 빌드 성공만으로 완료로 보지 않고, 실제 macOS API 의미와 설치 경로를 함께 검증합니다.

- CPU 사용률은 `host_processor_info`의 tick delta로 user/system/idle을 계산합니다.
- RAM pressure는 `kern.memorystatus_vm_pressure_level` 값을 사용합니다. `vm.memory_pressure`는 표시값 의미가 달라 health 판정에 사용하지 않습니다.
- CPU/RAM sampler는 `mach_host_self()`로 얻은 send right를 해제합니다.
- Network 카운터는 `NET_RT_IFLIST2`의 64-bit byte counter를 사용하고, 두 번째 샘플부터는 누적 총량이 아니라 현재 증가량이 있는 인터페이스를 우선 선택합니다.
- 이전에 정상 값이 있던 metric은 due sampling이 한 번 실패해도 마지막 정상 값과 상태를 유지합니다. retained last-success health가 `critical`이면 `critical`을 유지하고, 그 외에는 `warning`으로 표시합니다. 두 번째 연속 due 실패에서 unavailable로 전환하며, 이전 정상 값이 없는 첫 실패는 바로 unavailable입니다.
- Disk 읽기/쓰기 속도는 IOKit block storage counter delta로 계산하고, 볼륨명 fallback은 하드코딩된 `Macintosh HD`가 아니라 mount point 이름을 사용합니다.
- 디스크 공간 후보 스캔의 `du` 호출은 timeout 후 fallback scan으로 전환하며, UI refresh를 막지 않습니다.
- 기본 자동 디스크 후보 스캔은 넓은 `~/Library/Caches` 전체를 훑지 않습니다. macOS가 media library 등 개인정보 보호 권한 프롬프트를 띄울 수 있어 Xcode DerivedData처럼 범위가 좁은 개발자 캐시만 기본 후보로 둡니다.
- 프로세스 종료 직전에는 cadence와 관계없이 최신 프로세스 목록을 강제로 다시 샘플링해 PID, 이름, 실행 경로, 번들 ID가 같은 대상인지 확인합니다. 새 샘플을 얻지 못하면 cached 목록을 사용하지 않고 signal을 보내지 않습니다.
- 프로세스 번들 ID는 임의 경로를 `Bundle(path:)`로 여는 대신 `.app/Contents/Info.plist`만 직접 읽어 불필요한 개인정보 권한 프롬프트 가능성을 줄입니다.
- 메뉴바 `Open Dashboard`는 임의의 첫 번째 창이 아니라 `MyMacStats` 대시보드 창을 찾아 앞으로 가져옵니다.
- 개인 배포 zip은 `scripts/check-distribution.sh`로 압축 해제, quarantine 제거, 설치, codesign 검증까지 확인합니다.

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

## 갱신 주기와 일시 실패

대시보드는 하나의 refresh loop를 유지하지만, 각 sampler는 다음 cadence가 되었을 때만 실행됩니다. 사용자가 설정한 refresh interval을 base interval로 사용하며, cadence를 건너뛴 tick은 실패로 세지 않습니다.

| Metric | Sampling cadence |
| --- | --- |
| CPU, RAM, Network | `max(base interval, 1초)` |
| Processes | `max(base interval, 2초)` |
| Disk, Battery | `max(base interval, 10초)` |
| Disk space candidates | 별도 백그라운드 60초 |

정상 샘플 뒤 첫 due failure에서는 마지막 정상 값과 원래 시각을 유지합니다. retained last-success health가 `critical`이면 `critical`을 유지하고, 그 외에는 `warning`으로 표시합니다. 두 번째 연속 due failure에서는 `unavailable`로 전환합니다. 새 성공 샘플은 이 상태를 즉시 회복합니다. CPU history와 health debounce는 새 성공 샘플에서만 진행됩니다.

## 프로세스/앱 종료

오른쪽 상세 패널에서 선택된 대상에 대해 `Quit Process` 또는 `Quit App`을 요청할 수 있습니다. 단일 프로세스는 해당 PID만 대상으로 하고, 앱 그룹으로 묶인 항목은 같은 앱의 관련 프로세스들을 함께 대상으로 합니다.

- 일반 Quit은 대상 프로세스들에 `SIGTERM`을 보냅니다.
- 앱 그룹 Quit은 먼저 macOS 앱 종료 API를 사용해 정상 종료를 요청하고, 처리할 수 없을 때 `SIGTERM` 방식으로 fallback합니다.
- Quit 후 대상 앱/프로세스가 계속 남아 있으면 `Force Quit` 경로를 사용할 수 있습니다.
- Force Quit은 대상 프로세스들에 `SIGKILL`을 보냅니다.
- `launchd`, `WindowServer`, 앱 자신, 시스템 경로 프로세스 등 보호 대상이 포함되면 버튼이 비활성화됩니다.
- 종료 확인 시에는 Processes cadence를 우회해 새 프로세스 목록을 반드시 수집합니다. 이 수집이 실패하면 종료를 거부하므로 stale cached 대상에는 signal을 보내지 않습니다.

## 디스크 공간 후보

Disk 화면은 용량 부족 원인 후보를 보여줍니다.

기본 후보:

- Xcode DerivedData

Downloads, Desktop, Documents, Trash, `~/Library/Caches` 전체처럼 macOS 개인정보 보호 권한 프롬프트가 생길 수 있는 폴더는 기본 자동 스캔 대상에서 제외합니다.

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

- CPU/RAM sampler의 실제 커널 API 연동과 pressure level mapping
- Network 64-bit counter, 인터페이스 변경, 활성 인터페이스 선택
- Disk volume fallback, I/O counter delta, 공간 후보 timeout fallback
- HealthEvaluator 상태 판정
- metric formatter
- process sorting/grouping
- 프로세스/앱 그룹 Quit / Force Quit 대상, 최신 PID identity 재확인, fresh process sampling 실패 시 fail-closed, 앱 종료 fallback, signal 선택
- dashboard view model 선택/정렬/검색/히스토리와 선택 refresh interval
- metric별 cadence, last-known-good stale/unavailable 전환, system metrics snapshot 구성
- disk space candidate scanner
- cause summary builder
- RAM critical 지속 알림 컨트롤러
- 메뉴바 refresh lifecycle과 dashboard window targeting
- release/package distribution script behavior

## 개인용 앱 번들 및 zip 생성

```bash
cd MyMacStats
./scripts/build-app-bundle.sh --deploy-personal
open dist/MyMacStats/MyMacStats.app
```

스크립트 결과:

- `dist/MyMacStats/MyMacStats.app`
- `dist/MyMacStats-test-build.zip`
- `../downloads/MyMacStats/MyMacStats-test-build.zip`

개인용 zip에는 `MyMacStats.app`, `Install MyMacStats.command`, `처음 실행하기.command`가 함께 들어갑니다. 다른 개인 Mac에서는 `Install MyMacStats.command`로 설치하세요.

## 공개 배포 zip 생성

다른 Mac에서 다운로드 후 바로 실행 가능한 zip은 Developer ID 서명과 notarization이 필요합니다.

사전 준비:

```bash
xcrun notarytool store-credentials MyMacStatsNotary \
  --apple-id you@example.com \
  --team-id TEAMID1234 \
  --password app-specific-password
```

공개 배포 zip 생성 및 `downloads/MyMacStats` 갱신:

```bash
cd MyMacStats
MACOS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID1234)" \
MACOS_NOTARY_PROFILE="MyMacStatsNotary" \
./scripts/build-app-bundle.sh --release --deploy-downloads
```

검증:

```bash
./scripts/check-distribution.sh ../downloads/MyMacStats/MyMacStats-test-build.zip
```

`--release` 모드는 다음을 모두 통과해야 zip을 만듭니다.

- Developer ID Application 서명
- hardened runtime
- Apple notarization
- stapler staple/validate
- `spctl --assess --type execute`

Developer ID 인증서나 notarization 설정이 없으면 공개 배포 zip 생성은 실패합니다. 이는 깨진 zip이 `downloads/`에 올라가는 것을 막기 위한 동작입니다.

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
- 시스템 API가 값을 계속 제공하지 않거나 권한상 읽을 수 없는 항목은 unavailable로 표시됩니다. 이전 정상 값이 있으면 첫 due failure에서 마지막 값을 유지하며, retained last-success health가 `critical`이면 `critical`, 그 외에는 `warning`으로 표시합니다. 두 번째 연속 due failure에서 unavailable로 전환합니다.
