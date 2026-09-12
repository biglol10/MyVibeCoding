# 코드·다이어그램 표시 검증

검증일: 2026-09-12. 통합 편집기와 각 플랫폼의 표시 동작을 직접 검증하고 변경분을 재검토했다.

후속 설치: Mac 0.3.3 (9)를 설치하고 마지막 문서·폴더·Night 화면·목록 스크롤을 확인했다. 아래 설치 미수행 항목은 최초 구현 검증 당시의 범위다. 최신 설치 결과는 `code-preview-installation.json`을 따른다.

## 변경된 동작

- Mac·Windows 공통 편집기에서 코드 블록을 클릭해도 코드 상자, 고정폭 글꼴과 문법 색상을 유지한다. 편집은 기존 문서에서 이루어져 저장·실행 취소·원문 모드를 공유한다.
- Mermaid 그림 클릭은 그림을 유지한다. ‘편집’에서 원문과 그림을 함께 표시하고, ‘편집 완료’는 읽기 상태로 돌아간다. 키보드로 원문에 진입해도 그림을 유지한다.
- 앞 문단 수정 후 블록 위치, 읽기 전용 전환, 문서 전환, 조합 중 입력, 잘못된 Mermaid 수정, 좁은 화면 및 테마를 확인했다.
- Night에서 활성 코드 줄의 배경과 문법 색상을 읽기 화면에 맞췄다. 중첩 코드 탐색이 뒤쪽 독립 블록까지 넘어가지 않게 제한했다.
- Chromium에서 표 입력 확정 중 blur가 다시 발생하는 경우를 차단했다.
- Mac에서 파일 하나만 선택했을 때 문서 옆 임시 파일 생성 권한이 없어 저장하지 못하는 문제를 수정했다. Foundation 교체용 디렉터리를 사용하며 기존 충돌 검사·백업·원자적 교체를 유지한다.

주요 파일: `Editor/src/livePreview.ts`, `Editor/src/main.ts`, `Editor/src/style.css`, `Sources/Core/FileStore.swift`. 검증: `Editor/tests/browser/code-preview.spec.ts`, `Windows/tests/electron-code-preview.mjs`, `Android/tests/reader-browser.mjs`, `Tests/CoreTests/DocumentTests.swift`.

## 실행한 검증

환경: macOS 26.6.2 (25G83), Apple Silicon. Mac QA 앱은 arm64·x86_64 Universal Release 빌드이며 별도 번들 식별자로 서명했다.

| 검증 | 결과 | 근거 |
| --- | --- | --- |
| 편집기 단위 테스트 | 16 통과 | `build/code-preview-unit.log` |
| WebKit 전체 브라우저 테스트 | 60 통과 | `build/code-preview-webkit-all.log` |
| Chromium 전체 브라우저 테스트 | 60 통과 | `build/code-preview-chromium-all.log` |
| Swift 테스트 | Swift Testing 47 + XCTest 2 통과 | `build/code-preview-swift-tests.log` |
| Mac Universal Release 빌드·서명 검사 | 통과 | `build/code-preview-xcodebuild.log`, `codesign --verify --deep --strict` |
| 실제 Mac QA 화면 | 통과 | 그림 클릭 유지, 원문+그림, 편집 완료, Night 코드 가독성, 편집·저장·실행 취소 |
| 파일만 연 Mac 저장 흐름 | 통과 | 폴더 권한 없이 코드 수정→저장→실행 취소→재저장 후 검증 문서 원본 바이트 일치 |
| Electron 데스크톱 통합 | 통과 | Mac 호스트 Electron 44.3.0, `build/code-preview-windows-integration.log` |
| Android 읽기 화면 | 통과 | 모바일 Chromium에서 그림·코드 탭 후 표시 유지, 기존 읽기·검색·테마 검사; `build/code-preview-android-browser.log` |
| 공통 빌드 자산 비교 | 통과 | `docs/code-preview-artifacts.json`; Windows HTML의 연결 스크립트·스타일 추가를 반영 |

추가된 11개 브라우저 회귀 검사에는 코드 편집·undo, 그림 편집·undo/redo, 키보드 진입, 원문 모드, 잠금, 문서 전환, 오류 복구, 앞쪽 삽입과 중첩 블록 범위가 포함된다.

## 확인 범위와 남은 제한

- Windows 검증은 Mac에서 실행한 Electron과 Chromium 기준이다. Windows 실기기·설치 파일은 이번에 검증하거나 새로 만들지 않았다.
- Android는 읽기 화면 표시를 확인했다. 제품 코드 변경이나 APK 재빌드, 실기기 검증은 하지 않았다.
- Mac 실제 화면 검증은 Apple Silicon에서 수행했다. Intel 실행과 물리 두벌식 조합 입력은 검증하지 않았다.
- 목록·인용문 안의 복잡한 중첩 Mermaid를 독립된 편집 가능 그림으로 만드는 기능은 이번 범위에 포함되지 않는다.
- 이번 수정은 소스와 QA 빌드에 적용했다. `/Applications/MyMarkdownViewer.app`의 기존 0.3.2 (8)은 교체하지 않았다.
- 이번에 실행한 Mac QA 앱과 임시 미리보기 서버는 종료했다. 사용자 설치 앱은 유지했다.
- `.codex/lessons.md`에 표시·편집 상태, 응답별 집계 기준, 단독 파일 저장 권한과 검증 보완을 기록했다.

Foundation 교체 위치의 근거: [Apple FileManager.itemReplacementDirectory](https://developer.apple.com/documentation/Foundation/FileManager/SearchPathDirectory/itemReplacementDirectory).
