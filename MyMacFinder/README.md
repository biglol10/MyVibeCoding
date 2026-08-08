# MyMacFinder

MyMacFinder는 macOS Finder를 Windows 파일 탐색기와 ForkLift에 가까운 사용감으로 보완하기 위한 로컬 우선 파일 관리자 앱입니다. SwiftUI와 AppKit을 함께 사용해서 Finder의 기본 파일 작업을 유지하면서 single/dual pane, inspector, 탭, 고급 검색, 압축 파일 탐색, Finder tags, 컨텍스트 메뉴, 단축키를 제공합니다.

## 주요 기능

- Single pane / dual pane 전환
- 우측 Inspector: 강화된 미리보기, 파일 정보, Copy Path, Quick Look, Reveal, 폴더 크기 계산
- 탭 생성, 닫기, 이전/다음 탭 이동
- 경로 입력, 뒤로/앞으로/상위 폴더 이동, 경로 입력창 명령(`cmd`, `terminal`, `code .`, `open .`)
- Sidebar: 기본 Favorites, Recent Folders, Locations, 사용자 추가/삭제/정렬 가능한 Favorites
- 파일/폴더 목록: 이름, 크기, 수정일, 종류, Finder Tags 열
- 컨텍스트 메뉴 Open With, 폴더 Open in Terminal / Open in VS Code, 빈 영역/행 내부 여백 Open in Terminal
- 정렬: 이름, 크기, 종류, 확장자, 생성일, 수정일, 접근일, hidden 여부, 폴더/파일 그룹 정렬
- 숨김 파일 표시 on/off
- 현재 폴더 검색과 하위 폴더 포함 검색
- 고급 검색: 파일/폴더 범위, 확장자, Finder Tag 필터
- Preview: Smart/Text Only/Off 모드, 이미지/PDF/영상/문서 Quick Look 썸네일, 텍스트/code/JSON/Markdown/log/csv 인라인 내용 미리보기
- 기본 파일 작업: 새 폴더, 이름 변경, 복제, 복사, 잘라내기, 붙여넣기, 휴지통으로 이동
- Dual pane 파일 작업: `F5`로 반대편 pane에 복사, `F6`로 반대편 pane으로 이동
- 드래그 앤 드롭 기반 복사/이동
- 충돌 처리 UI: Replace, Keep Both, Skip, Cancel
- Undo: 생성, 복사, 이동, 이름 변경, 휴지통 이동, 압축 해제/생성 결과 되돌리기
- ZIP 탐색: 압축 파일 내부 폴더 이동, session-owned Quick Look 임시 추출과 안전한 lifecycle cleanup
- ZIP 작업: 선택 항목 압축, ZIP 압축 해제
- Finder Tags: 읽기, 표시, 편집, 삭제, 검색/필터
- 디렉터리 변경 감시: 외부 생성/삭제/수정 후 Refresh/동기화
- 네트워크/외장 볼륨을 포함한 mounted volume 표시
- Settings: pane mode, inspector 표시, 숨김 파일 표시, 기본 정렬, preview mode, text preview limit, 개인정보/폴더 접근 관리

## 현재 동작 확인

최근 자동/수동 검증에서 확인한 흐름입니다.

