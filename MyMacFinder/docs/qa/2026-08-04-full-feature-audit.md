# MyMacFinder 전체 기능 점검 체크리스트

- 점검일: 2026-08-04
- 시작 기준: `master`의 `4b01f3d`
- 대상: Swift 6.1, SwiftUI + AppKit, macOS 15 이상
- 실제 UI 대상: 별도 QA bundle ID로 복사하고 ad-hoc 서명한 release 앱
- 테스트 데이터: UUID가 포함된 시스템 임시 디렉터리만 사용

## 상태 표기

- `[x]`: 현재 소스 연결을 확인했고, 이번 점검의 자동 테스트 또는 실제 앱 QA 근거가 있음
- `[~]`: 구현과 자동 테스트는 있으나 OS 권한, 외부 앱, 실제 Trash, 네트워크 장비 등 이번 환경에서 실제 흐름 전체를 실행하지 않음
- `[ ]`: 미구현, UI 미연결 또는 후속 수정이 필요한 위험

이 문서는 기능의 존재와 검증 경계를 함께 기록한다. 단위 테스트 통과를 실제 macOS 권한 창, 외부 앱, 네트워크 볼륨 또는 실제 Trash 동작을 확인한 것으로 간주하지 않는다.

## 1. 앱 시작, 창, 레이아웃, 설정

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | release 앱 번들 실행과 메인 창 표시 | 별도 QA bundle ID 앱을 직접 실행해 홈 목록 렌더링 확인 |
| [x] | Sidebar + Toolbar + Tab bar + File table + Inspector 배치 | 실제 앱 화면과 접근성 트리 확인 |
| [x] | Single Pane / Dual Pane 설정 | 실제 Settings 변경 및 양쪽 pane 렌더링 확인 |
| [x] | Inspector 표시 on/off 설정 | `ExplorerLayoutSettingsTests`, Settings UI 확인 |
| [x] | 숨김 파일 표시 on/off 설정 | 실제 앱에서 `.hidden-note.txt` 표시/비표시와 설정 복원 확인 |
| [x] | 기본 정렬, 방향, 폴더/파일 우선순위 설정 | `ExplorerSettingsStoreTests`, `ExplorerSortSettingsTests`, Settings UI 확인 |
| [x] | Preview Smart / Text Only / Off 설정 | `FilePreviewPolicyTests`, Settings UI 확인 |
| [x] | 텍스트 미리보기 한도 16KB/64KB/256KB/1MB | `FilePreviewContentLoaderTests`, Settings UI 확인 |
| [x] | Privacy & Access 전용 설정 화면 | 실제 unrestricted 상태 및 empty grant UI 확인 |
| [x] | 다크/라이트 시스템 외관 적응 | SwiftUI/AppKit 시스템 색상 사용, release 다크 화면 확인 |

## 2. 경로 탐색과 History

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | 경로 입력 후 Return 이동 | 실제 UUID QA 경로 이동 확인 |
| [x] | 상대 경로와 `~` 경로 해석 | `PathResolverTests` |
| [x] | Back / Forward / Up 이동 | 실제 Back/Up 및 `ExplorerStoreTests` 확인 |
| [x] | `/`에서 Up 비활성화와 canonical path 유지 | `ExplorerStoreTests`, README 기존 수동 기록 |
| [x] | History 대상 로드 실패 시 현재 위치와 stack 보존 | `ExplorerStoreTests` |
| [x] | Sidebar 이동 시 path input 갱신 및 focus 해제 | `ExplorerFocusCommandTests`, 실제 Recent 이동 확인 |
| [x] | 다른 위치 이동 시 search input 초기화 | `ExplorerSearchStoreTests`, 실제 Sidebar 이동 확인 |
| [x] | 같은 tab의 pane별 현재 위치 유지 | `ExplorerTabStoreTests`, dual-pane 실제 QA |
| [x] | 느린 이전 navigation 결과의 최신 pane 덮어쓰기 차단 | `ExplorerPaneLoadRaceTests` |
| [x] | 제거된 secondary pane의 늦은 완료로 crash하지 않음 | `ExplorerPaneLoadRaceTests` |
| [x] | 위치 이동 뒤 목록 첫 행이 헤더 뒤에 가려지지 않음 | 이번 점검에서 재현 후 `scrollToBeginningOfDocument`로 수정, 실제 release QA와 회귀 테스트 확인 |

