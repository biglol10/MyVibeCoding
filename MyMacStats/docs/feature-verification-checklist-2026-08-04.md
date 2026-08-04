# MyMacStats 기능 검증 체크리스트

- 작성일: 2026-08-04
- 기준 커밋: `8e93341`
- 검증 대상: 현재 `MyMacStats` Swift Package, SwiftUI 앱, 테스트, 번들/zip 생성 스크립트
- 검증 방식: README 주장 대조, 소스 직접 확인, XCTest 실행, release build, 앱 번들 생성, 개인 배포 zip 설치 검증, 실제 앱 실행/화면 캡처 스모크

## 후속 수정 반영

이 문서는 최초 점검 뒤 같은 날 후속 수정 사항까지 반영했다.

- 프로세스 종료 직전 최신 프로세스 목록으로 PID/name/path/bundle identity를 재확인하도록 변경했다.
- 앱 그룹 Quit은 `NSRunningApplication.terminate()`를 먼저 시도하고, 처리할 수 없을 때 기존 `SIGTERM` 방식으로 fallback한다.
- 프로세스 번들 ID 해석은 임의 경로 `Bundle(path:)` 호출 대신 `.app/Contents/Info.plist` 직접 읽기로 제한했다.
- TCC 로그로 media library 권한 팝업의 실제 원인이 `du`의 넓은 `~/Library/Caches` 스캔임을 확인했고, 기본 자동 디스크 후보에서 broad Caches를 제거했다.
- Settings의 `Menu Bar Metric` 오해 가능 문구를 `Menu Bar Display: CPU + RAM`으로 바꿨다.

## 판정 기준

- `[x] 확인됨`: 구현이 있고, 소스/테스트/실행 중 하나 이상으로 확인했다.
- `[!] 제한 있음`: 구현은 있으나 정확성, UX, 테스트 깊이, 운영 안정성에 남은 리스크가 있다.
- `[ ] 미구현`: 현재 앱에 없는 기능이거나 후속 범위다.

## 이번에 실제로 실행한 검증

- [x] `swift test`
  - 결과: 79 tests, 0 failures.
  - 확인 범위: health 판정, CPU/RAM/Network/Disk 핵심 sampler, process 검색/정렬/grouping/termination, dashboard view model, 원인 요약, RAM critical 알림 controller, 메뉴바 lifecycle source check, 패키징 script source check.
- [x] `swift build -c release`
  - 결과: release build 성공.
- [x] `./scripts/build-app-bundle.sh`
  - 결과: `dist/MyMacStats/MyMacStats.app`, `dist/MyMacStats-test-build.zip` 생성 성공.
- [x] `./scripts/check-distribution.sh dist/MyMacStats-test-build.zip`
  - 결과: zip 압축 해제, quarantine 제거, 임시 Applications 설치, codesign 확인 성공.
- [x] 실제 앱 번들 실행
  - 실행 파일: `dist/MyMacStats/MyMacStats.app`
  - 결과: `MyMacStatsApp` 프로세스 기동 확인, `MyMacStats` 창 이름 확인.
- [x] 실제 화면 캡처 확인
  - 결과: CPU/RAM/Disk/Network/Battery/Processes 값이 채워진 3-column 화면이 렌더링됨.
  - 관찰: 최초 점검 때 앱 실행 중 macOS가 `MyMacStats.app`에 Apple Music/미디어 보관함 접근 권한 팝업을 표시했다. 후속 TCC 로그에서 `du`가 `~/Library/Caches` 전체를 스캔하는 과정이 `kTCCServiceMediaLibrary` 요청으로 이어진 것을 확인했고, 기본 자동 스캔 대상에서 broad Caches를 제거했다.
- [ ] 모든 UI row 클릭, 메뉴바 팝오버 클릭, 종료 확인창 클릭을 자동 UI 테스트로 전부 검증
  - 이번에는 프로세스/창/화면 렌더링 스모크까지만 확인했다. 세부 클릭 자동화는 아직 없다.

## 1. 앱 형태와 실행 구조

