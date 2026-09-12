# 기능·UI·사용성 전체 점검 — 2026-09-12

이번 검증은 현재 제공하는 기능의 품질 점검이며 Typora 전체 기능 동등성 또는 모든 기기의 무결함 보증은 아니다. 기존 변경을 보존하고 Astra가 공통 편집기·Mac을 점검, Terra가 Windows, Luna가 Android를 조사했다. 각 변경은 Astra 리뷰 후 필요한 수정과 재검증을 수행했다.

## 발견하여 수정한 문제

| 문제 | 수정 | 주요 파일 |
|---|---|---|
| 표 제목 셀에서 행 삭제 시 다른 본문 행 삭제 | 제목 행 삭제 방지, 표시 행 번호를 연속적으로 정리 | Editor/src/table.ts, livePreview.ts |
| 표 마지막 셀 Tab 후 포커스 유실, 첫 셀 Shift+Tab 탈출 불가 | 새 행 첫 셀 포커스 및 이전 컨트롤로 이동 | Editor/src/livePreview.ts |
| 유효한 짧은 Markdown 표 행의 생략된 셀을 편집할 수 없음 | 빈 셀 입력 표시 및 원문 보존하는 값 반영 | Editor/src/livePreview.ts |
| 셀 편집 중 호스트 서식/실행 취소가 다른 문단에 적용 | 활성 셀 선택에 인라인 서식 적용, 실행 취소 전 셀 확정; 부적합한 블록 명령은 안내 | Editor/src/main.ts |
| 표 편집 진입이 작고 눈에 띄지 않음 | 버튼 배경·테두리·32px 클릭 높이·키보드 포커스 표시 | Editor/src/style.css |
| Mac의 폴더 전체 검색 명령이 이전 하위 폴더 범위 유지 | 전체 검색 명령에서 범위 초기화; 이동/휴지통에 따른 범위 갱신; 바꾸기 검토 대상 표시 | Sources/App/AppModel.swift, FolderSearchView.swift |
| Windows 검색 입력·범위·취소 뒤 오래된 비동기 결과/미리보기 복원 | 준비 단계부터 요청 세대 확인, 입력/옵션 변경 시 결과와 미리보기 무효화, 취소/무응답 처리 | Windows/main.mjs, ui/shell.mjs |
| Windows 긴 정보 경로/검색 범위 표시 | 경로 줄바꿈과 초기화 영역 스타일 보강 | Windows/ui/shell.css |
| Android 다크 버튼이 Night에 연결 | 실제 Dark/Night 색상·선택·저장/재실행을 구분 | Android/reader/index.html, tests/reader-settings.mjs |

표 문제 네 가지는 수정 전 실패하는 브라우저 조작 테스트로 재현하고 수정 후 통과했다. 표 셀 입력은 Enter·Tab·포커스 이동 또는 저장 스냅샷에서 원문에 반영하는 기존 방식이다.

## 직접 다시 실행한 검증

| 영역 | 결과와 범위 | 근거 |
|---|---|---|
| 공통 편집기 | 단위 16개, 최종 WebKit 49개 통과: 렌더링·공백·한글/이모지·합성 조합 이벤트·표·참조/각주/TOC·테마·내보내기·실행 취소·잠금·대형 문서 | build/full-audit-editor-unit.log, full-audit-final-editor-browser.log |
| Mac 핵심 | Swift 37개 통과: 바이트/BOM/줄바꿈 보존·동시 저장·검색·파일 생성/이동/복제/충돌 | build/full-audit-final-swift.log |
| Mac 최종 Release QA | 저장/자동 저장/복구, 저장 중 추가 입력, 외부 변경·삭제·권한 실패, 파일 이동 후 링크·실행 취소, 선택 범위 검색/전체 초기화·바꾸기, Markdown 확장자 통과 | full-audit-mac-validation.json |
| Mac 출력 | 실제 PDF 8페이지, 첫·끝 문구 및 첫·끝 페이지 렌더 화면의 한글·수식·표·다이어그램 확인 | QA/FullAuditFinal-20260912/export-test.pdf, export-first.png, export-last.png |
| Mac 성능 | 약 2.99MB/20,003줄 읽기부터 2프레임까지 약 669ms, 프로그램 입력 p95 24ms, 네이티브 왕복 p95 약 41ms | full-audit-mac-validation.json |
| Mac 화면 | 실제 설정 화면 스크롤, 좁은 창의 검색·본문·표, 최종 표 컨트롤·제목 행 삭제 비활성 확인 | CUA 실제 앱 조작 |
| Windows | 핵심 16개 및 smoke/UI/context-menu/features/parity/design/performance 전부 root 재실행 통과 | build/full-audit-root-windows-*.log |
| Windows 화면/성능 | 800×560 설정/검색/메뉴, 키보드 접근, 긴 경로, 테마; 1,200항목 유휴 5.2초 읽기/목록조회 0, 20회 입력 중 트리 변형 0 | Windows/test-results/, performance.log |
| Android 읽기/테마 | 브라우저/설정 검증 root 재실행, 휴대폰·가로·태블릿·28px 글자에서 본문 가로 넘침 없음, 표 내부 스크롤 확인 | build/full-audit-root-android-*.log, Android/test-results/android-audit-*.png |
| Android 최종 APK | 1.1.2/code5를 전용 Android15/API35 arm64 에뮬레이터에 업데이트, SAF 계측 5개 통과 | build/full-audit-final-android-instrumentation.log |
| 빌드/배포 | Mac Universal/서명/설치본 일치, Windows ASAR 소스 일치/PE x64/ZIP, APK 기존 개인 서명/비디버그/122개 리소스 일치, 모든 압축 무결성 통과 | full-audit-release.json, windows-verification-results.json |

Android Gradle lint는 오류 0, 경고 8이다. 버전 갱신 권고, target API, intent-filter 표기, JavaScript 사용 점검, 백업 설정 권고가 남는다. Android 순수 단위 테스트 태스크는 NO-SOURCE이며 통과 테스트 수로 세지 않았다.

## 남은 확인 범위

- 실제 Windows PC의 Explorer·시스템 테마·Windows IME, 실제 Intel Mac/macOS14, 물리 두벌식, 실제 클라우드 동기화는 이번 실행으로 검증하지 않았다.
- Android 사용자 실기기의 시스템 뒤로 가기·파일 선택 취소·프로세스 종료 후 복원·기기 글꼴 배율·최대 크기 파일 경계는 추가 실기기 검증이 필요하다. 브라우저 크기 변경은 실기기 회전 검증을 대신하지 않는다.
- 최종 APK는 WebView 디버깅이 꺼져 있어 CDP 연결을 시도한 검사는 진행할 수 없었다. 별도의 signed 계측과 브라우저 검증을 구분했다.
- Mac은 개인용 ad-hoc 서명이며 Windows는 서명하지 않은 개인 배포물이다.

## 배포 및 설치

Mac 0.2.2(5), Windows 0.2.2, Android1.1.2(5)를 다시 빌드했다. Mac 설치본은 이전 버전을 백업하고 교체했다. 사용자 문서·설정은 보존했다. 실기기 설치, 메일, 푸시, 병합은 수행하지 않았다.

상세 산출물 해시: [full-audit-release.json](full-audit-release.json).
