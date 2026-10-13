# PaneHarbor·MyMacFinder 2026년 10월 13일 갱신

두 원본의 제품 소스와 회귀 테스트를 MyVibeCoding에 반영하고 개인 설치 ZIP을 다시 만들었다. 앱 버전은 각각 0.1.0, VS Code 확장은 각각 0.1.1을 유지한다. 이번 ZIP은 Apple Silicon(arm64), macOS 15 이상용 ad-hoc 서명 개인 테스트 빌드이며 Developer ID 공증 또는 App Store 배포본이 아니다.

## 다운로드

- PaneHarbor: [Mac 설치 ZIP](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/PaneHarbor/PaneHarbor-personal-mac.zip) · [SHA-256](../../downloads/PaneHarbor/PaneHarbor-personal-mac.zip.sha256) · [VS Code 확장](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/PaneHarbor/paneharbor-open-0.1.1.vsix)
- MyMacFinder: [Mac 설치 ZIP](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacFinder/MyMacFinder-personal-mac.zip) · [SHA-256](../../downloads/MyMacFinder/MyMacFinder-personal-mac.zip.sha256) · [VS Code 확장](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacFinder/mymacfinder-open-0.1.1.vsix)
- [두 앱의 이번 배포 페이지](https://github.com/biglol10/MyVibeCoding/releases/tag/file-managers-2026-10-13)

압축을 풀어 같은 폴더의 설치 스크립트를 실행한다. 두 앱은 별도 설정·데이터를 사용하며 하나를 설치해도 다른 앱을 자동 제거하지 않는다. 기존 앱과 미저장 문서를 먼저 닫고 필요한 백업을 보관한 뒤 설치한다. PaneHarbor 설치기는 실행 중인 앱이 있으면 중단하고 같은 경로의 기존 앱을 백업한다. MyMacFinder 설치기는 기존 설치본을 교체한다.

## 반영한 변경

- 두 앱 모두 빈 폴더와 짧은 목록 아래 빈 영역에서 우클릭 메뉴를 제공한다. 메뉴 동작을 해당 패널에 전달하고 기존 선택을 유지한다. 빈 목록의 줄무늬 배경도 제거한다.
- MyMacFinder에는 Favorites 아래의 접이식 Folder Tree를 추가했다. 기본은 접힘이며 펼침 상태를 저장한다. 하위 폴더를 필요할 때 읽고 심볼릭 링크 순환·오래된 비동기 결과를 차단한다.
- MyMacFinder의 Locations / Go 메뉴에서 Connect to Server…(⌘K)로 SMB 연결을 요청한다. 주소에 사용자 이름·비밀번호·쿼리·fragment를 넣으면 거절한다. 인증·마운트는 macOS에 맡기며 앱은 비밀번호를 저장하지 않는다. 연결 후 Locations를 새로고침한다.
- 개발용 앱 번들의 자동 LaunchServices 등록 방지와 기존 배포 보완을 유지했다. PaneHarbor의 라이선스 고지와 샌드박스 권한을 포함하는 패키징, 공개 테스트의 예시 경로도 원본 복사 과정에서 되돌리지 않았다.

## 검증과 경계

- MyVibeCoding의 PaneHarbor Swift 테스트 704개, MyMacFinder coverage 포함 Swift 테스트 670개가 경고를 오류로 처리한 상태에서 통과했다. 두 VS Code 확장의 테스트는 각각 4개씩 통과했다.
- MyMacFinder 검증 스킬의 영향별 기준에 따라 파일 트리·SMB 주소·빈 폴더 메뉴 회귀 검사를 포함했다. 배포 대상에는 원본의 하네스 runner가 없어 동일한 제품 검사 명령을 직접 실행했다. 하네스 자체나 네이티브 에이전트 실행을 검증했다고 주장하지 않는다.
- 두 ZIP을 새로 빌드하고 압축 무결성·앱 버전·arm64 실행 파일·코드 서명·실행 파일 일치를 검사했다. PaneHarbor의 샌드박스 권한과 라이선스 고지도 확인했다. VSIX는 기존 버전을 유지하며 포함 코드가 현재 소스와 일치하는지 확인했다.

원본의 개인 작업·실행 기록·하네스 구성과 다른 앱의 미완료 변경은 이번 커밋에 포함하지 않았다. 이 작업은 소스·배포 파일·문서 갱신이며 `/Applications` 설치본, Dock, 사용자 설정·문서·SMB 서버·설치된 확장은 변경하지 않았다. AppKit 회귀 테스트는 실제 사람의 전체 GUI 사용이나 실제 NAS 인증·마운트를 증명하지 않는다. 다른 Mac·Intel 실기 검증도 이번에는 수행하지 않았다.