- [x] 일반 macOS 앱 창이 실행 시 열린다.
  - 근거: `WindowGroup(AppWindowTitles.dashboard)`가 앱 entry에 있고 실제 실행 시 `MyMacStats` 창이 생성됐다.
- [x] 메뉴바 앱 형태가 구현되어 있다.
  - 근거: `MenuBarExtra`가 앱 entry에 있고, label은 `CPU ... RAM ...` 형식으로 구성된다.
- [x] 메뉴바 팝오버가 있다.
  - 근거: `MenuBarPopoverView`가 CPU/RAM/Disk 요약과 Top Culprits, Open Dashboard 버튼을 렌더링한다.
- [x] 메뉴바 팝오버와 대시보드가 같은 view model을 공유한다.
  - 근거: `@StateObject private var viewModel = DashboardViewModel()`이 창과 메뉴바에 동시에 전달된다.
- [x] Open Dashboard 버튼은 기존 대시보드 창을 우선 찾는다.
  - 근거: 창 title이 `AppWindowTitles.dashboard`인 window를 찾아 앞으로 가져온다.
- [!] 메뉴바 lifecycle/window targeting 테스트는 대부분 source-string 테스트다.
  - 실제 앱 실행으로 창 생성은 확인했지만, 메뉴바 아이콘 클릭과 팝오버 동작은 이번에 자동 조작하지 않았다.
- [ ] Dock 아이콘 숨김 설정은 없다.
  - README의 현재 제한과 일치한다.

## 2. 전체 데이터 갱신 파이프라인

- [x] `SystemMetricsService.refresh()`가 CPU/RAM/Disk/Network/Battery/Processes 샘플을 모아 하나의 snapshot을 만든다.
- [x] sampler 실패 시 앱 전체가 죽지 않고 해당 summary가 unavailable로 표시되는 흐름이 있다.
  - 근거: `DefaultSystemSampler`가 `try?`로 실패를 nil 처리하고, summary builder가 unavailable summary를 만든다.
- [x] CPU history는 최근 300초 샘플을 보관한다.
- [x] 디스크 공간 후보 스캔은 별도 task로 돌며 일반 refresh를 막지 않는다.
- [!] 원래 기획의 metric별 갱신 주기는 완전히 분리되어 있지 않다.
  - 현재 `DashboardViewModel.refreshInterval`은 전체 refresh loop 간격이다.
  - 디스크 공간 후보만 별도 60초 refresh interval을 가진다.
  - CPU/RAM 1초, Disk/Battery 10초처럼 metric별 sampling cadence는 아직 구현되지 않았다.
- [!] "마지막 정상 값을 잠깐 유지하다 오래 실패하면 unavailable" 정책은 현재 명확히 구현되어 있지 않다.
  - sampler가 nil이면 해당 refresh에서 바로 unavailable summary가 만들어진다.

## 3. CPU

- [x] 전체 CPU 사용률, user/system/idle 분해가 구현되어 있다.
  - 근거: `host_processor_info`의 CPU tick delta로 user/system/idle을 계산한다.
- [x] CPU sampler가 Mach send right와 processor info memory를 해제한다.
- [x] CPU health 규칙이 있다.
  - warning: 70% 이상 sustained threshold.
  - critical: 90% 이상 sustained threshold.
  - sustained 기본값: 10초.
- [x] CPU health에는 debounce가 적용된다.
- [x] CPU 화면은 CPU 사용량 높은 앱/프로세스 목록을 보여준다.
- [x] CPU 상세에는 Total/User/System/Idle, 1m/5m history picker, sparkline, 선택 프로세스 상세가 있다.
- [x] CPU 원인 요약은 top CPU group 기준으로 생성된다.
- [!] README의 "10초 이상 유지될 때 warning/critical" 표현은 실제보다 약간 단순하다.
  - 실제 적용은 10초 sustained 판정 뒤에도 debounce 2회 조건이 있어 상태 표시가 한 샘플 더 늦을 수 있다.
- [!] 첫 CPU 샘플은 이전 tick이 없어 이후 샘플보다 의미가 덜 정확할 수 있다.
  - 이후부터는 delta 기반이다.

