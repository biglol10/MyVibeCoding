# Release 앱 교체 — 2026-09-09

## 결과

사이드바 파일 관리, 폴더 검색·바꾸기, UI 간격과 체크리스트 보완을 포함한 현재 소스로 Universal Release 앱과 ZIP을 다시 만들었다. `/Applications/MyMarkdownViewer.app` 설치본을 교체하고 해당 경로에서 실행했다. 버전 표시는 0.1.0이며 이번 빌드는 아래 ZIP 해시로 구분한다.

- 배포 앱: `dist/MyMarkdownViewer.app`
- 배포 ZIP: `dist/MyMarkdownViewer-0.1.0-macOS.zip`
- ZIP SHA-256: `0dd03d88171577b3059227d078ca40b51ffd4b360550e07c4d6db88c6a8cc3bf`
- 이전 설치본: `build/previous-installed-65jrw47e/MyMarkdownViewer.app`
- 이전 배포 ZIP: `build/pre-ux-release-17z59n9a/MyMarkdownViewer-0.1.0-macOS.zip`

기존 앱을 정상 종료한 뒤 새 사본의 서명과 전체 파일 해시를 검사했다. 이전 앱은 삭제하지 않고 보관했으며, 설치 완료 후 241개 파일·링크 항목이 배포 앱과 일치함을 다시 확인했다. 실제 사용자 문서와 앱의 저장 데이터는 교체 대상에 포함하지 않았다.

## 검증

- 편집기 타입 검사·빌드, Xcode Universal Release 빌드 성공. arm64와 x86_64 실행 파일 포함.
- 배포 앱·설치본의 `codesign --verify --deep --strict` 통과. ZIP 무결성 검사 통과.
- 앞서 통과한 Swift 26개, Markdown 6개, WebKit 25개의 UI 관련 소스 해시가 이번 빌드 소스와 일치함을 확인했다. 이 설치 작업에서 해당 테스트 전체를 다시 실행했다고 주장하지 않는다.
- Release QA 사본은 재서명 전에 배포본과 전체 파일 일치를 확인했다. 별도 앱 식별자로 재서명한 뒤 서명과 편집기 리소스 일치를 확인하고 자체 생성 문서로 네이티브 검증을 수행했다.
- macOS 26.6.2 / Apple Silicon / Release / WKWebView에서 저장·복구·외부 변경·권한 실패·이동·검색·바꾸기·테마·성능 검증을 통과했다. 결과는 [release-install-results.json](release-install-results.json)에 기록했다.
- 약 3 MB, 20,003줄 문서 읽기부터 두 프레임까지 약 1,082ms, 프로그램 입력 p95 67ms였다. 실제 물리 키보드 입력 지연 검증은 아니다.
- `/Applications` 설치본을 실제 실행하고 기존 폴더·테마 복원, 파일 탭의 추가 메뉴, 검색 탭과 ⌘⇧F 화면 전환을 확인했다.

## 남은 제한

- 사용자가 이번 작업을 앱 교체까지만 진행하도록 선택했다. 실제 두벌식 IME는 미실행으로 유지한다. 추후 환경은 Mac 내장 키보드·macOS 두벌식이며 [검증표](Korean-IME-Checklist.md)에 기록했다.
- Intel 실행 파일 포함을 실제 Intel Mac 실행 검증으로 간주하지 않는다. Intel·macOS 14·클라우드 동기화 폴더의 실제 동작은 미확인이다.
- 개인용 ad-hoc 서명이며 Developer ID 서명·공증·다른 Mac 배포 검증은 포함하지 않는다. 외부 게시·푸시·병합은 수행하지 않았다.

## 추가 교훈

검증용 앱을 재서명하면 실행 파일의 서명 데이터도 바뀐다. QA 사본 전체 비교는 재서명 전에 수행하고, 실제 설치본은 원래 서명 그대로 복사해 배포본과 비교하도록 `.codex/lessons.md`에 기록했다.
