# MyMacFinder 변경 반영 — 2026-09-28

## 변경 내용

- 빈 폴더와 검색 결과 없음 안내가 마우스 입력을 가로막지 않도록 수정했다. 안내 문구 위에서도 파일 목록의 기존 우클릭 메뉴를 사용할 수 있다.
- 검색 결과가 없을 때의 `Clear All Filters` 버튼을 하단 항목 수 옆으로 옮겼다.
- MyVibeCoding에 있던 외부 폴더 열기 연동과 앱 번들 설정은 보존했다. 원본 프로젝트의 작업 파일·개인 검증 로그는 변경하거나 게시하지 않았다.

## 다운로드

- [최신 개인용 설치 ZIP](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacFinder/MyMacFinder-personal-mac.zip)
- [SHA-256](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacFinder/MyMacFinder-personal-mac.zip.sha256)
- [이번 배포 페이지](https://github.com/biglol10/MyVibeCoding/releases/tag/mymacfinder-2026-09-28)

ZIP SHA-256: `62a8ee7a899738db32c1800fb5f08ba088831caf9a94c4e618aedb38527806d7`.

## 이번 동기화 검증

- `swift test -j 4 -Xswiftc -warnings-as-errors`: 645개 통과, 실패 0개. 원본 프로젝트에는 없는 기존 외부 폴더 연동 테스트 3개도 포함한다.
- Release 빌드 및 개인 설치 ZIP 생성 성공.
- 배포 ZIP 무결성과 압축을 푼 앱의 엄격한 코드 서명 검사 통과.
- 패키지 실행 파일과 빌드된 앱 실행 파일이 일치한다. 외부 폴더 열기 지원 설정도 유지된다.
- 반영한 `RootView.swift`가 현재 원본 파일과 일치한다.

원본 프로젝트의 검증 기록에서는 빈 폴더 우클릭→새 폴더 생성·이름 변경과 검색 필터 초기화를 실제 UI로 확인했다고 보고한다. 이번 동기화에서는 해당 UI 조작을 재실행하지 않았다. 로컬 설치 앱이나 사용자 파일은 교체하지 않았다. 이 ZIP은 개인 사용용 ad-hoc 서명 빌드이며 Apple 공증 배포본이 아니다.