## 4. RAM

- [x] RAM used/free/compressed/cached/swap/pressure 값이 구현되어 있다.
- [x] memory pressure는 `kern.memorystatus_vm_pressure_level` 기반이다.
- [x] swap 사용량은 `vm.swapusage` 기반으로 읽는다.
- [x] used memory는 cached pages를 제외해서 health threshold 입력으로 사용한다.
- [x] RAM health 규칙이 있다.
  - warning: 사용률 80% 이상 또는 pressure warning.
  - critical: 사용률 90% 이상, pressure critical, 또는 swap 증가.
- [x] RAM 화면은 메모리 사용량 높은 앱/프로세스 목록을 보여준다.
- [x] RAM 상태가 나쁠 때 원인 요약 배너가 생성된다.
- [x] RAM critical 지속 알림 controller가 있다.
  - 테스트는 critical 30초 지속과 recovery 후 reset을 검증한다.
- [!] 실제 macOS 알림 전달은 best-effort다.
  - 권한 요청/알림 전달 실패가 UI에 표시되지 않는다.
  - controller는 delivery attempt 이후 sent 상태로 본다.
- [!] RAM critical 알림은 설정에서 켜고 끄거나 임계 시간을 바꿀 수 없다.

## 5. Disk

- [x] 메인 볼륨 total/free/used ratio 표시가 구현되어 있다.
- [x] volume name fallback이 하드코딩된 `Macintosh HD`가 아니라 mount point 이름/Root Volume을 사용한다.
- [x] Disk health 규칙이 있다.
  - warning: free ratio 20% 미만.
  - critical: free ratio 10% 미만.
- [x] 읽기/쓰기 속도가 IOKit block storage counter delta로 계산된다.
- [x] Disk 화면에는 volume, mount point, total/free, read/write, space candidates가 표시된다.
- [x] 디스크 공간 후보 기본 자동 스캔은 Xcode DerivedData로 제한되어 있다.
- [x] 넓은 `~/Library/Caches` 전체 스캔은 기본 자동 대상에서 제외됐다.
- [x] TCC 로그에서 media library 프롬프트가 `/usr/bin/du`의 broad Caches 스캔에서 발생한 것을 확인했다.
- [x] `du` timeout 시 fallback scan으로 넘어가는 테스트가 있다.
- [!] Disk I/O 속도는 앱/볼륨별 I/O가 아니라 시스템 block storage 전체 counter 기반이다.
- [!] 첫 disk I/O 샘플은 delta 기준점이 없어 read/write 속도가 unavailable일 수 있다.
- [!] 디스크 공간 후보는 "정리 후보 표시"까지만 있고 삭제/정리 실행 기능은 없다.
- [!] README는 Downloads/Desktop/Documents/Trash 제외를 설명하지만 테스트는 주로 Downloads/Documents/Desktop 제외만 확인한다.

## 6. Network

- [x] 활성 interface 이름, download/upload speed, received/sent totals 표시가 구현되어 있다.
- [x] 네트워크 카운터는 `NET_RT_IFLIST2`의 64-bit byte counter를 사용한다.
- [x] 이전 샘플 대비 실제 증가량이 있는 interface를 우선 선택한다.
- [x] interface 변경 시 speed가 reset되는 테스트가 있다.
- [x] network health는 높은 트래픽을 위험으로 보지 않고, interface 없음/연결 실패 중심으로 판단한다.
- [!] 첫 network speed 샘플은 이전 counter가 없어 0으로 표시될 수 있다.
- [ ] 프로세스별 네트워크 사용량은 없다.
  - README 현재 제한과 일치한다.

## 7. Battery

- [x] IOKit power source API로 battery present, percentage, charging, power source, time remaining을 읽는다.
- [x] cycle count와 service recommended는 가능한 경우 표시한다.
- [x] Battery health 규칙이 있다.
  - warning: 20% 이하.
  - critical: 10% 이하 또는 service recommended.
  - battery가 없는 Mac은 unavailable.
