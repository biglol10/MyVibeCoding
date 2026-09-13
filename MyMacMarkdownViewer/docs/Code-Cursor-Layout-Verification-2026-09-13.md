# 코드 블록 커서 위치 수정 — 2026-09-13

Mac 0.3.5 (11), Windows 0.3.6에 반영했다. 코드 언어 선택 기능은 유지한다. Android는 독립된 읽기 화면이므로 같은 커서 전환 경로가 없으며, 검증한 기존 1.2.3 (9) APK를 함께 제공한다.

## 원인과 변경

- 코드 시작·끝 구분자에 커서가 도달하면 테두리·여백을 적용할 줄이 달라졌다. 구문 분석으로 확인한 실제 코드 본문의 처음·끝 줄에 상자 스타일을 적용한다.
- 언어 선택 요소가 인라인 기준선에 영향을 받아 코드 상자와 겹쳤다. 시작 줄에 전용 공간을 확보하고 그 공간에 헤더를 고정한다.
- 미리보기 전환이 뒤의 빈 줄까지 포함해 아래 문단이 이동했다. 실제 빈 줄을 남긴다.
- 설치본의 긴 코드에서는 미리보기의 가로 스크롤과 편집 중 줄바꿈이 달랐다. 두 상태의 줄바꿈·탭 폭을 맞췄다. 처음 추가한 회귀 검사 네 개가 수정 전 실패했고 수정 후 통과했다.
- 숨긴 구분자는 라이브 모드의 기본 방향키 이동에서 건너뛴다. 원문 모드·범위 선택·보조키·입력 조합 중에는 기존 편집 동작을 유지한다. 구분자 범위는 문서 변경 때 계산하며 커서 이동마다 전체 문서를 다시 순회하지 않는다.

주요 파일은 `Editor/src/livePreview.ts`, `Editor/src/style.css`다. `Editor/tests/browser/code-cursor-layout.spec.ts`와 `Windows/tests/electron-code-cursor.mjs`에 재현 검증을 추가했다. `Sources/App/AppQA.swift`의 검증 전용 경로는 백그라운드 화면 갱신 대기로 저장 검증이 멈추지 않도록 수정했다.

## 직접 실행한 검증

| 검증 | 결과와 범위 |
| --- | --- |
| 전체 브라우저 회귀 | 162개 통과: WebKit 81개, Chromium 81개 |
| 단위 검사 | Editor 20개, Windows 22개 통과 |
| 커서 배치 | 17px·30px 글자, 블록 앞·구분자·본문·뒤 빈 줄, 범위 선택, 실제 클릭·방향키, 빈 블록 |
| 긴 코드 | 720px·1100px 창에서 공백 있는 긴 줄·긴 문자열·탭, 상자 하단과 뒤 문단 좌표 |
| Electron 앱 | macOS arm64에서 3개 테마 × 5개 커서 상태와 실제 방향키, 원문 무변경 저장 통과 |
| 언어 변경 | Mac WKWebView와 Electron에서 언어 토큰만 변경, BOM·CRLF 보존, 저장·실행 취소·다시 실행 통과 |
| 설치된 Mac 앱 | 실제 문서에서 클릭·방향키 후 헤더·프레임·긴 줄 높이·뒤 문단 위치 유지 확인. 원본 체크섬 유지 |
| 배포 파일 | Mac Universal 서명·242개 번들 파일·235개 공통 편집기 자산 일치. Windows ZIP·x64 실행 파일·ASAR 자산 일치 |
| Android | 휴대전화 크기의 읽기 화면 두 검사 통과, APK 서명·ZIP 무결성·122개 자산 일치 |

실제 확인 환경은 macOS 26.6.2 arm64, WebKit·Chromium, macOS에서 실행한 Electron이다. 실제 Windows PC와 Android 기기, 물리 두벌식 입력 검증을 대신하지 않는다. Mac은 ad-hoc 서명이며 다른 Mac에서의 공증·실행 검증은 포함하지 않았다.

## 설치와 전달 기록

- [설치 검증](code-cursor-installation.json): `/Applications/MyMarkdownViewer.app` 교체와 현재 문서·폴더·Night 테마 보존.
- [Mac 동작 검증](code-cursor-mac-verification.json), [Windows 동작 검증](code-cursor-windows-verification.json), [Android 검증](code-cursor-android-verification.json).
- [최종 배포 기록](code-cursor-release-verification.json): 최종 파일 크기·체크섬과 검증 범위.

## 다음 검증에 적용할 교훈

`.codex/lessons.md`에 짧은 코드의 본문 클릭만으로 완료하지 않는 규칙을 보강했다. 구분자·빈 줄·선택·방향키·긴 줄·좁은 창을 포함해 헤더, 테두리, 여백, 코드 하단, 앞뒤 문단 위치를 함께 비교한다. 네이티브 검증의 화면 갱신 대기와 제품 동작 실패도 구분한다.