## 3. 탭과 Pane

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | 새 탭, 탭 닫기, 활성 탭 변경 | 실제 두 탭 전환 및 `ExplorerTabStoreTests` |
| [x] | 탭별 위치, 선택, 검색 상태 복원 | 실제 A/B 탭 검색 복원 및 `ExplorerTabStoreTests` |
| [x] | 동일 pane 재활성화 시 불필요한 검색/tag 재시작 방지 | `ExplorerSearchStoreTests`, `ExplorerAdvancedSearchStoreTests` |
| [x] | Dual Pane에서 active pane 구분 | 실제 양쪽 pane 위치 변경과 active 표시 확인 |
| [x] | `F5` 반대 pane 복사 | 실제 `copy-source.txt` 복사 및 양쪽 목록 갱신 확인 |
| [x] | `F6` 반대 pane 이동 | `ExplorerShortcutRoutingTests`, `ExplorerCommandTests` |
| [x] | F5 복사 Undo | 실제 반대 pane 복사 후 `Cmd+Z`로 결과 제거 확인 |

## 4. 파일 목록, 선택, 스크롤

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | Name, Size, Date Modified, Kind, Tags 열 | 실제 앱 및 `FileTableViewReuseTests` |
| [x] | recursive 결과의 Path 열 | 실제 Subfolders 검색 및 `ExplorerSearchStoreTests` |
| [x] | Name 기본 폭과 first-column 자동 확장 | `FileTableViewReuseTests`, 실제 넓은 창 확인 |
| [x] | 긴 파일명/날짜/종류 중간 말줄임과 고정 행 높이 | AppKit reusable cell 구현과 실제 화면 확인 |
| [x] | AppKit `NSTableView` reusable cells 기반 대용량 목록 렌더링 | `FileTableViewReuseTests`; 전체 SwiftUI 행을 한꺼번에 만드는 구조가 아님 |
| [x] | metadata-only 변경 시 전체 reload 대신 해당 행 reload | `FileTableViewReuseTests` |
| [x] | metadata 기반 아이콘 캐시와 cache pruning | `FileTableViewReuseTests` |
| [x] | 단일 선택과 키보드 range 선택 | 실제 `Shift+Down` 다중 선택, `FileTableViewReuseTests` |
| [~] | 마우스 `Shift+Click` range 선택 | native multiple-selection과 회귀 테스트는 있음; Computer Use가 modifier+mouse 조합을 직접 합성하지 못해 이번 실제 클릭은 미실행 |
| [x] | 빠른 double-click 시 클릭한 행을 먼저 선택한 뒤 Open | `FileTableViewReuseTests`, 실제 폴더 double-click 확인 |
| [x] | Return / Command-Down으로 선택 항목 Open | `ExplorerShortcutRoutingTests`, 실제 폴더 진입 확인 |
| [x] | 위치 변경 시 이전 가로/세로 스크롤을 새 위치에 유지하지 않음 | `FileTableViewReuseTests` 및 실제 첫 행 표시 확인 |

## 5. 정렬, 숨김, 그룹 순서

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | 이름, 크기, 종류, 확장자 정렬 | `SortEngineTests`, 실제 Date Modified/Name header 정렬 확인 |
| [x] | 생성일, 수정일, 접근일, hidden 정렬 | `SortEngineTests`, `ExplorerSortSettingsTests` |
| [x] | 오름차순 / 내림차순 | `SortEngineTests` |
| [x] | Folders First / Files First / Mixed | `SortEngineTests`, Settings UI 확인 |
| [x] | 현재 폴더와 완료된 recursive 결과 즉시 재정렬 | `ExplorerSortSettingsTests`, `ExplorerSearchStoreTests` |
| [x] | 비활성 tab에도 기본 정렬 설정 반영 | `ExplorerSortSettingsTests` |
| [x] | 지원하는 열만 sort affordance 제공 | `FileTableViewReuseTests`; Tags 열은 가짜 정렬 버튼으로 동작하지 않음 |
| [ ] | Windows Explorer식 접을 수 있는 Group By 섹션 UI | 내부 grouping model/engine 일부는 있으나 production UI와 Store에는 연결되지 않음 |

