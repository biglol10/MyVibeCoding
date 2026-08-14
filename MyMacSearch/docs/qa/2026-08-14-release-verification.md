# MyMacSearch 릴리스 검증 — 2026-08-14

## 검증 결과

- SwiftUI 네이티브 앱 번들을 `com.biglol.MyMacSearch`, 버전 `0.1.0` (`1`), 최소 macOS 14로 빌드했다.
- 초기 스캔, SQLite FTS5 인덱스, FSEvents 반영, 위치별 상태·재스캔·검증, 정렬·크기 필터, 저장/최근 검색, 다중 선택 액션을 포함한 전체 테스트가 통과했다.
- synthetic Desktop, Documents, Downloads 범위에서 최초 스캔과 `Watching`, `Paused`, `Resume`, Index Center, Verify Index, 저장 검색, 최근 검색, 헤더 정렬, 유효/잘못된 크기 필터를 실제 UI로 확인했다.
- 결과가 1개에서 8개로 늘 때 발생하던 AppKit `NSTableView` 재진입 경고를 호출 스택으로 추적했다. 결과 테이블만 고정 행 높이로 설정한 뒤 같은 전환을 반복했고 런타임 경고가 다시 발생하지 않았다.
- 개인 설치 ZIP을 격리된 임시 Applications 폴더와 실제 `/Applications/MyMacSearch.app`에 각각 설치했다. 두 설치에서 strict deep codesign과 패키지/설치 실행 파일 해시 비교가 통과했다.

## 자동 테스트와 성능

```text
swift test / xctest: 103 tests, 1 opt-in benchmark skipped, 0 failures
Release warnings-as-errors build: passed
100,000-row all-sort pagination regression: passed
git diff --check: passed
```

100,000-row 회귀 테스트는 10개 정렬 모드에서 첫 페이지와 다음 keyset 페이지의 정확한 순서, 중복 없음, 크기 경계를 검증했다. 별도 1,000,000-row Release benchmark도 최종 스키마와 코드로 통과했다.

```text
entries: 1,000,000
insert: 247.380 seconds
warm selective search p95 across 10 sorts: 8.688–40.517 ms
slowest sort: sizeSmallest, p50 8.007 ms / p95 40.517 ms
Index Center health snapshot: 2.674 ms
database size: 857,350,144 bytes
result: all search p95 <= 50 ms, health <= 250 ms
```

백만 행 테스트는 생성한 파일 메타데이터를 SQLite에 넣는 synthetic benchmark다. 실제 파일 시스템에서 백만 개 파일을 순회하는 시간은 디스크, 권한, 디렉터리 구조에 따라 달라진다.

## 실제 UI 검증

- 권장 위치 Desktop, Documents, Downloads와 기본 제외 정책을 표시하는 최초 실행 화면을 확인했다.
- 8개 synthetic 항목을 인덱싱하고 `report kind:pdf`가 PDF 2개를 즉시 반환하는지 확인했다.
- Name 헤더 정렬, `PDF Reports` 저장 검색, Recent Searches 기록을 확인했다.
- Index Center에서 범위별 `3 / 3 / 2`개 항목, 전체 8개, `Watching`, Verify Index 성공을 확인했다.
- Pause가 `Paused`로 바뀌고 Resume가 `Watching`으로 복귀하는지 확인했다.
- `size:100`은 지원되지 않는 단위 오류를 표시하고, `size:<=1KB`는 토큰과 8개 결과를 표시하는지 확인했다.
- 마지막 UI 확인은 격리된 홈과 Application Support 경로를 사용했으며 사용자의 실제 폴더를 스캔하지 않았다.

## 배포 및 설치 검증

```text
ZIP SHA-256:
7f180cd911b0ff91a876a4834a2532e7750d3e2fdfd2b09a019b662d3ea62848

Build / packaged / installed executable SHA-256:
089a81c4f3dc1a33bba1313d77eb5baea1db31437f1dae0dc48bad8d4dfa1a80

Installed bundle:
CFBundleIdentifier = com.biglol.MyMacSearch
CFBundleShortVersionString = 0.1.0
CFBundleVersion = 1
LSMinimumSystemVersion = 14.0
```

- `unzip -tq`: 통과
- packaged app `codesign --verify --deep --strict`: 통과
- `/Applications/MyMacSearch.app` `codesign --verify --deep --strict`: 통과
- build, packaged, installed 실행 파일 SHA-256 일치: 통과
- 설치된 실행 파일 직접 시작과 새 프로세스 실행 확인: 통과

## 검증 경계

- 이 개인용 빌드는 ad-hoc 서명이며 Developer ID 서명이나 notarization을 하지 않았다. strict codesign은 통과하지만 Gatekeeper `spctl --assess`는 예상대로 거부한다.
- Full Disk Access를 실제로 부여하거나 보호된 시스템 폴더를 스캔하지 않았다.
- 외장 디스크와 네트워크 볼륨의 offline, identity mismatch, remount 동작은 단위·통합 테스트로 검증했으며 실제 장치를 연결한 수동 검증은 하지 않았다.
- 이전 검증에서 종료 중 커널 대기 상태(`UE`)에 들어간 PID 2370이 남아 있어 LaunchServices 기반 UI 자동화는 기존 프로세스로 전달되어 timeout 됐다. 설치된 동일 해시 실행 파일은 직접 실행한 새 PID 5198로 정상 시작했고 경고 없이 종료했다. 오래된 PID는 로그아웃 또는 재시작 후 정리된다.