- [!] cycle count/service recommended 파싱은 best-effort다.
  - 현재 테스트는 `HealthEvaluator` 중심이고, 실제 `BatterySampler` fixture parsing 테스트는 없다.
- [!] 데스크톱 Mac 또는 API가 값을 제공하지 않는 경우 Battery는 unavailable로 보이는 것이 정상 동작이다.

## 8. Processes 목록, 검색, 정렬, 그룹화

- [x] `/bin/ps -axo pid=,pcpu=,rss=,comm=` 기반 프로세스 sampling이 있다.
- [x] 프로세스 name, PID, CPU %, memory bytes, path, bundle identifier 모델이 있다.
- [x] 검색은 name, PID, path, bundle identifier에 대해 동작한다.
- [x] 정렬 key는 CPU/RAM/Name/PID가 있다.
- [x] CPU 화면 기본 정렬은 CPU 내림차순이다.
- [x] RAM 화면 기본 정렬은 memory 내림차순이다.
- [x] Processes 화면은 검색/정렬 controls를 보여준다.
- [x] 화면별 정렬 preference가 view model 안에서 분리되어 있다.
- [x] 프로세스가 app bundle 기준으로 group된다.
- [x] helper process는 owning app 기준으로 같은 앱 그룹에 묶인다.
- [x] 목록 row 폭은 CPU/Memory/action 영역이 고정 폭으로 설계되어 있다.
- [x] 목록 row 전체 클릭 영역이 `contentShape`와 button action으로 잡힌다.
- [!] UI에는 상위 60개 group만 표시된다.
  - 많은 프로세스가 있을 때 "60개까지만 표시" 안내 문구는 없다.
- [!] process sampling이 전체 refresh마다 `/bin/ps`를 실행한다.
  - 기능적으로 동작하지만 모니터링 앱 자체 overhead는 계속 관찰할 필요가 있다.
- [x] process bundle identifier resolver는 `.app/Contents/Info.plist`만 직접 읽는다.
  - 임의 executable/framework/private bundle 경로에 `Bundle(path:)`를 호출하지 않는다.
  - 비앱 bundle executable은 bundle identifier 해석 대상에서 제외하는 테스트가 있다.
  - 최초에는 이 경로를 의심했으나, TCC 로그상 실제 media library prompt 원인은 broad Caches `du` 스캔이었다.
- [!] sort comparator가 완전한 strict weak ordering이라고 보기 어렵다.
  - CPU/RAM/name/PID가 완전히 같은 값인 경우 descending에서 동등 항목도 `true`가 될 수 있다.
  - 일반 사용에서 큰 문제를 만들 가능성은 낮지만, 정렬 안정성 테스트가 추가되는 편이 낫다.

## 9. 프로세스 Quit / Force Quit

- [x] 상세 패널에 Quit Process/Quit App 버튼이 있다.
- [x] 앱 그룹 대상이면 관련 프로세스들을 함께 종료 대상으로 삼는다.
- [x] 앱 그룹 Quit은 먼저 macOS 앱 종료 API를 사용한다.
- [x] 앱 종료 API가 처리하지 못하는 대상은 기존 `SIGTERM` 방식으로 fallback한다.
- [x] 단일 프로세스 Quit은 `SIGTERM`, Force Quit은 `SIGKILL`을 보낸다.
- [x] Quit 후 같은 group이 남아 있으면 Force Quit 후보로 표시되는 흐름이 있다.
- [x] 실행 중 사라진 프로세스는 group termination에서 조용히 건너뛴다.
- [x] 보호 프로세스 차단이 있다.
  - PID <= 1, 앱 자신, `launchd`, `kernel_task`, `/System/`, `/usr/libexec/`, `/usr/sbin/`, `/bin/`, `/sbin/` 경로.
- [x] 종료 기능은 단위 테스트가 비교적 많다.
  - signal 선택, group target, self-protection, permission/protected error를 검증한다.
- [x] 종료 직전 최신 프로세스 목록으로 PID identity를 재확인한다.
  - PID가 다른 이름/경로/bundle identity로 바뀌었으면 signal을 보내지 않는다.
  - 대상이 이미 종료됐으면 signal을 보내지 않고 "already exited" 상태를 표시한다.