- 앱 번들 실행 후 홈 폴더 목록 렌더링
- Return / Command-Down으로 폴더 진입, 파일은 Open 동작. 검색 결과나 테이블 선택 직후 focus가 창에 남아도 Return은 선택 항목 Open으로 라우팅
- 상위 폴더 이동은 root(`/`)에서 비활성화되고 path input을 canonical path로 유지
- Name, Date Modified, Kind 열이 좁은 화면에서도 우선적으로 읽히도록 기본 폭과 자동 리사이즈를 조정
- 실제 정렬 가능한 컬럼만 정렬 affordance를 표시하며, Tags처럼 아직 정렬 엔진이 없는 컬럼은 fake sort UI를 노출하지 않음
- Finder Tags 편집 후 table과 inspector가 즉시 갱신
- Finder Tag 필터 중 태그 편집으로 항목이 필터에서 사라지면 selection도 함께 정리
- 텍스트/code/JSON/Markdown/log/csv 파일은 inspector 안에서 내용 일부를 바로 미리보기
- 큰 텍스트 파일 preview는 설정한 byte limit까지만 읽고 truncated 상태를 표시
- preview 파일 읽기/디코딩은 백그라운드에서 실행하고, selection 변경 직후 짧게 debounce하며 stale read 취소로 클릭 반응성을 유지
- Smart preview는 큰 visual 파일의 Quick Look thumbnail 생성을 자동으로 건너뛰고, Settings에서 Text Only 또는 Off로 inline preview 비용을 더 줄일 수 있음
- binary 또는 읽을 수 없는 텍스트 preview는 아이콘과 상태 메시지로 fallback
- 일반 검색과 고급 Tag 필터가 Finder Tags를 기준으로 필터링
- 기본 파일 listing은 Finder tag metadata 지연으로 막히지 않으며, current-folder tag 필터도 백그라운드에서 필요한 항목만 tag를 읽음
- 파일 하나의 metadata 읽기 실패가 폴더 전체 listing 실패로 번지지 않고 해당 항목만 건너뜀
- ZIP 내부 가상 항목에서는 파일 시스템 변경 명령과 Edit Tags 비노출
- ZIP 내부 가상 항목은 drag pasteboard에 실제 파일 URL처럼 기록하지 않음
- ZIP Quick Look 임시 추출물은 session별 UUID owner가 관리하며 panel close, replacement, 준비 실패, cancellation 시 원본 ZIP이나 unrelated 임시 파일을 건드리지 않고 해당 owner만 정리
- archive cleanup은 descriptor-anchored quarantine/unlink를 사용하고, 비어 있는 owner 또는 기록된 identity와 일치하는 단 하나의 output leaf만 삭제 권한으로 인정합니다. Quick Look/default-open 직전에는 owner와 output device/inode/generation/mode를 다시 확인합니다.
- Quick Look cleanup retry registry와 24시간 external-open retention registry는 서로 독립적으로 load/save 실패를 처리하고 corrupt/duplicate data를 덮어쓰지 않습니다. ZIP Quick Look은 panel presentation 전에 exact artifact를 durable retry registry에 기록해 비정상 프로세스 종료 후 다음 launch에서 정리할 수 있습니다.
- ZIP 내부 항목을 기본 앱으로 여는 데 성공하면 외부 앱이 읽을 수 있도록 임시 추출물을 24시간 보존하고, 이후 앱 시작 시 ownership을 다시 검증한 뒤 만료된 owner만 정리
- macOS 기본 앱 실행이 거부되면 조용히 무시하지 않고 작업 오류를 표시하며, 취소는 사용자 오류 banner 없이 정리
- selection이 바뀌어 obsolete된 Quick Look thumbnail 요청은 generator까지 취소하고 late completion이 최신 preview를 덮어쓰지 못하게 차단
- 열려 있는 ZIP의 host 파일이 외부에서 변경되면 watcher가 archive pane을 다시 읽음
- 잘못된 ZIP 압축 해제나 중간 실패 시 빈/부분 폴더를 남기거나 기존 폴더를 교체하지 않음
- Sidebar Favorites 추가, 삭제, 이동, 누락 경로 처리
- Locations의 mounted volume 클릭 시 사라진 볼륨은 목록에서 제거하고, 읽을 수 없는 볼륨은 이동하지 않고 권한 오류 표시
- Sidebar favorite, recent folder, mounted volume, 경로 입력의 파일 상태 확인은 백그라운드 경로 상태 서비스로 처리
- 파일 작업 컨텍스트 메뉴와 단축키 동작
- Rename은 `F2`, 메뉴, 컨텍스트 메뉴에서 별도 alert 없이 선택 행의 Name cell을 바로 편집
- 경로 입력창과 inline rename은 AppKit shared field editor를 서로 침범하지 않으며, 기존 파일/폴더와 새 폴더 생성 직후 rename에서 Return은 commit, Escape는 cancel로 동작
- Dual pane에서 `F5`는 선택 항목을 반대편 pane의 현재 폴더로 복사하고, `F6`는 반대편 pane으로 이동하며 양쪽 pane 목록을 갱신
- 경로 입력창의 `cmd`, `terminal`, `code .`, `open .` 명령 해석
- `cmd` / `terminal`은 Terminal 실행 요청 후 MyMacFinder를 유지하고, Terminal completion error를 앱 오류로 표시하지 않음
- 파일 작업 실패, ZIP 압축/해제 실패, 외부 앱 실행 실패는 단순 read failure로 뭉개지지 않고 작업 종류에 맞는 오류로 표시
- 경로 입력창에 포커스가 있을 때 `Cmd+A/C/V` 같은 텍스트 편집 단축키는 파일 작업 단축키로 새지 않음
- 파일 컨텍스트 메뉴 Open With와 폴더 Open in Terminal / Open in VS Code, 빈 영역/행 내부 여백 컨텍스트 메뉴의 현재 폴더 Open in Terminal
- Open in VS Code는 LaunchServices bundle id로 앱을 찾고, 앱 위치를 찾지 못하면 하드코딩된 후보 경로 대신 사용자 셸의 `code` 명령으로 fallback
- Settings의 기본 정렬 변경은 현재 pane뿐 아니라 열려 있는 비활성 tab에도 적용
- 폴더 이동 시 table scroll position을 좌상단으로 초기화해서 이전 폴더의 가로/세로 스크롤이 새 폴더에 남지 않음
- AppKit의 실제 문서 시작 좌표를 사용해 폴더/ZIP 이동 직후 첫 행이 column header 뒤에 가려지지 않음
- 폴더를 자기 하위 경로로 copy/move/paste/drop 하는 edge case 차단
- destination의 parent symlink까지 canonical path로 검사해 symlink를 통한 자기 하위 copy/move/drop 우회를 차단하고, source 자체가 symlink인 정상 이동/복사는 leaf symlink를 보존
- 같은 폴더에 같은 이름으로 copy할 때 원본을 replace하지 않고 `copy` 이름으로 분기
- case-insensitive volume의 case-only rename과 Undo를 filesystem identity로 검증하며, 실패 cleanup이 원본을 partial destination으로 오인해 삭제하지 않음
- 새 폴더, rename, move, duplicate/copy 결과는 작업이 실제로 소유한 filesystem identity만 Undo ownership으로 기록하고, 공개 경로가 작업 직후 교체되면 해당 교체 항목을 소유물로 오인하지 않음
- 충돌 처리, replace 실패 rollback, Undo, 대용량 작업 progress banner
- 일반 파일 복사는 byte manifest 기반 진행률을 표시하고, 단일 대용량 파일도 스트리밍 복사 중 중간 진행률/취소를 처리하며 Finder tag/xattr/ACL/resource fork 계열 metadata를 보존
- copy와 ZIP extraction은 UUID staging에서 완성한 전체 tree snapshot을 확인한 뒤 공개하며, rollback은 공개 경로를 고유한 `0700` quarantine으로 먼저 이동한 다음 identity와 전체 tree를 재검증해서 외부 교체 파일을 삭제하지 않음
- 휴지통 이동 중 일부 항목 처리 후 후속 항목이 실패하면 이미 이동한 항목을 원래 위치로 복구
- 휴지통 rollback이 실패하면 실패 경로를 사용자 오류로 노출해서 조용한 데이터 잔존을 피함
- compound Undo는 모든 단계를 사전 검증하고, 중간 실패나 취소 시 이미 완료한 변경을 역순 rollback하며 rollback 불완전 상태를 명시적으로 표시
- Inspector 폴더 크기 계산은 백그라운드에서 실행해 큰 폴더 선택 시 메인 UI 정지를 줄임
- Back/Forward 대상 로드 실패 시 현재 위치와 history stack을 유지하고 오류를 표시
- pane별 load generation과 검색 generation으로 느린 이전 요청이 최신 위치, 목록, 검색 결과, 정렬, 오류, loading, history를 덮어쓰지 못하게 차단
- 파일 목록 아이콘은 파일 경로별 동기 `fileExists`/`NSWorkspace.icon(forFile:)` 조회 없이 metadata 기반 아이콘을 캐시
- 파일 목록에서 URL 순서가 같은 metadata-only 변경은 전체 table reload 대신 변경 행만 갱신
- 권한 안내, 선택 폴더 grant 저장/초기화, sandboxed launch 시 persisted grant resolve와 stale/unavailable 표시
- security-scoped bookmark 손상 시 원본 보존, stale refresh 실패 access 정리, 저장 실패 시 기존 grant 유지
- Settings > Privacy & Access는 sandbox 상태, grant 목록, 영속화 오류 경고, remove/reset, Privacy Settings 이동을 표시
- 외부에서 Finder tag 변경 후 Refresh로 table과 inspector 동기화

