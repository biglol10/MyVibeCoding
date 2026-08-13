# Persistence and Session Restoration Verification

- 검증일: 2026-08-13
- 대상: Swift 6.1, SwiftUI + AppKit, macOS 15+
- 격리 QA bundle ID: `com.biglol.MyMacFinder.qa.b18656ce-58c4-4249-87ee-09f00d794538`
- 격리 QA root: `/tmp/MyMacFinderSessionQA-b18656ce-58c4-4249-87ee-09f00d794538`

## 결과

Settings, Sidebar, Previous Session 저장소는 decode/save 실패를 호출자에게 전달하고, 읽을 수 없는 원본 값을 자동으로 덮어쓰지 않는다. 이전 세션 복원은 bounded/versioned snapshot으로 탭, pane, 위치, 활성 index, 정렬과 그룹만 저장한다. 검색, 선택, history, Undo, clipboard, 진행 중 작업, rename과 오류 상태는 새 실행으로 전달하지 않는다.

복원 경로 검증과 첫 read fallback은 tab ID, pane ID, 원래 위치를 기준으로 commit한다. 검증 중 사용자가 다른 위치로 이동했거나 pane이 교체되면 오래된 결과는 최신 상태를 변경하지 않는다. 성공한 새 navigation은 복원 전용 fallback을 즉시 소모하므로 이후 일반 refresh 실패를 시작 실패로 오인하지 않는다.

## 자동 검증

| 검증 | 결과 |
|---|---|
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| `xcodebuild -version` | Xcode 16.4, build 16F6 |
| `xcrun --find xctest` | Xcode toolchain의 `xctest` 확인 |
| `swift build -Xswiftc -warnings-as-errors` | 통과, compiler warning 없음 |
| `swift test --enable-code-coverage` | 623 tests / 0 failures |
| 세션·pane race 집중 검증 | 16 tests / 0 failures |
| `git diff --check` | 통과 |
| `./scripts/build_app.sh --configuration release` | `build/MyMacFinder.app` 생성 |
| strict codesign | build, packaged, installed app 모두 통과 |
| `./scripts/verify-app-icon.sh` | 통과 |
| `./scripts/package_personal.sh` + `unzip -tq` | 통과 |

새 회귀 테스트는 다음을 포함한다.

- settings/sidebar/session 손상 원본 보존과 영역별 reset
- 최대 1 MiB, 최대 20개 탭, 탭당 최대 2개 pane, future version 거부
- missing/unreadable filesystem 및 누락 ZIP host fallback
- 비활성 restored tab의 첫 read 실패 fallback
- 지연된 복원 검증이 최신 navigation을 덮지 못하도록 context 검증
- 성공한 최신 navigation 이후 복원 fallback이 재사용되지 않음
- debounce, lifecycle flush, save 실패 후 자동 retry 차단
- transient search/selection/history/Undo 비복원
- 테스트용 `ExplorerStore` 인스턴스 사이 session 저장소 격리

## 실제 앱 QA

격리된 release 앱과 위 UUID root만 사용했다. 홈 폴더의 기존 파일과 실제 Trash에는 파일 작업을 수행하지 않았다.

확인한 흐름:

1. Settings > General에 `Restore Previous Session`이 기본 활성 상태로 표시됨.
2. dual pane에서 `left`, `right` 폴더를 각각 열고 두 번째 `other` 탭을 만든 뒤 재실행함.
3. 재실행 후 두 탭 순서, 활성 `other` 탭, 첫 탭의 `left`/`right` pane 위치가 복원됨.
4. 종료 전에 입력한 `transient-query` 검색어는 재실행 후 비어 있었음.
5. session UserDefaults에 8-byte 손상 값을 주입한 뒤 실행해도 crash하지 않고 안전한 시작 위치를 표시함.
6. Settings에 `Saved Data Recovery > Previous Session` 경고와 Reset이 표시됨.
7. 앱 실행과 설정 진입 뒤에도 손상 값 `00ff0102aabbccdd`가 그대로 유지됨.
8. Reset을 누른 뒤 경고가 사라지고 365-byte 정상 snapshot이 생성됨.
9. 복원 설정을 끈 뒤 임시 폴더로 이동하고 재실행하면 저장 위치 대신 기본 홈에서 시작함.

QA PID와 bundle, UserDefaults domain, UUID root는 검증 뒤 모두 제거했다. QA 실행 중 즉시 crash는 없었다.

## 배포물과 설치

- build/packaged/installed executable SHA-256: `be4d4c50c1e1cf4c48ba9539fe6fc4b76b3bccb7f8aa1a7fc64df62de96c33dc`
- personal ZIP SHA-256: `3f594c1a5e35fe0b05e096970afd9d89c55c98b135ae0b5bec9a0b7d64bc02d6`
- 설치 경로: `/Applications/MyMacFinder.app`
- 실행 PID: `63573`
- 실행 파일: `/Applications/MyMacFinder.app/Contents/MacOS/MyMacFinder`
- 기존 설치본의 복구용 백업: `/Users/biglol/.Trash/MyMacFinder-backup-c0dc5b4c-e9cd-4367-aed9-8053fe313981.app`

설치는 UUID staging에서 서명과 해시를 확인하고 기존 설치본을 고유 backup으로 이동한 뒤 교체했다. 설치본의 strict signature와 source 동일 해시, 실제 PID 실행 경로를 확인한 후 backup만 Trash로 이동했다. staging 잔여물은 없다.

## 검증 경계

- settings와 sidebar 손상 복구는 주입 XCTest로 확인했고 실제 GUI 손상 주입은 session 영역만 수행했다.
- missing/unreadable 복원 위치와 ZIP host fallback은 XCTest로 확인했으며 실제 network volume을 분리하는 수동 테스트는 수행하지 않았다.
- 이 변경은 파일 작업, 실제 Trash, sandbox permission grant를 수정하지 않았다. 관련 기존 회귀 테스트는 전체 suite에 포함되지만 이번 실제 QA에서 실파일 삭제나 권한 변경은 수행하지 않았다.
- 개인 설치본은 ad-hoc 서명이다. Developer ID, notarization, entitlement 기반 공개 배포 검증은 별도 과제다.