## 6. 검색과 Finder Tags

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | 현재 폴더 일반 텍스트 검색 | 실제 `preview` 검색, `ExplorerSearchStoreTests` |
| [x] | 하위 폴더 포함 recursive 검색 | 실제 nested `find-me.txt` 검색, `FileSearchServiceTests` |
| [x] | 파일/폴더 범위와 확장자 필터 | `ExplorerAdvancedSearchStoreTests`, `FileEntrySearchFilterTests` |
| [x] | 명시적 Finder Tag query | `ExplorerAdvancedSearchStoreTests`, `FinderTagServiceTests` |
| [x] | ordinary query로 파일명 또는 Finder Tag 검색 | `ExplorerSearchStoreTests`, `ExplorerAdvancedSearchStoreTests` |
| [x] | current-folder tag metadata lazy/background 로딩 | `ExplorerSearchStoreTests`, `FileSystemServiceTests` |
| [x] | 기본 listing이 Finder Tag I/O로 막히지 않음 | `FileSystemServiceTests` |
| [x] | 검색 context의 tab/pane/location/scope/query/tag 일치 후 commit | `ExplorerSearchStoreTests`, `ExplorerAdvancedSearchStoreTests` |
| [x] | search generation으로 취소 비협조 stale 결과/오류/loading 차단 | `ExplorerSearchStoreTests` |
| [x] | active pane 변경 시 기존 결과 제거 후 새 root 재검색 | `ExplorerSearchStoreTests` |
| [x] | recursive search symlink entry는 매칭하되 내부 비진입 | `FileSearchServiceTests` |
| [x] | root 권한 오류 throw, descendant 권한 오류 skip | `FileSearchServiceTests` |
| [x] | unreadable directory 비진입과 cancellation 전파 | `FileSearchServiceTests` |
| [x] | Finder Tags 읽기, 표시, 편집, 삭제 | `FinderTagServiceTests`, `ExplorerFinderTagCommandTests` |
| [x] | Tag 편집 후 필터 결과와 selection 즉시 정리 | `ExplorerAdvancedSearchStoreTests` |
| [ ] | Spotlight index/content 검색 | 현재 검색은 파일 목록/재귀 열거와 Finder Tag 기반이며 Spotlight API는 연결하지 않음 |

## 7. Sidebar, Favorites, Recent, Volumes

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | Home/Desktop/Documents/Downloads/Applications 전체 행 클릭 | `ExplorerSidebarStoreTests`, 실제 Sidebar 이동 확인 |
| [x] | 현재 폴더 또는 선택 폴더 Favorite 추가 | 실제 UUID 폴더 추가, `ExplorerSidebarStoreTests` |
| [x] | Favorite 삭제와 위/아래 재정렬 | 실제 임시 Favorite 삭제, `SidebarFavoritesStoreTests` |
| [x] | 중복 Favorite 방지와 영속화 | `SidebarFavoritesStoreTests` |
| [x] | 없는 Favorite 클릭 시 자동 제거 | `ExplorerSidebarStoreTests` |
| [x] | Recent Folder 기록, 중복 제거, 최대 개수 제한 | `ExplorerSidebarStoreTests` |
| [x] | 없는 Recent 클릭 시 자동 제거 | `ExplorerSidebarStoreTests` |
| [x] | mounted volume 정렬과 새로고침 | `ExplorerVolumeStoreTests`, `MountedVolumeTests` |
| [x] | 사라진 volume 제거와 unreadable volume 오류 | `ExplorerVolumeStoreTests` |
| [~] | 외장/네트워크 mounted volume 실제 탐색 | 서비스와 테스트는 있음; 이번 Mac에는 별도 네트워크 볼륨을 연결하지 않음 |
| [ ] | SMB/NFS 서버를 앱에서 새로 연결하는 UI | 미구현; macOS에 이미 mount된 volume만 표시 |