- [x] Quit App은 `NSRunningApplication.terminate()`를 먼저 사용한다.
  - 일반 앱 종료 UX가 기존 signal-only 방식보다 자연스럽다.
  - 앱 종료 API가 처리하지 못하면 기존 signal fallback을 사용한다.

## 10. 원인 분석과 health 표시

- [x] `MetricSummary`가 kind/title/value/detail/health/updatedAt을 가진다.
- [x] HealthState는 normal/warning/critical/unavailable이다.
- [x] Sidebar row는 health별 dot/text color를 반영한다.
- [x] CPU/RAM 원인 요약은 top process group을 기반으로 생성된다.
- [x] Disk 원인 요약은 남은 공간/volume 중심이다.
- [x] debounce 기본값 2회가 적용된다.
- [!] Network/Battery/Processes에는 CPU/RAM 수준의 "원인 앱" 요약은 없다.
  - Network는 프로세스별 사용량을 수집하지 않으므로 현재 구조상 원인 앱을 특정할 수 없다.

## 11. SwiftUI UI/UX

- [x] 3-column 구조가 구현되어 있다.
  - 왼쪽 sidebar, 가운데 metric list, 오른쪽 detail.
- [x] dark macOS utility tone이 적용되어 있다.
- [x] sidebar에는 CPU/RAM/Disk/Network/Battery/Processes/Settings가 있다.
- [x] sidebar row는 아이콘, 이름, 현재 값, 상세 텍스트, 상태 점을 가진다.
- [x] process list search input은 상단에 충분한 padding을 가진다.
- [x] process list row는 폭이 제각각 흔들리지 않도록 고정 width column을 사용한다.
- [x] 실제 화면 캡처에서 CPU/RAM/Disk/Network/Battery/Processes 값과 목록이 렌더링됐다.
- [x] broad Caches 제거 후 실제 실행 화면에서 macOS media library permission prompt가 다시 뜨지 않았다.
  - 실행 시점 이후 TCC 로그에서도 `kTCCServiceMediaLibrary` 요청이 새로 발생하지 않았다.
- [!] UI 자동 테스트/snapshot 테스트는 없다.
  - 현재는 view model 테스트와 실제 실행 스모크에 의존한다.
- [!] 화면 내 실제 클릭 반응은 이번에 전부 자동 검증하지 않았다.
  - 이전에 row click 이슈가 있었기 때문에, 접근성/UI automation 기반 클릭 테스트가 있으면 좋다.

## 12. Settings

- [x] refresh interval 선택 UI가 있다.
  - 선택지는 `RefreshInterval.allCases` 기반이다.
- [x] refresh interval 변경은 view model의 refresh loop sleep 간격에 반영된다.
- [!] refresh interval은 앱 재시작 후 유지되지 않는다.
  - UserDefaults persistence가 없다.
- [x] Settings의 메뉴바 표시 문구는 실제 동작과 맞다.
  - 현재는 `Menu Bar Display: CPU + RAM`으로 표시한다.
  - 메뉴바 표시 항목 커스터마이징은 아직 없다.
- [ ] Dock icon hide setting은 없다.

## 13. 아이콘과 앱 리소스

- [x] `MyMacStatsIcon.png`와 `MyMacStatsIcon.icns`가 앱 리소스에 있다.
- [x] 앱 bundle plist가 icon file을 지정한다.
- [x] 실제 화면 하단 Dock에서 앱 아이콘이 표시되는 것을 캡처로 확인했다.
- [x] 앱은 media library usage description을 추가하지 않았다.
  - 시스템 모니터 앱이 media library 권한을 요청하지 않아야 하므로, 권한 설명을 추가하는 대신 broad Caches 자동 스캔을 제거했다.

## 14. 개인 배포와 설치