## 요구사항

- macOS 15 이상
- Xcode 16.4 또는 Swift 6.1 호환 toolchain
- Swift Package dependency: ZIPFoundation

## 실행

개발 중에는 SwiftPM 실행 파일로 바로 실행할 수 있습니다.

```bash
swift run MyMacFinder
```

앱 번들 형태로 실행하려면 MyMacCalendar와 같은 방식으로 아래 스크립트를 사용합니다.

```bash
./scripts/build_app.sh
open build/MyMacFinder.app
```

생성되는 앱 번들 위치:

```text
build/MyMacFinder.app
```

내부 검증용 번들은 기존 스크립트로도 만들 수 있습니다.

```bash
./scripts/create-app-bundle.sh --configuration release
open .build/app/MyMacFinder.app
```

앱 아이콘을 새로 만들거나 검증하려면:

```bash
swift scripts/generate-app-icon.swift
./scripts/verify-app-icon.sh
```

## 개인 Mac에 설치하기

개인 용도로 다른 Mac에 옮겨 쓰려면 개인 설치 패키지를 만들 수 있습니다.

```bash
./scripts/package_personal.sh
```

생성되는 파일:

```text
dist/MyMacFinder-personal-mac.zip
```

압축 해제 후 `Install MyMacFinder.command`를 우클릭해서 실행하면 `/Applications/MyMacFinder.app`으로 복사하고 로컬 ad-hoc 서명을 적용한 뒤 앱을 엽니다.

