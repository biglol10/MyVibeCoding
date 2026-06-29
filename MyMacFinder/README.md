# MyMacFinder

MyMacFinder는 macOS Finder를 Windows 파일 탐색기와 ForkLift에 가까운 사용감으로 보완하기 위한 로컬 우선 파일 관리자 앱입니다. SwiftUI와 AppKit을 함께 사용해서 Finder의 기본 파일 작업을 유지하면서 single/dual pane, inspector, 탭, 고급 검색, 압축 파일 탐색, Finder tags, 컨텍스트 메뉴, 단축키를 제공합니다.

## 주요 기능

- Single pane / dual pane 전환
- 우측 Inspector: 강화된 미리보기, 파일 정보, Copy Path, Quick Look, Reveal, 폴더 크기 계산
- 탭 생성, 닫기, 이전/다음 탭 이동
- 경로 입력, 뒤로/앞으로/상위 폴더 이동, 경로 입력창 명령(`cmd`, `terminal`, `code .`, `open .`)
- Sidebar: 기본 Favorites, Recent Folders, Locations, 사용자 추가/삭제/정렬 가능한 Favorites
- 파일/폴더 목록: 이름, 크기, 수정일, 종류, Finder Tags 열
- 컨텍스트 메뉴 Open With, 폴더 Open in Terminal / Open in VS Code
- 정렬: 이름, 크기, 종류, 확장자, 생성일, 수정일, 접근일, hidden 여부, 폴더/파일 그룹 정렬
- 숨김 파일 표시 on/off
- 현재 폴더 검색과 하위 폴더 포함 검색
- 고급 검색: 파일/폴더 범위, 확장자, Finder Tag 필터
- Preview: 이미지/PDF/영상/문서 Quick Look 썸네일, 텍스트/code/JSON/Markdown/log/csv 인라인 내용 미리보기
- 기본 파일 작업: 새 폴더, 이름 변경, 복제, 복사, 잘라내기, 붙여넣기, 휴지통으로 이동
- 드래그 앤 드롭 기반 복사/이동
- 충돌 처리 UI: Replace, Keep Both, Skip, Cancel
- Undo: 생성, 복사, 이동, 이름 변경, 휴지통 이동, 압축 해제/생성 결과 되돌리기
- ZIP 탐색: 압축 파일 내부 폴더 이동, Quick Look용 임시 추출
- ZIP 작업: 선택 항목 압축, ZIP 압축 해제
- Finder Tags: 읽기, 표시, 편집, 삭제, 검색/필터
- 디렉터리 변경 감시: 외부 생성/삭제/수정 후 Refresh/동기화
- 네트워크/외장 볼륨을 포함한 mounted volume 표시
- Settings: pane mode, inspector 표시, 숨김 파일 표시, 기본 정렬, 개인정보/폴더 접근 관리

## 현재 동작 확인

최근 자동/수동 검증에서 확인한 흐름입니다.

- 앱 번들 실행 후 홈 폴더 목록 렌더링
- Return / Command-Down으로 폴더 진입, 파일은 Open 동작
- 상위 폴더 이동은 root(`/`)에서 비활성화되고 path input을 canonical path로 유지
- Date Modified와 Tags 열이 좁은 화면에서도 잘리지 않도록 표시
- Finder Tags 편집 후 table과 inspector가 즉시 갱신
- 텍스트/code/JSON/Markdown/log/csv 파일은 inspector 안에서 내용 일부를 바로 미리보기
- 큰 텍스트 파일 preview는 16KB까지만 읽고 truncated 상태를 표시
- preview 파일 읽기/디코딩은 백그라운드에서 실행하고, selection 변경 직후 짧게 debounce해 클릭 반응성을 유지
- binary 또는 읽을 수 없는 텍스트 preview는 아이콘과 상태 메시지로 fallback
- 일반 검색과 고급 Tag 필터가 Finder Tags를 기준으로 필터링
- 기본 파일 listing은 Finder tag metadata 지연으로 막히지 않으며, tag 검색/편집 시 필요한 항목만 tag를 읽음
- ZIP 내부 가상 항목에서는 파일 시스템 변경 명령과 Edit Tags 비노출
- 잘못된 ZIP 압축 해제 실패 시 빈 폴더를 남기거나 기존 폴더를 교체하지 않음
- Sidebar Favorites 추가, 삭제, 이동, 누락 경로 처리
- 파일 작업 컨텍스트 메뉴와 단축키 동작
- 경로 입력창의 `cmd`, `terminal`, `code .`, `open .` 명령 해석
- 파일 컨텍스트 메뉴 Open With와 폴더 Open in Terminal / Open in VS Code
- 폴더를 자기 하위 경로로 copy/move/paste/drop 하는 edge case 차단
- 같은 폴더에 같은 이름으로 copy할 때 원본을 replace하지 않고 `copy` 이름으로 분기
- 충돌 처리, Undo, 대용량 작업 progress banner
- 권한 안내, 선택 폴더 grant 저장/초기화
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

앱 아이콘과 번들 검증:

```bash
./scripts/verify-app-icon.sh
```

현재 테스트 범위:

- 파일 시스템 listing, hidden file, symlink, Finder tag lazy loading/read fallback
- 파일 작업 copy/move/rename/duplicate/trash와 conflict decision
- copy/move descendant guard, same-folder copy naming, rename separator validation
- drag and drop pasteboard/validator/store flow와 descendant drop guard
- undo action과 undo command
- 정렬, 검색, 고급 검색, Finder tag 검색, 탭별 검색 상태 복원
- ZIP 탐색, 압축, 압축 해제
- invalid ZIP extraction side-effect 방지
- preview content loader: 텍스트 판별, byte limit, main-thread read 방지, binary fallback, read error fallback
- tabs, layout settings, sidebar favorites add/reorder/remove, full-row sidebar hit targets, mounted volumes
- root 상위 폴더 이동 비활성화와 path input focus clear
- path input command resolver, Open With menu routing, external app launcher injection
- permission guidance, security-scoped bookmark store
- AppKit table bridge, column sizing, context menu command availability, responder-chain shortcuts, system pasteboard file copy/paste
- inspector model, thumbnail/Quick Look wiring

수동 QA 기록:

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
```

## 프로젝트 구조

```text
Sources/MyMacFinder
  App/                 macOS 앱 진입점
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
- 텍스트 preview는 Inspector 반응성을 위해 기본 16KB까지만 읽습니다. 전체 파일 확인은 Open 또는 Quick Look을 사용하세요.
- 네트워크 볼륨은 mounted volume으로 탐색할 수 있지만, SMB/NFS 연결을 새로 생성하는 전용 UI는 없습니다.
- Finder Tags는 macOS resource value 기반이라 파일 시스템이나 볼륨에 따라 지원되지 않을 수 있습니다.

## 개발 메모

현재 검증 명령:

```bash
swift test --enable-code-coverage
swift build
git diff --check
./scripts/build_app.sh
```

최근 검증 기준으로 `swift test --enable-code-coverage`는 286 tests / 0 failures로 통과했습니다. `./scripts/build_app.sh`로 생성한 `build/MyMacFinder.app`도 직접 실행해 홈 폴더 목록 렌더링과 root(`/`)에서 Up 버튼 비활성화를 확인했습니다.
