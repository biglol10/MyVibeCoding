# MyMarkdownViewer 2026년 10월 11일 갱신

Mac 0.3.8 (14)의 숨김 파일·폴더 표시 기능을 MyVibeCoding에 반영했다. Windows 0.3.8과 Android 1.2.3은 기존 공개 설치 파일을 유지하며, 이번 숨김 항목 옵션은 macOS에만 추가했다.

## 다운로드

- [Mac 0.3.8 Universal ZIP](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacMarkdownViewer/MyMarkdownViewer-0.3.8-macOS.zip) · [SHA-256](../../downloads/MyMacMarkdownViewer/MyMarkdownViewer-0.3.8-macOS.zip.sha256)
- [Windows 0.3.8 x64 ZIP](https://github.com/biglol10/MyVibeCoding/releases/download/apps-2026-09-27/MyMarkdownViewer-0.3.8-Windows-x64.zip)
- [Android 1.2.3 APK](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacMarkdownViewer/MarkdownReader-1.2.3-Android.apk) · [SHA-256](../../downloads/MyMacMarkdownViewer/MarkdownReader-1.2.3-Android.apk.sha256)
- [세 플랫폼 설치 파일 배포 페이지](https://github.com/biglol10/MyVibeCoding/releases/tag/markdownviewer-2026-10-11)

Mac ZIP은 macOS 14 이상용이며 Apple Silicon·Intel 실행 파일을 함께 포함한다. 압축을 풀어 앱을 `/Applications`에 복사할 수 있다. 개인 실행용 ad-hoc 서명이고 Developer ID 공증본은 아니다. Windows는 전체 압축을 해제한 후 `MyMarkdownViewer.exe`를 실행한다. Android는 읽기 전용 리더다.

## 변경

- 보기 메뉴의 **숨김 파일·폴더 표시**(⌘⇧.)와 설정의 파일 탐색에서 옵션을 바꿀 수 있다. 기본값은 꺼짐이며 재실행 후에도 유지한다.
- `.claude` 같은 숨김 폴더의 Markdown을 파일 목록·빠른 파일 열기·폴더 검색·현재 문서 찾기에 포함한다. 심볼릭 링크와 앱 패키지 내부는 계속 제외한다.
- 목록을 갱신할 때 열린 문서·미저장 편집·커서·스크롤을 유지한다. 설정 변경 전의 검색·바꾸기 검토는 무효화하고, 바꾸기 적용 전 경로를 다시 확인한다.
- 파일 별칭을 건너뛸 때 다음 폴더까지 누락되던 인덱스 문제를 수정했다. 기존 설정의 테마·글꼴·자동 저장 값을 유지한다.

## 검증 범위

MyVibeCoding에서 Swift Testing 회귀 테스트 57개(숨김 항목 테스트 6개 포함)와 XCTest 2개, 편집기 단위 테스트 21개, Windows 코어 테스트 25개가 통과했다. WebKit 브라우저 테스트 95개도 단일 작업자로 재실행해 모두 통과했다. 첫 병렬 실행에서는 초기화 시간 초과 5개가 발생했으며 재실행에서는 재현되지 않았다. Universal Release 앱을 다시 빌드하고 ZIP 무결성·버전·두 실행 아키텍처·서명·라이선스 고지를 확인했다. 기존 Android APK의 v2/v3 서명과 버전 1.2.3 (9), 기존 Windows ZIP 무결성도 재확인했다.

Swift 테스트는 새 임시 빌드 폴더에서 실행했다. 기존 `SessionQA.swift`의 메인 액터 관련 경고 때문에 warnings-as-errors 모드는 통과하지 못했지만 일반 Swift 테스트와 Xcode Release 빌드는 통과했다. 원본 프로젝트에 기록된 네이티브 숨김 항목 검증과 별개로, 이번 동기화에서는 설치 앱·실제 사용자 설정을 변경하지 않았다. Intel 실기·실제 Windows PC·Android 기기의 이번 실행 검증은 수행하지 않았다.
