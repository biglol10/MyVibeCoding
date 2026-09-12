# Windows parity audit (2026-09-12)

> 아래 내용은 0.1.1 시점의 감사 기록이다. 후속 0.1.2 최종 리뷰 결과와 세 플랫폼 배포 검증은 [Final-Review-2026-09-12.md](Final-Review-2026-09-12.md)를 기준으로 확인한다.

## 범위와 판정 기준

Mac 구현(`Sources/App`)과 Windows 구현(`Windows`, 공통 편집기 `Editor/src`)을 코드로 대조했다. 기능 대조는 코드 기준이며, 아래 0.1.1 수정 결과에 macOS Electron 실행 및 패키지 검증 결과를 별도로 기록했다. 실제 Windows PC와 Windows 한글 IME는 검증하지 않았다. 상태는 다음처럼 구분한다.

- **구현됨**: Windows 코드에 기능과 호출 경로가 있다.
- **메뉴 누락**: 공통 편집기 또는 Main 액션은 있지만 Windows 메뉴에서 접근할 항목이 없다.
- **신규 미구현**: Mac 기능에 대응하는 Windows 구현 경로를 찾지 못했다.
- **OS 차이**: 기능은 있으나 Windows와 macOS의 시스템 동작 차이로 별도 표현이 필요하다.
- **부분**: 기능의 일부 경로만 있거나 접근성이 제한된다.

## 확인된 우클릭 버그

수정 전 0.1.0 트리 항목의 `contextmenu` 핸들러는 기본 브라우저 메뉴를 막고 선택 경로만 갱신한 뒤 공통 `.folder-menu`를 열었다. 당시 우클릭 이벤트의 `clientX`, `clientY`는 사용하지 않았다. [Windows/ui/shell.mjs의 `renderTree()` contextmenu 핸들러](../Windows/ui/shell.mjs) 참조.

공통 팝업은 절대 위치이고, 파일 관리 팝업은 `right: 0`으로 상단 도구 버튼에 붙는다. 따라서 항목 메뉴가 우클릭 지점이 아니라 상단 메뉴 위치에 나타난 것이 수정 전 코드와 일치한다.

수정 전 디자인 테스트는 우클릭 뒤 `.folder-menu`가 열렸는지만 검사했으며, 클릭 좌표와 팝업 위치를 비교하지 않았다. [Windows/tests/electron-design.mjs](../Windows/tests/electron-design.mjs)의 해당 검사는 수정 전 기준의 한계를 보여 준다.

## 수정 전 테마 경로와 차이

Windows 설정 UI는 `dark`, `night`, `light` 세 값을 노출한다. Shell은 `state.settings.theme`를 `document.documentElement.dataset.theme`에 적용하고, Main은 설정을 저장한 뒤 공통 편집기로 전달한다. 공통 편집기는 `data-theme`, 글자 크기, 줄 간격, 본문 폭, 글꼴 및 CodeMirror 밝기를 갱신한다.

근거 함수/경로:

- `Windows/ui/shell.mjs`: `renderHeader()`, `settingsDialog()`, `saveSettings()`
- `Windows/main.mjs`: `doAction()`의 `settings` case, `openEditor()`
- `Editor/src/main.ts`: `applySettings()`, `host.receive()`
- `Windows/ui/shell.css`: `data-theme=light`, `data-theme=night`

Mac은 `ThemeChoice.system`을 지원하고 시스템 appearance 변경도 반영한다. Windows UI와 Main 설정 검증은 세 가지 명시적 테마만 처리한다. 수정 전에는 기존 설정 파일에 `system`이 들어오면 Windows Shell에는 `data-theme="system"`이 설정되지만 해당 CSS 선택자가 없어 테마가 기대와 다르게 보일 가능성이 있다. 새 Windows 기본값은 `dark`이므로 모든 설치에서 재현된다고 단정하지 않는다.

또한 수정 전 Windows 상단 HTML 보기 메뉴에는 설정이 없고 하단 설정 버튼과 Native 보기 메뉴에만 설정이 있다. 사용자가 테마를 찾기 어려운 원인이 될 수 있다.

## Mac-Windows 기능 대조

