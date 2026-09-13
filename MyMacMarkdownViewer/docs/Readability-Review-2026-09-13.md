# 링크·코드 가독성과 관련 사용성 검토

2026-09-13. 링크·코드·검색 표시의 가독성을 검토하고 Mac, Windows 호스트, Android 읽기 화면에서 수정 사항을 확인했다.

## 확인한 문제와 수정

| 항목 | 수정 전 | 수정 후 |
| --- | --- | --- |
| 클릭하여 편집 중인 링크 주소 | 모든 테마에 기본 `#221199`가 적용돼 Night 대비 약 1.16:1 | 테마별 링크 색상 적용. Night 약 7.51:1, Light 약 5.56:1, Dark 약 8.77:1 |
| 코드 글자 크기 | 17px 본문에서 읽기 13.94px, 편집 14.28px | 둘 다 16.15px, 사용자 크기에 따라 확대하며 최소 15px |
| 코드 문법 구분 | 편집 중 함수명이 일반 변수 색으로 덮이고, Python 문자열 안의 값·JSON 키 구분이 부족 | 실제 구문 태그를 사용하는 색상 규칙. 함수·키워드·문자열·숫자·주석·보간 값을 구분하고 HTML 내보내기에도 적용 |
| 코드 클릭 시 간격 | 일반 문단의 빈 줄 축소 규칙과 서로 다른 상자 글꼴 기준으로 코드 높이가 줄어듦 | 코드 빈 줄을 문단 축소에서 제외. 읽기·편집의 상자 글꼴·크기·줄 높이를 일치시키고 전체 높이 차이를 검사 |
| Windows 코드 글꼴·링크 안내 | Mac 중심 글꼴 대체 순서와 고정된 ⌘클릭 안내 | Cascadia Code·Consolas 대체 글꼴 추가, Windows는 Ctrl클릭 안내 |
| 밝은 테마 보조 글자·오류 | 흐린 보조 글자와 Markdown 구분자, 오류 설명의 낮은 대비 | 보조 색상·불필요한 투명도 조정, 오류 안내 테마 색상과 최소 14px 적용 |
| 검색 결과 | 반투명 강조 위에 문법 색상이 겹쳐 읽기 어려울 수 있음 | 결과 강조의 배경·글자색을 함께 지정. 코드 문자열 안의 검색도 검증 |
| Android | 작은 코드·인라인 코드, 일부 문법 구분 부족 | 최소 크기·문법 색상·표 글자·검색 강조 보완. 긴 코드와 표는 내부에서 스크롤하고 긴 링크는 화면 안에서 줄바꿈 |

Android의 기존 Night 링크 색상은 이미 충분한 대비가 있었다. 링크 색상 결함을 Android에서도 재현했다고 간주하지 않았다.

일반 글자 대비 검사는 [WCAG 2.2의 4.5:1 기준](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)을 참고했다. 계산뿐 아니라 실제 화면의 크기·간격·색 구분도 확인했다. 전체 앱에 대한 접근성 인증을 의미하지 않는다.

## 검증 범위와 결과

- 공통 편집기 단위 테스트: **16개 통과** (`build/readability-editor-unit.log`).
- WebKit 전체 브라우저 테스트: **65개 통과** (`build/readability-webkit-all.log`).
- Chromium 전체 브라우저 테스트: **65개 통과** (`build/readability-chromium-all.log`).
- 새 가독성 회귀 검사 5개: 세 테마의 링크·코드·실제 편집 토큰, 원문·실행 취소, 확대와 전환 크기, 오류·HTML 출력, 검색 강조, 빈 줄을 포함한 코드 전체 높이.
- Windows 호스트: Mac에서 실행한 Electron의 실제 설정 창으로 세 테마를 변경하고, 편집기 전달·900×640 창의 설정 버튼·내용 너비를 확인했다 (`build/readability-windows-host.log`). 기존 코드·그림 편집, 실행 취소, 저장 후 원본 바이트 검사도 통과했다 (`build/readability-windows-code-preview.log`). 검증 프로세스는 종료까지 확인했다.
- Android 읽기 자산 빌드 후 `reader-readability`, `reader-browser`, `reader-navigation`, `reader-session`, `reader-settings` 모두 통과했다. 393×852 모바일 Chromium과 기존 가로·태블릿 검증을 포함한다. 원본을 편집하는 요소가 생성되지 않고, 검색 뒤 문법 표시가 유지됨을 확인했다.
- Mac Universal Release 빌드와 서명 검증 통과. **macOS 26.6.2 / Apple Silicon**에서 별도 식별자의 검증용 앱을 실행해 Night 설정, 링크 클릭·줄바꿈, 코드 클릭·색상·빈 줄 간격을 직접 확인했다. 코드에 주석을 입력하고 저장한 파일을 읽어 확인한 뒤, 실행 취소·재저장한 파일의 SHA-256이 처음과 같음을 확인했다.
- 최종 공통 편집기 **235개 파일**을 Mac 검증용 앱 및 Windows 편집기 자산과 대조했다. Windows HTML의 연결 스크립트·스타일 삽입을 반영했으며 불일치는 없었다. 수치·해시는 `readability-verification-2026-09-13.json`에 기록했다.

## 주요 변경 파일

- `Editor/src/main.ts`: 테마에 따르는 의미별 구문 색상.
- `Editor/src/style.css`: 링크·코드·빈 줄·검색·오류·보조 글자 가독성.
- `Editor/src/textPreview.ts`: 플랫폼별 링크 조작 안내.
- `Editor/src/render.ts`: 독립 HTML의 코드 문법 색상.
- `Android/reader/reader.css`: 모바일 읽기 크기·문법 색상·검색 대비.
- `Editor/tests/browser/readability.spec.ts`, `Windows/tests/electron-readability.mjs`, `Android/tests/reader-readability.mjs`: 실제 사용 상태 회귀 검사.
- `Windows/tests/electron-fixtures.mjs`: 자동화 연결 종료와 프로세스 종료 사이의 지연을 구분하는 QA 정리.

## 화면 검증

수정 전후 비교 화면과 자동화 캡처는 로컬 검증 산출물이며 공개 저장소에는 포함하지 않았다.

## 적용 범위와 제한

소스, Mac 검증용 앱, Windows 공통 편집기 자산, Android 읽기 자산에 반영했다. `/Applications`의 설치 앱 교체와 새 Windows ZIP·APK 생성·메일 발송은 이 작업에서 진행하지 않았다. 기존 배포본은 수정 전 버전이다.

Windows 실기기와 Android 실기기의 OS·글꼴·입력 환경은 이번에 검증하지 않았다. Mac Intel은 빌드에 포함했으나 직접 실행하지 않았다. 물리 두벌식 IME 검증도 이번 가독성 검사에 포함하지 않았다.

`.codex/lessons.md`에 실제 링크 대비·구문 클래스 우선순위·비동기 구문 로딩·빈 줄 및 전체 코드 높이 검사·Electron 검증 종료에 관한 예방 규칙을 추가했다.