참고로 개인용 패키지는 이 Mac과 신뢰하는 개인 Mac에서 쓰기 위한 패키지입니다. 공개 배포용 notarized release zip은 아직 별도 스크립트로 제공하지 않습니다.

## 권한

MyMacFinder는 로컬 파일 관리자라서 선택한 폴더와 파일에 접근합니다. macOS가 접근 권한을 요청하면 허용해야 하며, Desktop/Documents/Downloads 또는 외장/네트워크 볼륨 접근이 막히는 경우:

```text
System Settings > Privacy & Security > Files and Folders
System Settings > Privacy & Security > Full Disk Access
```

에서 MyMacFinder 권한을 확인하세요.

샌드박스 빌드에서는 Settings > Privacy & Access에서 폴더를 직접 선택해 security-scoped folder grant를 저장할 수 있습니다. 개인 개발 빌드는 보통 unrestricted 상태로 동작하지만, macOS TCC가 보호하는 위치는 시스템 설정 권한이 필요할 수 있습니다.

## 테스트

전체 테스트:

```bash
swift test
```

GitHub Actions CI도 루트 `.github/workflows/ci.yml`에서 `swift test --enable-code-coverage`, `swift build`, 앱 아이콘 검증, 앱 번들 빌드를 실행합니다.

앱 아이콘과 번들 검증:

```bash
./scripts/verify-app-icon.sh
```

현재 테스트 범위:

