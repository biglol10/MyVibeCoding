# 문서 기능 확장 구현 기록

2026-09-12. 사용자가 승인한 핵심 기능 범위이며 Typora 전체 기능 동등성을 뜻하지 않는다.

## 바뀐 동작

- Mac·Windows: 표의 읽기 화면에서 **표 편집**을 눌러 셀·행·열·정렬을 수정한다. 입력은 Enter·Tab·포커스 이동 또는 저장 스냅샷에서 반영되며 실행 취소할 수 있다. 빈 셀, 파이프 문자, 마지막 셀 Tab, 편집 중 구조 변경, 전환 잠금과 키보드 버튼 조작을 검증했다.
- 세 플랫폼: 참조 링크(축약형 포함), 각주와 역방향 이동, 본문 `[toc]`, front matter 표시를 지원한다. 코드 예제 속 문법을 그대로 보존하고, 중복 제목과 각주 정의 순서가 바뀐 경우도 구분한다. 여러 문단의 각주와 빈 줄 포함 수식을 함께 표시한다.
- Mac·Windows: 파일 메뉴에 HTML/PDF 내보내기와 인쇄, 보기 메뉴에 집중·타자기 모드, 서식 메뉴에 표·목차·각주·문서 정보·번호 목록·취소선·구분선·수식 삽입을 추가했다.
- HTML/PDF는 화면 밖 내용을 포함한 전체 원문에서 만든다. 로컬 이미지·수식 글꼴을 포함하고 Mermaid를 SVG로 만든다. 외부 이미지는 자동 다운로드하지 않는다. 원본 문서와 다른 출력 파일을 사용하고 취소·실패 시 원본을 보존한다.
- Mac 파일 열기에서 폴더 감시 초기화가 화면을 멈추는 문제도 발견했다. 감시 생성·종료와 늦은 콜백의 정리를 화면 스레드와 분리하는 수정 후 실제 폴더·문서 열기를 다시 통과했다.
- Android는 읽기 전용을 유지한다. 편집·저장·내보내기를 추가하지 않았다.

주요 파일: `Editor/src/{livePreview,main,markdown,render,semantic,table,exportAssets,exportFonts}.ts`, `Sources/App/{AccessAndWatch,AppModel,EditorWebView,HTMLPrintRenderer,MyMarkdownViewerApp,WorkspaceView}.swift`, `Windows/{main,export}.mjs`, `Windows/ui/`, `Android/reader/reader.ts`.

## UI·출력 확인

표 편집 조작과 집중 모드의 현재 문단 강조, 좁은 Windows 창 메뉴 접근, 각주·목차 실제 이동을 검사했다. 집중 모드에서도 읽기 폭은 유지한다. 기존 우클릭 메뉴와 테마·검색·파일 관리의 회귀 테스트를 통과했다.

Windows 엔진의 긴 PDF는 10페이지이고, 첫 제목과 마지막 문구를 텍스트로 확인했다. 1·3·6·10페이지를 macOS PDFKit/Quartz로 직접 확인하여 한글·표·수식·Mermaid·여백·마지막 각주가 보이는 것을 검증했다. Mac 최종 QA5 앱은 실제 폴더·문서 열기와 저장 창을 거쳐 HTML 및 8페이지 PDF를 생성했다. 첫 제목·마지막 ENDQA9C3A, 한글·표·수식·Mermaid, 로컬 이미지와 글꼴 포함, 원본 해시 보존을 확인했다. 첫·중간·마지막 페이지를 직접 검토했다. 단순 PDF 헤더·페이지 수만으로 출력 성공을 판단하지 않았다.

## 검증

- Astra 직접 실행: Swift 34개, 공통 단위 16개, WebKit 브라우저 45개 통과.
- 성능: 2,990,014바이트·20,003줄, 열기 259ms, 입력 P95 25ms. 이 결과는 자동 테스트 표본이며 모든 문서·기기의 보장은 아니다.
- Windows: 코어 15개, Electron parity 6 / context menu 7 / design 8 / smoke 17 / UI 9, 신규 기능 7개 항목 통과. 최종 ASAR에서 신규 기능과 smoke를 다시 실행했다. ZIP 무결성, PE AMD64, ASAR 소스·리소스 일치를 검증했다.
- Android: Luna 최종 빌드·서명·122개 자산 일치 검사 후 Astra가 브라우저 및 실제 Android WebView 자동 검증을 다시 실행했다. 신규 문법의 이동·표시와 원본 파일 해시 보존을 확인했다.
- Mac: 최종 변경 전 QA2 전체 AppQA 통과. 이후 저장 목적지 보호 및 감시 수정은 QA5 실제 메뉴·저장 창·폴더/문서 열기로 재검증했다. QA5의 자동 AppQA 보고서는 생성되지 않았으므로 전체 자동 재실행으로 기록하지 않는다. 자세한 구분은 `typora-implementation-mac-validation.json`에 기록했다.
- Astra 감시 harness: 실제 변경 이벤트 1회, 중지 이후 콜백 0회, 50회 반복 생성·중지, 메인 처리 heartbeat 100회 및 최대 간격 17.7ms 통과. 재현 코드는 `Tests/AppHarnesses/FolderObservationHarness.swift`.
- 배포 파일 버전·해시·검증 환경은 `typora-implementation-release.json`에 기록한다.

환경: macOS Apple Silicon, WebKit 및 Electron 44.3.0. Android 15 API 35 arm64 전용 에뮬레이터 5580. Windows 실행 파일 대상은 Windows 11 Intel/AMD x64이나 UI 실행 검증은 macOS의 동일 Electron 코드에서 수행했다.

## 제한과 후속 범위

실제 Windows PC·Explorer, 물리 두벌식 조합, Intel Mac/macOS 14, 사용자 Android 기기, 실제 클라우드 동기화 폴더는 미검증이다. Mac은 개인용 ad-hoc 서명이며 공증하지 않았다. Windows는 개인용 서명 없는 ZIP이다. APK는 기존 개인 서명으로 생성했다. 기존 `/Applications` 설치본은 교체하지 않았고 외부 전송·푸시·병합·커밋은 하지 않았다.

이미지 파일·DOCX·EPUB 내보내기, 사용자 CSS 테마, 다중 탭/다중 창, 최근 문서·복제·파일 목록 정렬 등은 이번 승인 범위에 포함하지 않았다.

## 새 교훈

`.codex/lessons.md`에 문서 전체 각주 상태의 재사용 오류, 빈 셀 위치 추정, PDF 내용 검증 누락, 호스트별 CSP, 테스트 준비 조건과 파일 소유권 경계를 기록했다. Mac 인쇄는 로딩 완료 뒤 중단하지 않고 비동기 인쇄 완료 콜백을 기다려야 했다. 저장 창 권한과 임시 출력 경로를 구분하고, 폴더 감시가 화면 스레드를 막지 않도록 해야 한다. PDF 검사 도구도 실제 페이지 범위 안에서 표본을 선택하도록 보완했다.

## 빌드 파일

- macOS 0.2.0 (3): `dist/MyMarkdownViewer-0.2.0-macOS.zip` — Apple Silicon / Intel Universal.
- Windows 0.2.0: `dist/windows/MyMarkdownViewer-0.2.0-Windows-x64.zip` — 압축 해제 후 실행.
- Android 1.1.0 (3): `dist/android/MarkdownReader-1.1.0-Android.apk` — 개인 설치용 읽기 전용 앱.