## 8. 새 폴더와 Rename

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | `Cmd+Shift+N` 새 폴더 생성 | 실제 UUID 폴더에서 생성 확인 |
| [x] | 새 폴더 생성 직후 즉시 inline rename | 실제 `Untitled Folder` 편집, Return commit 확인 |
| [x] | 기존 파일/폴더 `F2` inline rename | 실제 파일 rename, `PathInputFieldTests`, `FileTableViewReuseTests` |
| [x] | context menu Rename | 메뉴 노출 및 command routing 테스트 |
| [x] | Return commit / Escape cancel | 실제 두 흐름과 `FileTableViewReuseTests` |
| [x] | path input과 rename의 shared field editor 격리 | `PathInputFieldTests` |
| [x] | 이름의 path separator 검증 | `FileOperationServiceTests` |
| [x] | case-insensitive volume case-only rename | `FileOperationServiceTests` |
| [x] | case-only rename 실패 cleanup이 원본을 삭제하지 않음 | `FileDropValidatorTests`, `FileOperationServiceTests` |
| [x] | rename Undo와 새 폴더 생성/rename Undo 순서 | 실제 두 번 Undo, `ExplorerUndoCommandTests` |

## 9. Copy, Move, Delete, Drag & Drop

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | Copy / Cut / Paste responder-chain routing | `FileClipboardTests`, `FileTableViewReuseTests`, `ExplorerShortcutRoutingTests` |
| [x] | 경로/search 입력창 focus 중 Cmd+A/C/V가 파일 명령으로 새지 않음 | `PathInputFieldTests`, `ExplorerShortcutRoutingTests` |
| [x] | Duplicate | `FileOperationServiceTests`, `ExplorerCommandTests` |
| [x] | 같은 폴더 copy 시 Keep Both 이름 생성 | `FileOperationServiceTests` |
| [x] | 파일/폴더 Move | `FileOperationServiceTests`, F6 routing 테스트 |
| [~] | Move to Trash | simulated Trash 기반 `FileOperationServiceTests`; 이번 실제 UI에서는 사용자 Trash를 변경하지 않음 |
| [x] | 여러 항목 Trash 중 취소/오류 시 역순 rollback | simulated Trash 기반 `FileOperationServiceTests` |
| [x] | Trash rollback 실패를 명시적 오류로 노출 | `FileOperationServiceTests` |
| [x] | Drag pasteboard 읽기와 copy/move 판정 | `FileDropPasteboardReaderTests`, `ExplorerStoreDropTests` |
| [~] | 실제 마우스 drag & drop | validator/store/UI 연결 테스트는 있음; 이번 Computer Use에서는 파일 drag를 실행하지 않음 |
| [x] | source를 자기 자신/하위 destination으로 copy/move/drop 차단 | `FileOperationServiceTests`, `FileDropValidatorTests` |
| [x] | destination parent symlink 우회 차단 | `FileOperationServiceTests`, `FileDropValidatorTests` |
| [x] | source leaf symlink 정상 copy/move 허용 | `FileOperationServiceTests`, `FileDropValidatorTests` |
| [x] | alias를 통한 same-folder copy도 Keep Both 처리 | `FileOperationServiceTests` |
| [x] | 항목별 metadata 실패가 전체 directory listing 실패로 번지지 않음 | `FileSystemServiceTests` |

