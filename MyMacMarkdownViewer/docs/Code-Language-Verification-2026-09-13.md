# 코드 언어 표시와 클릭 위치 검증 — 2026-09-13

## 동작과 범위

- Mac·Windows: 코드 상자 오른쪽 위에서 언어를 선택한다. 언어 지정과 구문 색상이 함께 바뀌고, 실행 취소·다시 실행할 수 있다.
- Markdown의 코드 본문, 코드 기호, 들여쓰기와 부가 정보는 보존한다. 부가 정보가 있는 언어를 ‘텍스트’로 바꾸면 부가 정보가 언어로 잘못 해석되지 않도록 `text`를 기록한다.
- 언어가 없는 코드와 들여쓰기 코드는 ‘텍스트’로 표시한다. 인식하지 못한 기존 언어 이름은 유지한다. 들여쓰기 코드는 언어 정보가 없으므로 표시만 제공한다.
- Mermaid를 클릭해도 그림은 유지한다. 명시적 편집에서는 원문과 그림을 함께 표시한다.
- Android: 언어 이름만 표시하며 변경 기능은 제공하지 않는다. 본문 검색 대상에 UI 언어 이름을 포함하지 않는다.
- 내보내기에는 언어 선택 같은 편집 컨트롤을 추가하지 않는다.

## 위치 이동 원인과 검증 기준

이전 편집기에서는 코드 미리보기 앞에 있던 CodeMirror 빈 줄이 편집 상태에서 사라졌다. 17px 설정에서 코드 상자와 뒤 문단이 약 10.19px 위로 이동했지만 실제 scrollTop은 바뀌지 않았다. 코드 높이 비교만으로 이 문제를 찾지 못했다.

새 언어 헤더는 읽기·편집 양쪽에 같은 공간을 유지한다. 클릭 전후와 편집 종료 후의 코드 상자·뒤 문단 좌표, 글자 크기별 결과, scrollTop을 검증한다. 긴 코드가 편집 시 줄바꿈되는 경우의 아래쪽 높이 변화는 클릭 시 위쪽 위치 이동과 구분한다.

## 주요 파일

- `Editor/src/codeLanguage.ts`: 언어 정보의 정확한 토큰 범위와 표시 이름.
- `Editor/src/livePreview.ts`, `Editor/src/style.css`: 데스크톱 코드 헤더, 언어 변경, 읽기·편집 레이아웃.
- `Android/reader/reader.ts`, `Android/reader/reader.css`: 읽기 전용 언어 표시와 검색 제외.
- `Editor/tests/browser/code-language.spec.ts`, `Windows/tests/electron-code-language.mjs`, `Sources/App/AppQA.swift`, `Android/tests/reader-code-language.mjs`: 화면과 저장 경로 검증.

## 검증 경계

통합 검증 결과와 배포 파일 해시는 `code-language-release-verification.json`에 기록한다. Mac의 실제 WKWebView, macOS에서 실행한 Electron, WebKit·Chromium 브라우저 및 휴대폰 크기의 읽기 화면을 구분한다. Windows 실제 운영체제·Android 실기기·물리 키보드 IME 결과로 확대 해석하지 않는다.

이번 버전은 Mac 0.3.4 (10), Windows 0.3.5, Android 1.2.3 (9)이다. 로컬 빌드와 `/Applications` 설치, 메일 발송은 별도 상태다.

## 최종 결과

- 편집기 단위 테스트 20개, Windows 단위 테스트 22개 통과.
- 브라우저 전체 검사 재실행: WebKit 73개, Chromium 73개 통과.
- 실제 Mac: Universal Release 빌드·서명 검사, WKWebView 저장/실행 취소/다시 실행, UI 메뉴 클릭과 Space·방향키·Return 선택 통과. BOM·CRLF·코드 본문·부가 정보 보존 확인.
- Windows: macOS 호스트 Electron의 언어 변경·저장·실행 취소, 코드/다이어그램·가독성 흐름 통과. Windows ZIP의 x64 실행 파일·필수 런타임·ASAR 자산 검사 통과.
- Android: 언어 표시·읽기·검색·테마·이어 읽기·목차·가로 화면 검증 통과. APK 서명·기존 버전과 같은 서명·읽기 자산 122개 비교 통과.
- 공통 편집기 자산 235개가 Mac 앱과 Windows에 반영된 것을 확인했다.
- 검증 앱은 종료했다. 새 Mac 앱은 `/Applications`에 설치하지 않았으며 설치본은 0.3.3 (9)이다. 이번 새 배포 파일은 메일로 발송하지 않았다.