| 기능 | 판정 | 근거 및 비고 |
|---|---|---|
| 새 문서, 문서 열기, 폴더 열기 | 구현됨 | Windows HTML 파일 메뉴와 `doAction()`에 경로가 있다. |
| 저장, 다른 이름으로 저장 | 구현됨 | Windows `doAction()`의 `save`, `saveAs`. |
| 복구 목록, 복구, 복구본 삭제 | 구현됨 | Native `recoveries`가 Shell `showRecoveries()`로 dispatch되고, 복구 UI에 복구/삭제가 있다. 닫기와는 별도 기능이다. |
| 닫기 | OS 차이/부분 | Mac은 명시적 `닫기` Cmd+W를 제공한다. Windows Native 메뉴는 `quit` 역할을 제공하며 창 닫기 이벤트에는 저장 흐름이 있다. |
| 실행 취소, 다시 실행, 문서 찾기 | 구현됨 | Native 메뉴와 공통 Editor command 경로가 있다. |
| 폴더 전체 검색 | 구현됨 | Windows `search`와 `folderSearch` 경로가 있다. |
| 찾아 바꾸기 | 메뉴 누락 | 공통 Editor에는 `replace` command가 있으나 Windows HTML/Native 메뉴에는 항목이 없다. |
| 굵게, 기울임, 링크, 제목, 목록, 할 일, 인용, 코드 블록 | 구현됨 | 공통 Editor command 및 Windows 메뉴가 있다. |
| 인라인 코드 | 메뉴 누락 | 공통 Editor의 `code` command는 있으나 Windows 메뉴에는 없다. |
| 이미지 삽입 | 파일 선택 삽입 신규 미구현 | 공통 Editor의 이미지 붙여넣기/드롭 및 Main `insertImageData`는 있으나 Mac의 `이미지 삽입…`에 대응하는 Windows 파일 선택 dialog 액션과 메뉴가 없다. |
| 빠른 파일 열기 | 구현됨 | Shell dialog 및 Native accelerator가 있다. |
| 사이드바, 목차, 파일, 원문 모드 | 구현됨 | Shell 탭/보기 메뉴와 Editor `source` 경로가 있다. |
| 파일/폴더 생성, 이름 변경, 이동, 휴지통 | 구현됨 | Main 액션과 파일 관리 팝업이 있고, 0.1.1에서는 우클릭 전용 메뉴에서 파일/폴더 대상을 고정한다. |
| Finder에서 보기 | 신규 미구현 | Mac context menu에는 있으나 Windows 메뉴/액션에서 대응 경로를 찾지 못했다. Windows에서는 탐색기 열기 구현이 별도 필요하다. |
| 테마 | 부분 | 0.1.1에서 보기 메뉴에 dark/night/light와 읽기 설정을 노출하고 저장·재실행을 연결했다. `system` 테마 차이는 남아 있다. |

Native dispatch는 다음을 확인했다. `command:search`는 Shell에서 `find`로 변환되고, `recoveries`는 `showRecoveries()`로 처리된다. `replace`는 Editor에만 존재하며 메뉴 dispatch가 없다. Ctrl 단축키는 일부 Shell keydown 처리와 Electron Native accelerator가 함께 있으므로 전체 누락으로 판정하지 않는다.

## 0.1.1 현재 수정 결과

우클릭 메뉴는 전용 `item-context-menu`로 분리되어 클릭 좌표에 표시되고 파일/폴더별 항목을 구분한다. 대상 경로를 메뉴에 고정하며 Escape, Shift+F10/ContextMenu 키, 방향키, 스크롤, 창 크기 변경, iframe 포커스 이탈 시 닫힘을 처리한다. 상단에는 Mac 구성에 맞춘 아이콘 toolbar가 추가되었다.

보기 메뉴에는 세 가지 테마와 읽기 설정이 노출된다. 설정은 저장 후 재실행에도 유지되며 유효하지 않은 테마 값은 dark로 정규화된다. 따라서 수정 전의 상단 위치 우클릭 버그 판정은 0.1.1에서 수정됨으로 갱신한다. `system` 테마의 OS 차이는 여전히 남은 항목이다.

루트에서 재실행한 검증은 Windows core 13개, 최종 app.asar context 7개, design 8개, smoke 17개, Electron UI 9개가 모두 통과했다. 실행 환경은 실제 Windows가 아닌 macOS arm64 Electron 44.3.0이다.

## 테스트와 패키지 검증 한계

`Windows/package.json`의 `npm test`는 `tests/*.test.mjs`만 실행한다. Electron UI 테스트는 별도 실행 대상이다. 현재 Electron UI 스크립트는 macOS 경로인 `Electron.app/Contents/MacOS/Electron`을 사용하므로 실제 Windows 실행 증거가 아니다.

수정 전 UI 테스트는 테마 세 가지, 메뉴 키보드 조작, 일부 파일 흐름을 검사했지만 우클릭 좌표를 검사하지 않았고 `system` 테마도 검사하지 않았다. 실제 Windows 검증은 Windows 호스트에서 플랫폼에 맞는 Electron 실행 파일 또는 패키지 EXE를 사용해 UI 테스트와 실제 창/입력 동작을 실행해야 한다.

`Windows/scripts/verify-package.mjs`는 패키징된 산출물의 ASAR 원본 대조, ZIP 무결성, 필수 런타임 파일, PE x64 헤더, 개발 파일 제외를 검사한다. 이 스크립트는 버전을 `Windows/package.json`에서 읽고 날짜를 실행 시 생성한다. 패키지 검증은 실제 Windows 실행이나 IME 검증을 의미하지 않으며, 실행하지 않은 테스트 개수를 결과에 기록하지 않는다.

## 최소 후속 범위

0.1.1의 우클릭 수정은 클릭 좌표, 파일/폴더별 항목, 대상 고정 및 키보드·포커스·레이아웃 경로 검증을 통과했다.

현재 남은 parity 누락 항목은 `찾아 바꾸기` 메뉴, `인라인 코드` 메뉴, 파일 선택 방식의 이미지 삽입, Windows 탐색기에서 보기 메뉴, `system` 테마다. 이 감사에서는 해당 신규 앱 기능을 구현하지 않았다.

패키지 0.1.1은 [MyMarkdownViewer-0.1.1-Windows-x64.zip](../dist/windows/MyMarkdownViewer-0.1.1-Windows-x64.zip)이며 크기는 161003838 bytes, SHA-256은 `a3b99cbbcdbce54cc5f110afdca95035ae72597e32a38e4a006e1e566e8226b9`이다. 패키지 검증 결과는 [windows-verification-results.json](windows-verification-results.json)에 기록되어 있다. Mac/Android 소스 변경과 실제 Windows 및 Windows 한글 IME 검증은 포함하지 않는다.
