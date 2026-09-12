# 최종 리뷰 및 세 플랫폼 재빌드 — 2026-09-12

## 완료 범위

직전 Windows 감사에서 확인한 누락 5개와 이번 리뷰에서 확인한 버그를 수정했다. Astra가 변경분과 관련 사용 흐름을 리뷰하고, 수정 요청 후 재리뷰 및 직접 검증을 수행했다. 초기 이미지의 전체 신규 기능 로드맵까지 확대할지는 질문 답변 대기 상태이며 이번 완료 범위로 간주하지 않는다. Android는 이전에 합의한 읽기 전용을 유지한다.

| 항목 | 결과 | 주요 파일 |
|---|---|---|
| Windows 문서 내 찾아 바꾸기 | 편집 메뉴 및 Ctrl+H 연결, 실제 교체 검증 | `Windows/ui/index.html`, `Windows/main.mjs` |
| Windows 인라인 코드 | 서식 메뉴 연결, 문서 변경 검증 | `Windows/ui/index.html`, `Windows/main.mjs` |
| Windows 이미지 파일 선택 | 이미지 삽입 메뉴, 20 MiB 제한 및 제한된 읽기, 취소·파일 형식 확인 | `Windows/main.mjs` |
| Windows 탐색기에서 보기 | 파일 메뉴 및 우클릭 대상 경로 연결, 폴더 열기 실패 표시 | `Windows/main.mjs`, `Windows/ui/shell.mjs` |
| Windows 시스템 테마 | 사용자 선택과 실제 밝기 값을 분리, 메뉴·설정창·재실행 검증 | `Windows/main.mjs`, `Windows/ui/shell.mjs` |
| 우클릭 메뉴 | 포인터 위치·항목 대상·화면 경계·키보드 동작 회귀 검증 | `Windows/ui/shell.mjs`, `Windows/ui/shell.css` |
| `.markdown` 파일 누락 | Mac/Windows 목록·검색·바꾸기·링크·이동 및 이름 처리에 공통 판별 적용 | `Sources/Core/Settings.swift`, `FolderSearch.swift`, `WorkspaceFiles.swift`, `Sources/App/AppModel.swift`, `Windows/core.mjs`, `Windows/main.mjs` |
| Windows 문서 내 한글 링크 | 퍼센트 인코딩 해제, 공통 Markdown 파서의 실제 제목 사용; 코드 블록의 가짜 제목 제외 | `Windows/main.mjs` |
| 배포 버전 구분 | Mac 0.1.1, Windows 0.1.2, Android 1.0.1; 파일명을 버전에서 생성 | `Resources/Info.plist`, `scripts/build.sh`, `Windows/package.json`, `Android/app/build.gradle`, `Android/scripts/package-apk.py` |

Android 제품 동작은 변경하지 않았다. 기존 APK와 동일한 개인 서명 인증서로 새 버전을 만들었다. Windows 이미지 형식 확인은 확장자·시그니처·크기 검사이며, 유효한 PNG의 편집기 표시를 실제 검증했다. 모든 손상 파일의 완전한 디코딩 검증을 의미하지 않는다.

## UI·UX 검토

- Windows 최종 패키지에서 Mac에 가까운 상단 도구 배치, 본문 여백, 나이트 테마, 최소 800×560 창의 설정·검색·파일 메뉴를 확인했다.
- 시스템 테마는 메뉴와 설정창에서 직접 선택하고 앱 화면과 편집기에 같은 밝기 값이 전달되는지 검사했다. 네이티브 밝기 변경을 모의하여 밝음/어두움 각각을 확인하고 재실행 후 선택 유지도 확인했다.
- Mac의 배포 QA 앱을 직접 열어 `.MARKDOWN` 문서 표시, 검색 결과, 저장 상태와 화면 간격을 확인했다.
- Android 최종 APK의 한글, 목차·검색·중첩 폴더, 읽기 전용 표시와 원본 파일 해시 보존을 확인했다. 휴대폰·태블릿 크기에서도 검증했다.

## 실행 및 통과한 검증

| 검증 | 통과 | 환경 / 증거 |
|---|---:|---|
| 공통 편집기 단위 / WebKit | 7 / 27 | `build/final-review-editor-tests.log`, `build/final-review-editor-browser.log` |
| Mac Swift 단위 | 34 | Astra 재실행, `build/final-review-swift-integrated.log` |
| Mac 네이티브 QA | 30개 불리언 검사 | macOS arm64, 배포본과 일치한 사본을 별도 식별자로 재서명, `final-review-mac-validation.json`; 물리 IME 제외 |
| Windows 핵심 | 15 | Astra 재실행, `build/final-review-windows-core.log` |
| Windows 최종 ASAR 기능 / 우클릭 / 디자인 / 통합 / UI | 6 / 7 / 8 / 17 / 9개 검증 묶음 | Astra 재실행, `build/final-review-packaged-electron-*.log`; macOS arm64 Electron 44.3.0 |
| Android 브라우저 | 13개 검증 묶음 | Astra 재실행, 휴대폰 393×852·태블릿 1024×768, `build/final-review-android-browser-root.log` |
| Android 최종 서명 APK 네이티브 | 9개 검증 묶음 | Astra 재실행, Android 15/API 35 arm64 전용 에뮬레이터, `build/final-review-android-native-root.log` |
| 배포 무결성 | 통과 | Mac Universal 및 서명·ZIP CRC, Windows ASAR 원본 대조·ZIP CRC·PE AMD64, APK 서명·비디버그·이전 인증서 일치·리소스 122개 일치 |
| 변경 공백 오류 | 통과 | `git diff --check` |

Windows 통합 테스트의 오래된 이미지 URL 404는 의도한 거부 검증이다. Windows UI 스크립트도 `PACKAGED_APP`을 받도록 보강한 후 최종 ASAR로 다시 실행했다. 코드/리소스와 배포물의 상세 해시·검증 요약은 [final-review-release.json](final-review-release.json)에 기록했다.

## 배포 파일

- [Windows 0.1.2 x64 ZIP](../dist/windows/MyMarkdownViewer-0.1.2-Windows-x64.zip): 전체 압축 해제 후 `MyMarkdownViewer.exe` 실행.
- [Mac 0.1.1 Universal ZIP](../dist/MyMarkdownViewer-0.1.1-macOS.zip): 압축 해제 후 앱 사용. arm64 및 x86_64 포함.
- [Android 1.0.1 APK](../dist/android/MarkdownReader-1.0.1-Android.apk): 개인 서명, versionCode 2, 기존 1.0과 인증서 일치.

기존 사용자 설치본·문서는 교체하지 않았다. 메일 발송·외부 배포·커밋·푸시는 하지 않았다.

## 남은 검증 및 결정

실제 Windows PC의 탐색기·시스템 테마 전환·Windows IME, 물리 Mac 두벌식, 실제 Intel Mac/macOS 14, 사용자 Android 실기기, 실제 클라우드 동기화 폴더는 미검증이다. Mac은 개인용 ad-hoc 서명이며 Developer ID 공증은 포함하지 않는다. 초기 로드맵 전체 확대 및 APK 편집 기능 추가 여부는 사용자 답변 전까지 구현하지 않는다.

## 새 교훈

`.codex/lessons.md`에 지원 확장자의 전체 흐름 일치, 샌드박스 QA 경로와 실제 설정 조작 검증, diff 일부만으로 기존 메뉴 누락을 오판하지 않는 규칙을 기록했다. 중복 메뉴는 패키징 전에 제거하고 재검증했다.
