# MyMarkdownViewer Windows

Windows 11 Intel·AMD x64용 개인 사용 버전입니다. `dist/windows/MyMarkdownViewer-0.1.0-Windows-x64.zip` 전체를 압축 해제하고 `MyMarkdownViewer.exe`를 실행합니다. 런타임과 편집기 리소스가 포함되므로 별도 Node.js나 WebView 설치가 필요 없습니다. EXE만 분리하지 마세요.

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

서명 없는 개인 배포본으로 조직 정책이나 Windows 실행 보호 기능이 실행을 제한할 수 있습니다. Windows ARM64 전용 패키지와 설치 프로그램은 포함하지 않습니다. 표 셀 전용 편집·내보내기·집중 모드 등 향후 기능은 이 버전 범위에 포함하지 않습니다.

Electron renderer의 Node 실행은 꺼져 있으며 sandbox와 contextIsolation을 사용합니다. IPC는 주 창의 정확한 origin과 frame을 검사합니다. 폴더 바꾸기는 미리보기 이후 경로·원본 해시를 다시 확인합니다. 파일별 백업은 남기지만 여러 파일 쓰기는 하나의 파일시스템 트랜잭션이 아닙니다. 저수준 동시 쓰기 경쟁을 완전히 제거하는 방식은 아닙니다.
