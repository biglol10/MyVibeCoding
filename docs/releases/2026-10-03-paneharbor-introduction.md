# PaneHarbor 신규 추가와 배포 검증 — 2026년 10월 3일

PaneHarbor를 MyVibeCoding의 별도 macOS 파일 관리자 앱으로 추가했다. MyMacFinder의 설치 앱·설정·데이터를 교체하거나 이전하지 않는다. 원본에서 개발 소스·테스트·빌드 스크립트·VS Code 확장을 선별해 옮겼고, 원본의 빌드 캐시·개인 QA 로그·화면 기록은 포함하지 않았다.

## 다운로드와 설치

- [Mac 개인 설치 ZIP](../../downloads/PaneHarbor/PaneHarbor-personal-mac.zip) · [SHA-256](../../downloads/PaneHarbor/PaneHarbor-personal-mac.zip.sha256)
- [VS Code 확장 0.1.1](../../downloads/PaneHarbor/paneharbor-open-0.1.1.vsix) · [SHA-256](../../downloads/PaneHarbor/paneharbor-open-0.1.1.vsix.sha256)
- [GitHub 배포 페이지](https://github.com/biglol10/MyVibeCoding/releases/tag/paneharbor-2026-10-03)

ZIP을 풀고 `Install PaneHarbor.command`를 실행하면 `/Applications/PaneHarbor.app`에 설치한다. 기존 동일 경로의 앱은 `.saved-bundle`로 백업하며, `/Applications/PaneHarbor Preview.app`은 교체하지 않는다. 실행 중인 PaneHarbor가 있으면 설치 스크립트가 중단한다. 이 ZIP은 Apple Silicon(arm64) 전용의 ad-hoc 서명 로컬 베타로, Developer ID 공증 또는 App Store 배포본이 아니다. 처음 실행할 때 폴더 접근을 직접 허용해야 한다. VS Code 확장은 기본적으로 `/Applications/PaneHarbor.app`을 연다. Preview 앱을 쓴다면 `paneharbor.applicationPath`를 별도로 설정한다.

## 이번 저장소에서 확인한 사항

- Swift 테스트 701개를 warnings-as-errors 설정으로 통과했고, VS Code 확장 테스트 4개를 통과했다.
- Release 앱과 개인 설치 ZIP을 새로 만들고, ZIP 무결성·앱 번들 ID·arm64 실행 파일·엄격한 코드 서명을 확인했다. 앱 서명에 샌드박스, 사용자 선택 파일 읽기/쓰기, 앱 범위 북마크, 네트워크 클라이언트 권한이 남아 있는지 확인했다.
- VSIX의 확장 코드·설정·안내 문서가 옮긴 소스와 일치하는지 확인했다.
- 설치 스크립트가 앱을 다시 서명해 샌드박스 권한을 잃지 않도록 수정했다. 이 작업에서 설치 스크립트 실행이나 `/Applications` 교체는 하지 않았다.

원본 프로젝트의 별도 로컬 QA 기록은 이번 저장소의 새 실기 UI 검증을 뜻하지 않는다. 다른 Mac에서의 설치·실행, Intel 실기, 외부 NAS, 드래그 대상 전달, App Store 제출·판매는 이번 작업으로 검증되지 않았다. 이 저장소의 공개 다운로드 링크는 푸시와 GitHub 자산 게시 후 별도로 확인한다.