- 파일 시스템 listing, hidden file, symlink, Finder tag lazy loading/background current-folder filtering/read fallback, 항목별 metadata 실패 skip
- 파일 작업 copy/move/rename/duplicate/trash, source preflight, conflict decision, replace rollback, trash partial rollback, rollback failure surfacing
- case-only rename 성공/실패 원본 보존, strict filesystem identity, hard-link 오판 방지, case-only Undo
- 파일 작업/ZIP 작업/외부 앱 실행 오류 분류
- copy/move descendant guard, same-folder copy naming, rename separator validation
- copy byte progress, single-file streaming progress, mid-copy cancellation cleanup, extended attribute metadata preservation
- drag and drop pasteboard/validator/store flow, descendant drop guard, archive-backed drag 차단
- undo action과 undo command
- transactional compound Undo preflight/rollback/rollback-incomplete 처리
- 정렬, 검색, 고급 검색, Finder tag 검색, 태그 편집 후 필터/selection 동기화, 탭별 검색 상태 복원, stale recursive search 차단
- recursive search symlink 비진입, root/descendant 권한 구분, unreadable directory skip, cancellation 전파
- pane load generation, 제거된 secondary pane의 late completion, Back/Forward 중 active pane 전환 경쟁 상태
- ZIP 탐색, 압축, 압축 해제
- invalid/unsafe ZIP extraction side-effect 방지, unsafe archive entry path filtering, extraction partial folder cleanup
- preview content loader/policy: 텍스트 판별, byte limit, Smart/Text Only/Off mode, 큰 visual file thumbnail skip, main-thread read 방지, stale read cancellation, binary fallback, read error fallback
- tabs, layout settings, sidebar favorites add/reorder/remove/load dedupe, favorite/recent/volume path status background checks, recent folder load dedupe, full-row sidebar hit targets, mounted volume sorting/stale/unreadable handling
- root 상위 폴더 이동 비활성화와 path input focus clear
- Back/Forward target load failure 시 history stack 보존
- directory watcher 기반 active/visible pane refresh, ZIP host 변경 시 archive pane refresh
- path input command resolver, Terminal fire-and-forget launch, empty-area Open in Terminal routing, Open With menu routing, VS Code bundle lookup/user-shell command fallback, external app launcher duplicate-completion guard
- permission guidance, security-scoped bookmark store, persisted grant resolution/access lifecycle
- AppKit table bridge, shared field editor 격리, 기존 파일/폴더 및 새 폴더 inline rename Return commit/Escape cancel, column sizing, location-change scroll reset, supported-column sort affordance, content-aware row whitespace context menu, context menu command availability, responder-chain shortcuts, F5/F6 opposite-pane commands, system pasteboard file copy/paste
- metadata-based table row icon caching
- metadata-only table row reload
- archive preview owner containment/identity/symlink 검증, partial extraction cleanup, corrupt/duplicate retention 및 retry registry fail-closed 처리
- transactional Quick Look session의 reverse-order cleanup, panel close/replacement one-shot release, stale tab/pane/search/selection completion 차단
- ZIP default-open retention의 24시간 경계와 startup cleanup, default-open 실패 표시, thumbnail generator cancellation 및 late completion 차단
- inspector model, thumbnail/Quick Look wiring, folder size background execution

수동 QA 기록:

아래 문서들은 실행 당시의 스냅샷입니다. 각 파일 안의 테스트 개수나 번들 경로가 현재 최신 검증 숫자와 다를 수 있으므로, 최신 실행/검증 기준은 이 README의 실행, 테스트, 개발 메모 섹션을 우선합니다.

```text
docs/qa/file-operations-stabilization-manual-qa.md
docs/qa/large-file-operation-ux-manual-qa.md
docs/qa/permission-policy-manual-qa.md
docs/qa/shortcut-menu-parity-manual-qa.md
docs/qa/sidebar-click-add-ux-manual-qa.md
docs/qa/sidebar-editable-favorites-manual-qa.md
docs/qa/file-table-icons-manual-qa.md
docs/qa/finder-tags-manual-qa.md
docs/qa/path-command-open-with-manual-qa.md
docs/qa/inspector-preview-manual-qa.md
docs/qa/regression-audit-2026-06-29.md
docs/qa/e2e-ui-ux-audit-2026-06-30.md
docs/qa/2026-07-22-rename-filesystem-safety-verification.md
docs/qa/2026-08-04-full-feature-audit.md
docs/qa/2026-08-08-archive-preview-lifecycle-verification.md
```

## 프로젝트 구조

```text
Sources/MyMacFinder
  App/                 macOS 앱 진입점과 Settings 전용 뷰
  Domain/              파일, 정렬, 명령, 충돌, undo, archive, permission, tag 모델
  Resources/           App icon과 번들 리소스
  Services/            파일 시스템, 파일 작업, 압축, 검색, 감시, 권한, tag 서비스
  Stores/              Explorer 상태, 탭, 설정, sidebar 관리
  UI/                  SwiftUI/AppKit 하이브리드 UI

Tests/MyMacFinderTests
  파일 작업, 검색, 정렬, 압축, 설정, 권한, tabs, sidebar, UI bridge 단위 테스트

scripts/build_app.sh
  release build 후 build/MyMacFinder.app 번들 생성

scripts/package_personal.sh
  개인 Mac 설치용 dist/MyMacFinder-personal-mac.zip 생성
```

