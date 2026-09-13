# MyMarkdownViewer Windows

Windows 11 Intel·AMD x64용 개인 사용 버전입니다. [최신 0.3.7 포터블 ZIP 다운로드](https://github.com/biglol10/MyVibeCoding/releases/download/mymarkdownviewer-2026-09-14/MyMarkdownViewer-0.3.7-Windows-x64.zip) 후 전체 압축을 풀고 `MyMarkdownViewer.exe`를 실행합니다. 런타임과 편집기 리소스가 포함되므로 별도 Node.js나 WebView 설치가 필요 없습니다. EXE만 분리하지 마세요.

## 구현 범위

macOS 앱과 동일한 CodeMirror 편집기를 사용합니다. 라이브 편집과 원문 전환, 문서 저장·다른 이름으로 저장, 자동 저장·임시본 복구, 목차, 문서 검색, 사이드바 파일 관리, 폴더 본문 검색과 검토 후 선택 바꾸기, 테마·글자·줄 간격·읽기 폭 설정을 제공합니다. 설정과 복구본은 실행 폴더가 아닌 사용자 AppData 앱 폴더에 저장합니다.

- `main.mjs`: 네이티브 창·메뉴·파일 선택·휴지통, 문서 세션과 충돌 감지, 접근 허용 경로, IPC
- `core.mjs`: UTF-8/BOM/줄바꿈 보존, UTF-16 변경, 원본 해시 검증, 파일 작업·검색·복구
- `preload.cjs`, `editor-bridge.js`: 격리된 화면과 편집기의 제한된 메시지 연결
- `ui/`: 한국어 Windows 도구 모음·사이드바·대화상자
- `../Editor/`: macOS와 공유하는 편집기 소스. Ctrl 클릭과 Windows 드라이브·공유 경로 링크 보존을 추가했습니다.

## 로컬 개발·패키징

```sh
npm --prefix Editor ci
npm --prefix Editor run build
npm --prefix Windows ci
node Windows/node_modules/electron/install.js
npm --prefix Windows run prepare:editor
npm --prefix Windows test
npm --prefix Windows start
npm --prefix Windows run package:win
```

ZIP 생성에는 Python 3이 필요합니다. 이는 개발 환경에만 필요합니다. Windows 패키징은 Electron 44.3.0과 @electron/packager 20.3.0을 사용하며 macOS에서 수행할 수 있습니다. 패키지는 로컬에 생성되며 자동 업로드·배포·업데이트를 수행하지 않습니다.

## 검증과 경계

검증 결과는 `../docs/Windows-Verification.md`에 기록합니다. macOS에서 동일 Electron 앱의 실제 창·편집·파일 작업을 검증했으며, Windows x64 실행 파일과 ZIP 구조를 별도로 검사했습니다. **실제 Windows PC 실행, Windows 두벌식 조합, 실제 클라우드 동기화 폴더는 미검증입니다.** 자동 테스트는 물리 키보드 검증을 대체하지 않습니다.

서명 없는 개인 배포본으로 조직 정책이나 Windows 실행 보호 기능이 실행을 제한할 수 있습니다. Windows ARM64 전용 패키지와 설치 프로그램은 포함하지 않습니다. 이미지 파일·DOCX·EPUB 내보내기와 사용자 CSS 테마는 포함하지 않습니다.

Electron renderer의 Node 실행은 꺼져 있으며 sandbox와 contextIsolation을 사용합니다. IPC는 주 창의 정확한 origin과 frame을 검사합니다. 폴더 바꾸기는 미리보기 이후 경로·원본 해시를 다시 확인합니다. 파일별 백업은 남기지만 여러 파일 쓰기는 하나의 파일시스템 트랜잭션이 아닙니다. 저수준 동시 쓰기 경쟁을 완전히 제거하는 방식은 아닙니다.

## 0.1.2 변경

우클릭 위치의 항목 메뉴, 보기 메뉴의 시스템·어두움·나이트·밝음 테마, 찾아 바꾸기·인라인 코드·이미지 파일 선택·탐색기에서 보기를 제공합니다. `.md`와 `.markdown` 파일의 목록·검색·이름 변경·이동을 지원합니다. [최종 검증](../docs/Final-Review-2026-09-12.md)을 확인하세요.

## 0.2.0 변경

참조 링크·각주·본문 목차·문서 정보 표시, 표 셀·행·열·정렬 편집, HTML/PDF 내보내기·인쇄, 집중·타자기 모드를 추가했습니다. 파일 메뉴에서 내보내기, 보기 메뉴에서 글쓰기 모드(F8/F9), 서식 메뉴에서 새 문법을 찾을 수 있습니다. 인쇄 단축키는 Ctrl+Alt+P이며 Ctrl+P는 기존 빠른 파일 열기입니다. [구현 검증](../docs/Typora-Implementation-2026-09-12.md).

## 0.3.0 탐색 개선

목차 탭에서 제목 검색·접기/펼치기를 사용할 수 있습니다. 검색을 지우면 기존 접기 상태가 복원되고 다른 문서로 이동하면 초기화합니다. 빠른 파일 열기의 키보드·목록 갱신 동작도 보완했습니다. [구현·검증 기록](../docs/Outline-Navigation-Release-2026-09-12.md).

## 0.3.1 이어 읽기

일반 실행 시 마지막 문서·읽던 위치·열어 둔 폴더를 복원합니다. 파일을 지정해 실행하면 지정한 파일을 우선합니다. 파일이 없으면 안내하며 폴더는 독립적으로 복원합니다. 편집기 시작 신호를 놓치지 않도록 화면 초기화 순서도 수정했습니다.

## 0.3.4 가독성 개선

읽기·클릭·편집 상태에서 코드 글자 크기와 줄 높이를 맞추고, Night 테마의 활성 링크 주소와 코드 구문 색상 대비를 보완했습니다. 빈 코드 줄도 클릭 상태에서 높이를 유지합니다. [가독성 검토](../docs/Readability-Review-2026-09-13.md)와 Windows 패키지 검증 기록을 확인하세요.

## 0.3.5 코드 언어 표시

코드 상자 오른쪽 위의 언어 표시를 눌러 언어와 구문 색상을 바꿀 수 있습니다. 코드 본문과 부가 정보는 보존되며 실행 취소할 수 있습니다. 클릭 시 코드 상자가 위로 이동하던 간격 변화도 수정했습니다. [검증 범위](../docs/Code-Language-Verification-2026-09-13.md)를 확인하세요.

## 0.3.6 코드 커서 위치 수정

커서가 코드 앞·본문·끝 줄로 이동해도 언어 헤더가 상자 테두리와 겹치거나 안쪽 여백이 사라지지 않습니다. 시작·끝 표시 줄의 키보드 이동과 빈 코드 블록을 함께 보완했습니다. [검증 범위](../docs/Code-Cursor-Layout-Verification-2026-09-13.md)를 확인하세요.

## 0.3.7 현재 문서 찾기

파일 탭 상단의 과녁 모양 **현재 문서 찾기** 버튼으로 상위 폴더를 펼치고 현재 문서를 선택해 목록에 표시합니다. 본문 위치·선택 범위·미저장 내용을 유지하며 예약된 자동 저장을 방해하지 않습니다.