## 10. 충돌, 진행률, 취소, Undo

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | Replace / Keep Both / Skip / Cancel 충돌 UI와 결정 모델 | `AppKitFileConflictResolverTests`, `FileConflictModelTests` |
| [x] | 일반 copy byte manifest 진행률 | `FileOperationManifestBuilderTests`, `FileOperationProgressReporterTests` |
| [x] | 대용량 단일 파일 streaming 중간 진행률과 취소 | `FileOperationServiceTests` |
| [x] | 완료 배너는 성공 완료 뒤 1초 후 자동 사라짐 | `OperationProgressBannerTests`, 실제 F5 완료 배너 확인 |
| [x] | 진행 중/실패 상태는 성공처럼 자동 dismiss하지 않음 | `OperationProgressBannerTests` |
| [x] | copy staging 완료 후 tree snapshot 검증과 publish | `FileOperationServiceTests`, `FileSystemTreeSnapshotTests` |
| [x] | rollback quarantine, filesystem identity/tree 재검증 | `FileOperationServiceTests`, `FileSystemTreeSnapshotTests` |
| [x] | create/copy/move/rename/trash/ZIP 결과 Undo | 관련 Store/Service 테스트와 일부 실제 UI Undo 확인 |
| [x] | compound Undo 전체 preflight와 simulated state | `ExplorerUndoCommandTests` |
| [x] | compound Undo 중간 실패/취소 시 역순 rollback | `ExplorerUndoCommandTests` |
| [x] | rollback-incomplete 상태를 숨기지 않음 | `ExplorerUndoCommandTests` |
| [x] | Undo 실패 시 원래 action을 stack에 복원 | `ExplorerUndoCommandTests` |
| [ ] | Redo | Undo만 구현되어 있으며 Redo stack/UI는 없음 |

## 11. ZIP 탐색과 압축

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | ZIP double-click 내부 탐색 | 수정된 release 앱에서 `sample.zip` 실제 탐색 확인 |
| [x] | ZIP 내부 폴더 Back/Up/경로 표시 | 실제 앱과 `ExplorerArchiveNavigationTests` |
| [x] | ZIP host 파일 외부 변경 watcher refresh | `ExplorerStoreWatcherTests` |
| [x] | 선택 항목 ZIP 압축 | `ZipCompressionServiceTests`, `ExplorerZipCompressionCommandTests` |
| [x] | ZIP 압축 해제 | `ZipExtractionServiceTests`, `ExplorerZipExtractionCommandTests` |
| [x] | unsafe archive path 차단 | `ZipExtractionServiceTests`, `ArchiveBrowsingServiceTests` |
| [x] | 압축 해제 staging/부분 실패 cleanup | `ZipExtractionServiceTests` |
| [x] | archive-backed 항목의 rename/delete/tag/drag 차단 | `ExplorerArchiveCommandTests`, `FileTableViewReuseTests` |
| [x] | ZIP 내부 파일 Quick Look 임시 추출 | `ArchiveBrowsingServiceTests`, Inspector wiring 테스트 |
| [ ] | Quick Look 임시 ZIP 추출물 lifecycle cleanup | UUID 임시 경로를 생성하지만 소비 완료/앱 종료 기반 정리 정책이 없음 |
| [ ] | ZIP 내부 직접 쓰기/수정 | 내부 항목은 read-only 가상 항목; 외부로 압축 해제 후 수정해야 함 |

## 12. Inspector와 Preview

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | 단일 선택 metadata와 다중 선택 요약 | 실제 Markdown/폴더/4개 선택, `InspectorModelsTests` |
| [x] | Copy Path | `ExplorerInspectorCommandTests`, Inspector UI 확인 |
| [x] | Open / Quick Look / Reveal | `InspectorViewWiringTests`, 실제 버튼 노출 확인 |
| [x] | 폴더 크기 백그라운드 계산 | `FolderSizeServiceTests`, `ExplorerInspectorCommandTests` |
| [x] | 텍스트/code/JSON/Markdown/log/csv inline preview | 실제 `preview.md`, `FilePreviewContentLoaderTests` |
| [x] | byte limit까지만 읽고 truncation 표시 | `FilePreviewContentLoaderTests` |
| [x] | selection debounce, stale preview 취소 | `FilePreviewContentLoaderTests`, `FilePreviewThumbnailLoaderTests` |
| [x] | 큰 visual file thumbnail skip 정책 | `FilePreviewPolicyTests` |
| [x] | binary/read error fallback | 실제 2.1MB binary fixture fallback, loader/policy 테스트 |
| [~] | 실제 Quick Look 창에서 이미지/PDF/영상 확인 | 서비스/wiring 테스트는 있음; 이번 audit에서는 외부 Quick Look 창을 띄우지 않음 |

