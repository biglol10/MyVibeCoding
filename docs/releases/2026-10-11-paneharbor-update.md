# PaneHarbor 2026년 10월 11일 배포 갱신

PaneHarbor 원본과 MyVibeCoding을 비교하고, 개발 빌드가 macOS 앱 목록에 자동 등록되지 않도록 한 변경을 반영했다. 표준 설치 앱 이름과 경로는 `PaneHarbor.app`, `/Applications/PaneHarbor.app`으로 안내한다. 기능 소스·리소스·앱 설정·VS Code 확장은 이전 배포와 동일하며 앱 버전은 0.1.0, 확장 버전은 0.1.1을 유지한다.

## 다운로드

- [Mac 개인 설치 ZIP](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/PaneHarbor/PaneHarbor-personal-mac.zip) · [SHA-256](../../downloads/PaneHarbor/PaneHarbor-personal-mac.zip.sha256)
- [VS Code 확장](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/PaneHarbor/paneharbor-open-0.1.1.vsix) · [SHA-256](../../downloads/PaneHarbor/paneharbor-open-0.1.1.vsix.sha256)
- [이번 GitHub 배포 페이지](https://github.com/biglol10/MyVibeCoding/releases/tag/paneharbor-2026-10-11)

ZIP은 Apple Silicon(arm64), macOS 15 이상용 개인 테스트 빌드다. 압축을 풀고 `Install PaneHarbor.command`를 실행하면 표준 경로에 설치하며, 같은 경로의 기존 앱은 백업한다. 과거 Preview 경로를 지정한 VS Code 설정은 `paneharbor.applicationPath`를 현재 설치 경로로 바꿔야 한다. 설치 스크립트는 실행 중인 PaneHarbor가 있으면 중단한다.

## 변경과 검증 범위

- `build_app.sh`의 개발 앱 자동 등록을 제거했다. 실제 설치 스크립트의 설치본 등록은 유지한다. 프로젝트의 `build`·`dist` 폴더를 Spotlight 검색 개인정보 보호에서 제외하면 개발·백업 사본의 앱 검색 노출을 줄일 수 있다.
- MyVibeCoding에서 Swift warnings-as-errors 테스트 701개와 VS Code 확장 테스트 4개가 통과했다. 확장 설치 파일의 코드·설정·안내 문서가 현재 소스와 일치하는지 확인했다.
- 개인 설치 ZIP을 다시 만들고 ZIP 무결성, 앱 버전·번들 ID, arm64 실행 파일, 코드 서명, 샌드박스 권한, ZIPFoundation 라이선스 고지를 검사했다.

이번 작업은 소스·배포 파일·문서 갱신이다. 설치 앱이나 사용자 설정을 교체하지 않았고, 실제 앱 UI·다른 Mac에서의 설치·Intel 실기·외부 NAS를 새로 검증하지 않았다. 이 설치 ZIP은 ad-hoc 서명 로컬 베타로 Developer ID 공증 또는 App Store 제출·판매를 뜻하지 않는다.