- [x] 앱 번들 생성 스크립트가 있다.
- [x] 개인용 ad-hoc signed 앱 번들을 만들 수 있다.
- [x] 개인용 zip에 앱, 설치 command, 처음 실행 command를 포함한다.
- [x] 설치 command는 quarantine 제거, codesign verify, `/Applications` 복사, 설치 후 실행을 수행한다.
- [x] distribution check script가 zip을 실제로 풀고 임시 Applications 경로에 설치 검증을 수행한다.
- [x] 이번 점검에서 실제 `check-distribution.sh`가 통과했다.
- [!] GitHub 다운로드 후 앱을 바로 더블클릭하는 공개 배포는 Developer ID signing/notarization 없이는 불가능하다.
  - README의 안내와 일치한다.
- [!] 패키징 단위 테스트는 script source inspection 비중이 높다.
  - 다만 이번 점검에서는 script를 실제로 실행해 보완 확인했다.

## 15. 테스트 커버리지

- [x] 총 79개 XCTest가 통과한다.
- [x] CPU sampler: tick delta, kernel sampling, first sample behavior.
- [x] Memory sampler: host stats, pressure mapping, swap.
- [x] Network sampler: 64-bit counters, active interface, speed reset.
- [x] Disk sampler: I/O delta, volume fallback.
- [x] Disk candidate scanner: target restriction, timeout fallback.
- [x] HealthEvaluator: CPU/RAM/Disk/Network/Battery/debounce.
- [x] Process sorting/grouping: search and ordering basics.
- [x] Process termination: signal, protection, group behavior, stale PID identity recheck, app quit fallback.
- [x] DashboardViewModel: selection, sort/search, history, termination state.
- [x] Cause summary: CPU/RAM/Disk summary behavior.
- [x] RAM alert controller: critical persistence and reset.
- [!] BatterySampler fixture parsing 테스트는 없다.
- [!] UI snapshot/interaction 테스트는 없다.
- [!] 실제 NotificationCenter delivery 실패/권한 거부 테스트는 없다.
- [x] process termination stale PID identity 테스트가 있다.
- [x] app group Quit이 앱 종료 API를 우선 사용하고, 실패 시 signal fallback하는 테스트가 있다.
- [!] menu bar popover 실제 click/open 테스트는 없다.

## 16. README/문서 주장 점검

- [x] README의 주요 기능 대부분은 현재 구현과 일치한다.
- [x] 개인 배포 zip/설치 안내는 현재 스크립트와 일치한다.
- [x] 현재 제한 목록은 대체로 실제 미구현 범위와 일치한다.
- [!] `RAM critical 상태가 30초 이상 지속되면 macOS 알림 전송`은 표현이 강하다.
  - 실제로는 "전송 시도"에 가깝고, 권한 거부/전달 실패는 UI에 표시되지 않는다.
- [x] `Menu Bar Metric` 오해 가능 문구는 `Menu Bar Display: CPU + RAM`으로 수정됐다.
- [!] CPU 10초 sustained 설명에는 debounce로 인한 추가 지연 가능성이 빠져 있다.

## 우선 수정 순위

1. RAM 알림 전달 실패/권한 거부를 UI나 로그 상태로 노출.
2. metric별 refresh cadence를 원래 기획대로 분리하거나 README/기획에서 현재 정책으로 명확히 정리.
3. BatterySampler fixture parsing 테스트 추가.
4. UI interaction/snapshot smoke test 추가.
5. process sort comparator tie 안정성 보강.
6. 메뉴바 표시 항목 커스터마이징을 실제 기능으로 추가할지 결정.

## 현재 종합 판단

- 핵심 MVP 기능인 CPU/RAM/Disk/Network/Battery/Processes 표시, 자동 갱신, 검색/정렬, 3-column UI, 메뉴바 기본 통합, 개인 배포 zip은 구현되어 있고 이번 점검에서 대체로 확인됐다.
- 최초 점검에서 최우선으로 잡은 프로세스 종료 안전성, media library 권한 팝업 원인, Quit App UX는 후속 수정으로 보강됐다.
- 다음 기능 개발 전에 남은 주요 리스크는 RAM 알림 delivery 상태 노출, metric별 refresh cadence, BatterySampler fixture 검증, UI interaction 자동화다.