## 13. Context Menu, 키보드, 외부 앱

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | 파일/폴더 context menu | 실제 Open, Open With, Rename, Tags, Duplicate, Compress, Copy/Cut/Paste, Copy Path, Delete, Reveal, Refresh 확인 |
| [x] | 빈 영역/행 오른쪽 여백 context menu | 실제 Undo, New Folder, Open in Terminal, Paste, Refresh 확인 |
| [x] | 파일 메뉴 Delete 노출 | 실제 메뉴와 `FileTableViewReuseTests` |
| [x] | Open With default/recommended/choose app routing | 실제 submenu 노출, `FileTableViewReuseTests`, `ExternalAppLauncherTests` |
| [x] | 폴더 Open in Terminal / Open in VS Code | 실제 메뉴 노출, `ExternalAppLauncherTests` |
| [x] | 경로 명령 `cmd`, `terminal`, `code .`, `open .` | `PathInputCommandResolverTests`, `ExplorerStorePathInputCommandTests` |
| [x] | Terminal fire-and-forget 후 MyMacFinder 유지 | `ExternalAppLauncherTests`, 이전 실제 회귀 QA 기록 |
| [x] | VS Code bundle lookup 후 user shell `code` fallback | `ExternalAppLauncherTests` |
| [x] | F2, Cmd+Shift+N, Cmd+C/X/V, Cmd+Z, Return 등 단축키 routing | `ExplorerKeyboardShortcutTests`, `ExplorerShortcutRoutingTests`, 실제 주요 흐름 확인 |
| [~] | 설치된 모든 추천 앱 조합의 Open With 실행 | LaunchServices 결과는 환경 의존; 이번 audit에서는 메뉴와 routing까지만 확인 |

## 14. 외부 변경 동기화와 비동기 안정성

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | 외부 파일 생성 시 active pane 자동 반영 | 실제 UUID fixture에 shell로 파일 생성 후 즉시 표시 확인 |
| [x] | 외부 파일 삭제 시 active pane 자동 반영 | 같은 정확한 fixture 파일만 unlink 후 즉시 제거 확인 |
| [x] | dual pane의 같은/다른 visible directory watcher 갱신 | `ExplorerStoreWatcherTests` |
| [x] | 느린 pane read의 stale completion 차단 | `ExplorerPaneLoadRaceTests` |
| [x] | 느린 recursive search의 stale completion 차단 | `ExplorerSearchStoreTests` |
| [x] | Finder Tag population stale context 차단 | `ExplorerSearchStoreTests`, `ExplorerAdvancedSearchStoreTests` |
| [x] | folder size와 preview의 메인 스레드 I/O 회피 | `FolderSizeServiceTests`, preview loader 테스트 |

## 15. 권한, Bookmark, Sandbox

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | permission denied 오류 분류와 recovery guidance | `PermissionGuidanceTests`, `ExplorerPermissionRecoveryTests` |
| [x] | 선택 폴더 grant 저장, remove, reset UI | `SecurityScopedBookmarkStoreTests`, `PrivacyAccessSettingsViewTests`, 실제 UI 확인 |
| [x] | stale bookmark data 재생성과 resolved URL 반영 | `UserSelectedFolderAccessService`, `ExplorerStore` 소스 연결 확인 |
| [~] | sandboxed 앱의 실제 security-scoped access | 자동 resolver/store 테스트는 있음; 개인 release는 unrestricted라 실제 sandbox grant는 미실행 |
| [x] | 손상된 bookmark JSON 보존/오류 표시 | decode 실패를 명시적 오류로 반환하고 load/save/remove 모두 원본 bytes를 보존; 자동 테스트와 격리 release 실제 UI 확인 |
| [x] | stale bookmark refresh 실패 시 access lifecycle 정리 | refresh 실패 시 실제 시작된 access만 즉시 stop; 성공/실패/미시작 분기 `UserSelectedFolderAccessServiceTests` |
| [x] | refreshed bookmark 저장 실패 표시 | 갱신 저장 실패 시 access 정리, unavailable 표시, alert와 Settings 경고/Reset 제공; `ExplorerPermissionRecoveryTests`, `PrivacyAccessSettingsViewTests` |

