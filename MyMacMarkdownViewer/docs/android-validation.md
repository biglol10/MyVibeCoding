# Android 개인 APK 검증 — 2026-09-10

- 산출물: `dist/android/MarkdownReader-1.0-Android.apk` (개인 서명 release, 3,732,105 bytes).
- SHA-256: `712af118e6a8f87ec24fa156af1f7bf19901ea794ede1ea92d362984b1886b8c`.
- APK v2/v3 서명 검증 통과, 디버깅 비활성화 확인, 현재 리더 빌드 자원 전체와 APK 내부 파일 일치. 오픈소스 고지 포함.
- Android Gradle debug/release 빌드 통과. `lintDebug`: 오류 0, 경고 8. 경고는 고정된 SDK·의존성 버전, 필요한 WebView JavaScript, 백업 설정 및 파일 연결 관련 권고로 검토함.
- `node Android/tests/reader-browser.mjs`: Chromium 휴대폰 393×852 / 태블릿 1024×768에서 13개 검증 항목 통과. 원문 편집 요소 없음, 체크박스 표시 전용, HTML 실행 차단, 표·코드·수식·Mermaid, 목차, 검색, 테마, 원격 이미지 승인 범위, 화면 폭, 렌더러 오류 확인.
- `node Android/tests/native-reader.mjs`: Android 15/API 35 arm64 전용 에뮬레이터 `emulator-5580`의 debug 앱에서 9개 검증 항목 통과. 시스템 폴더 선택, UTF-8 BOM 및 한글, 로컬 이미지, Mermaid, 복원된 폴더·중첩 탐색, 본문 검색, 원격 이미지 확인창 취소, 나이트 화면, 원본 fixture 전체 해시 일치.
- 최종 개인 서명 release APK도 같은 전용 에뮬레이터에 새로 설치하여 첫 실행 → 시스템 폴더 선택 → 문서 읽기 확인. Android의 Markdown 파일 열기 연결 대상에 이 앱이 표시되는 것도 확인.
- 실제 Android 화면에서 시스템 바 겹침과 긴 표·다이어그램이 전체 화면 폭을 늘리던 현상을 수정하고 재확인. 휴대폰과 태블릿 화면의 여백·줄 간격·탐색 동선 검토.
- 사용자 실기기에는 설치하지 않음. Android 8~14/16, 제조사별 파일 앱, 실제 외부 HTTPS 이미지 서버 요청, 실기기 성능은 미검증. 인터넷 이미지 기본 차단·승인/취소 범위는 검증.
- 문서 UTF-8 8 MiB, 이미지 20 MiB, 폴더 표시 1,000항목 제한. OS가 Download 루트 선택을 제한할 때 하위 폴더 사용. 파일 하나로 열면 인접 이미지 권한이 없어 폴더 선택 필요.
- 소스: `Android/app/src/main/java/com/personal/markdownreader/MainActivity.java`, `Android/reader`, `Android/scripts`. Mac/Windows 제품 코드는 이번 Android 작업에서 수정하지 않음.