## 알려진 제한

- 공개 배포용 Developer ID 서명, notarization, auto-update는 아직 연결되어 있지 않습니다.
- ZIP 내부 항목은 가상 항목이므로 이름 변경, 삭제, Finder Tags 편집 같은 직접 쓰기 작업은 제공하지 않습니다.
- 텍스트 preview는 Inspector 반응성을 위해 기본 64KB까지만 읽으며, Settings에서 16KB/64KB/256KB/1MB 중 선택할 수 있습니다. Smart mode에서는 큰 visual 파일의 inline thumbnail 생성을 건너뜁니다. 전체 파일 확인은 Open 또는 Quick Look을 사용하세요.
- 네트워크 볼륨은 mounted volume으로 탐색할 수 있지만, SMB/NFS 연결을 새로 생성하는 전용 UI는 없습니다.
- Finder Tags는 macOS resource value 기반이라 파일 시스템이나 볼륨에 따라 지원되지 않을 수 있습니다.
- Redo, Spotlight index/content 검색, Windows식 접이형 Group By UI는 아직 제공하지 않습니다.
- 실제 GUI에서 준비 중 tab/pane 전환, 느린 대용량 항목의 generator cancellation, Quick Look panel replacement, 주입된 default-open 실패 표시는 자동 회귀 테스트로 검증했지만 release 앱 수동 재현은 추가 확인 대상입니다. 실제 GUI로는 normal/ZIP Quick Look, panel close cleanup, PDF -> PNG -> text 최종 선택, ZIP default-open/retention, 만료 cleanup, Quick Look 도중 프로세스 종료 후 durable retry를 확인했습니다.
- AppKit Quick Look과 LaunchServices는 pathname URL을 받으므로 마지막 no-follow identity 검사 직후 framework가 실제 경로를 열기 전까지 같은 사용자 프로세스가 pathname을 교체할 수 있는 잔여 race가 있습니다. 현재 구현은 handoff 직전 mismatch를 차단하지만 handle-based consumer API 없이 이 kernel-level window를 완전히 제거하지는 못합니다.

## 개발 메모

현재 검증 명령:

```bash
swift test --enable-code-coverage
swift build -Xswiftc -warnings-as-errors
git diff --check
./scripts/build_app.sh
./scripts/verify-app-icon.sh
./scripts/package_personal.sh
```

2026-08-09 최신 archive preview lifecycle 검증에서 `swift test --enable-code-coverage`는 591 tests / 0 failures, `swift build -Xswiftc -warnings-as-errors`는 경고 없이 통과했습니다. 새 release 앱과 개인 설치 패키지의 strict codesign/ZIP 무결성을 확인했고 build, packaged, installed 실행 파일 SHA-256은 `64cb9376df0e1ca922a11c6cfbb1469563a92a3a873370fba244d43883ba024f`, ZIP SHA-256은 `9daf4f28fe0dc5797165f989ef31e539d495d426e90952b14cca3e49a0f6075c`입니다. 별도 QA bundle ID와 bare-UUID 임시 root에서 실제 ZIP panel close cleanup, external-open retention/expiry, 열린 Quick Look 도중 exact QA PID 종료 후 durable launch retry를 exact owner/record condition polling으로 확인했습니다. QA process, defaults domain, app, root, exact preview owners는 모두 제거했습니다. 같은 release를 UUID staging/rollback backup으로 `/Applications/MyMacFinder.app`에 안전 교체했으며 현재 PID `94702`, 실행 경로 `/Applications/MyMacFinder.app/Contents/MacOS/MyMacFinder`를 확인했습니다. 실제 GUI와 자동 검증의 정확한 경계는 `docs/qa/2026-08-08-archive-preview-lifecycle-verification.md`에 기록되어 있습니다.