## 16. 빌드, 테스트, 패키징, 배포

| 상태 | 세부 기능 | 이번 점검 근거 |
|---|---|---|
| [x] | Xcode 16.4 / xctest toolchain 확인 | `xcode-select`, `xcodebuild -version`, `xcrun --find xctest` |
| [x] | Swift warnings-as-errors build | `swift build -Xswiftc -warnings-as-errors` |
| [x] | 전체 XCTest + coverage | 최종 검증에서 508 tests / 0 failures |
| [x] | release `.app` 생성 | `./scripts/build_app.sh --configuration release` |
| [x] | strict code signature 검증 | `codesign --verify --deep --strict --verbose=2` |
| [x] | 앱 아이콘 검증 | `./scripts/verify-app-icon.sh` |
| [x] | 개인 설치 ZIP 생성/무결성 | `./scripts/package_personal.sh`, `dist/MyMacFinder-personal-mac.zip` |
| [x] | 루트 GitHub Actions workflow | `.github/workflows/ci.yml`에 build/test/icon/app bundle job 존재 |
| [x] | `/Applications/MyMacFinder.app` 안전 설치/교체 | release와 staging 서명/실행 파일 해시를 확인하고 기존 설치본을 복구 가능한 백업으로 옮긴 뒤 원자적으로 교체; 설치본 실행 경로와 PID 확인 |
| [ ] | Developer ID 서명, notarization, entitlement 기반 공개 배포 | 미구성; 현재 개인용 ad-hoc 패키지 |
| [ ] | 자동 업데이트 | 미구현 |

## 이번 점검에서 발견하고 수정한 문제

### AUDIT-001: 탐색 후 첫 행이 헤더 뒤에 가려짐

- 재현: Home/Recent/ZIP 등 새 location 로드 뒤 접근성 트리에는 첫 행이 있지만 화면은 두 번째 행부터 표시됨.
- 영향: 첫 파일/폴더가 없는 것처럼 보이고, 그 위치를 클릭하면 두 번째 행이 선택됨.
- 원인: AppKit scroll view의 올바른 시작 Y가 음수일 수 있는데 `contentView.scroll(to: .zero)`로 강제했다. 테스트 환경에서도 AppKit의 문서 시작점은 `y = -28`로 확인됐다.
- 수정: table reload 후 `NSTableView.scrollToBeginningOfDocument`를 사용하고 그 결과 Y를 보존한 채 X만 0으로 초기화한다.
- 회귀 테스트: AppKit이 계산한 실제 시작 좌표와 reset 결과 비교, 빈 목록 reset, 같은 location metadata reload의 scroll 보존, 실제 `RootView` navigation 뒤 첫 행과 header 비겹침. 기존 `.zero` 구현에서는 시작 좌표 비교 테스트가 `0` 대 `-28`로 실패하는 것도 확인했다.
- 실제 확인: 수정된 release QA 앱에서 일반 폴더와 ZIP root 모두 첫 행이 즉시 표시됐다. 최종 소스로 다시 만든 별도 release 앱에서도 31개 행을 아래까지 스크롤한 뒤 빈 폴더로 이동하고 Back으로 돌아왔을 때 빈 목록은 crash 없이 표시되고 원래 폴더는 첫 행부터 복원되는 것을 확인했다.

### AUDIT-002: 손상·stale security-scoped bookmark의 데이터 및 access lifecycle

