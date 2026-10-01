# MyMacFinder 2026년 10월 1일 변경 및 배포 검증

MyVibeCoding의 MyMacFinder에 원본 프로젝트의 최신 코드와 VS Code 확장을 반영했다. 새 Mac 설치 ZIP과 확장 설치 파일을 제공하며, 기존 원본 작업이나 사용자의 설치 앱·파일은 이 동기화 작업에서 변경하지 않았다.

## 변경 내용

- 새 폴더 생성·이름 변경 후 해당 행의 선택과 스크롤이 유지되도록 하고, 대량 목록의 파일 감시 갱신과 충돌하지 않게 했다.
- 빠르게 끝나는 작업에는 진행 표시를 숨기고, 0.5초 이상 계속되는 작업에만 표시한다. 실패 안내는 지연하지 않는다.
- ZIP의 DOS 수정 시간을 로컬 시간대로 처리하는 ZIPFoundation 패치를 라이선스와 함께 로컬 소스로 포함했다. ZIP 시간은 기존 DOS 형식의 2초 정밀도와 연도 범위 제한을 따른다.
- 앱이 파일·폴더 열기 요청, `mymacfinder://open` 링크, macOS 서비스를 받을 수 있게 했다. VS Code 파일 탐색기의 로컬 파일·폴더 우클릭 메뉴에는 별도 확장으로 **Open in MyMacFinder**를 제공한다. 모든 앱의 자체 우클릭 메뉴에 자동으로 나타나는 기능은 아니다.

## 다운로드와 설치

- [MyMacFinder 개인용 Mac 설치 ZIP](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacFinder/MyMacFinder-personal-mac.zip)
- [VS Code 확장 0.1.1 VSIX](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacFinder/mymacfinder-open-0.1.1.vsix)
- [이번 GitHub 배포 페이지](https://github.com/biglol10/MyVibeCoding/releases/tag/mymacfinder-2026-10-01)

Mac 앱을 설치한 뒤 필요하면 `code --install-extension mymacfinder-open-0.1.1.vsix --force`로 확장을 설치한다. 설치할 확장은 [사용 안내](../../MyMacFinder/integrations/vscode/README.md)를 참고한다. Mac 앱은 개인 사용용 ad-hoc 서명 빌드이며 Apple 공증 배포본이 아니다.

## 이번 동기화의 검증

- Swift warnings-as-errors 테스트 657개와 VS Code 확장 테스트 4개가 통과했다.
- Release 앱과 개인 설치 ZIP을 새로 만들었다. ZIP 무결성, 압축 해제 앱의 엄격한 코드 서명, 앱 실행 파일 일치를 확인했다.
- 앱 번들의 외부 폴더 열기 지원 플래그, `mymacfinder` URL 스킴, macOS 서비스 등록 정보를 확인했다.
- VSIX 무결성과 포함된 확장 코드·설정·안내 문서가 현재 소스와 일치함을 확인했다.
- 다운로드 파일의 SHA-256은 각각 `bcd88171d20a66d952c6f2ea2619f72157d37ae048d6767d229acff7436ea407`(Mac ZIP), `16f269fa8870ebdbeaff6000b1fae2d8b15dd5b7ea4c2aaa3654049bbb3488d1`(VSIX)이다.

원본 프로젝트에는 실제 설치 앱으로 외부 열기와 폴더·ZIP 동작을 점검한 기록이 있다. 이번 MyVibeCoding 동기화에서는 그 UI 조작을 재실행하지 않았으며, 실제 다른 Mac이나 다른 VS Code 구성에서의 동작을 확인했다고 주장하지 않는다. 원본의 개인 경로·화면 기록·로그는 배포 저장소에 복사하지 않았다.