- 재현: 저장된 bookmark JSON을 손상시키면 기존 구현은 빈 grant 목록으로 간주했고, 다음 save/remove가 손상 원본을 새 배열로 덮어썼다. stale bookmark 재생성이 access 시작 뒤 실패하면 stop 호출 기회가 없었고, 갱신 데이터 저장 실패는 `try?`로 숨겨졌다.
- 영향: 사용자가 저장한 폴더 권한 정보 손실, security-scoped access 누수, UI와 실제 영속 상태 불일치가 가능했다.
- 수정: bookmark store의 load/remove를 throwing 계약으로 바꾸고 decode 실패 시 원본 bytes를 유지한다. resolver는 stale refresh 실패 시 시작에 성공한 access만 종료한다. ExplorerStore는 save/remove 성공 뒤에만 active 상태를 commit하고 실패 시 기존 grant를 유지하며, 경고와 명시적 Reset을 제공한다.
- 회귀 테스트: 손상 원본 보존, load/save/remove 오류, stale refresh 성공/실패/미시작, 시작 시 갱신 저장 실패, 새 grant 저장 실패, grant 삭제 실패, Reset 복구를 검증했다.
- 실제 확인: 별도 QA bundle ID의 UserDefaults에 손상된 9-byte 데이터를 주입했다. release 앱은 crash 없이 경고를 표시했고 Settings > Privacy & Access에 복구 안내와 Reset이 노출됐다. 앱 시작과 설정 진입 뒤에도 원본 bytes가 유지됐고, 명시적으로 Reset을 누른 뒤에만 키와 경고가 제거됐다. QA 앱, 설정 domain, 임시 bundle은 모두 정리했다.

## 후속 상태와 남은 위험 우선순위

Quick Look용 ZIP 임시 추출물의 소비 완료/앱 종료 cleanup 부재는 2026-08-08 구현과 검증에서 해소됐다. session-owned artifact, durable retry, 외부 앱 open retention, startup expiry cleanup의 최신 근거는 `docs/qa/2026-08-08-archive-preview-lifecycle-verification.md`를 따른다.

1. **검증 공백**: 실제 다중 항목 Trash 취소 rollback, 실제 network volume, sandbox grant, 마우스 drag/drop은 자동 또는 simulated 검증만 수행했다.
2. **제품 범위**: Redo, Spotlight 검색, Group By UI, SMB/NFS 연결 UI, ZIP 내부 직접 쓰기, 공개 배포 서명/공증은 아직 제공하지 않는다.

## 최종 검증 결과

최종 코드와 문서 수정 뒤 아래 항목을 새로 실행했다.

| 검증 | 결과 |
|---|---|
| `swift build -Xswiftc -warnings-as-errors` | 통과, compiler warning 없음 |
| `swift test --enable-code-coverage` | 통과, 508 tests / 0 failures |
| `FileTableViewReuseTests` 반복 | 3/3 통과 |
| `git diff --check` | 통과 |
| `./scripts/build_app.sh --configuration release` | 통과, `build/MyMacFinder.app` 생성 |
| strict codesign | 통과, on-disk valid 및 designated requirement 충족 |
| `./scripts/verify-app-icon.sh` | 통과 |
| `./scripts/package_personal.sh` 및 ZIP 무결성 | 통과, `dist/MyMacFinder-personal-mac.zip` 생성 및 `unzip -t` 오류 없음 |
| 격리 release 실제 UI smoke test | 통과; 주요 파일 탐색 흐름과 손상 bookmark 보존/명시적 Reset을 확인한 뒤 QA 데이터, 설정 domain, 앱 bundle 전부 제거 |
| `/Applications` 안전 설치 | 통과; 설치본과 release 실행 파일 SHA-256 일치, strict codesign 통과, `/Applications/MyMacFinder.app/Contents/MacOS/MyMacFinder` 실행 확인 |

설치 전 앱은 정상 종료했고, 기존 설치본은 `MyMacFinder.backup-20260804-170129-6F82ED23.app` 이름으로 휴지통에 남겨 복구 가능하게 보존했다. `/Applications`에는 staging 또는 교체용 backup 잔여물이 없으며, 설치본과 `build/MyMacFinder.app` 실행 파일 SHA-256은 모두 `40bdac76a29ef4b8818fb1069ed8e952d4ec8c74ca03117acb42e66d39b2e7ec`다.
