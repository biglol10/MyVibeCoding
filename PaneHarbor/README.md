# PaneHarbor

PaneHarbor는 두 창과 탭으로 파일을 정리하는 macOS 15 이상용 로컬 베타입니다. MyMacFinder와 별도 앱으로, 번들 ID·설정·데이터를 공유하지 않습니다. App Store 제출·판매 또는 공증된 공개 배포 상태가 아닙니다.

## 다운로드와 시작

- [Mac 개인 설치 ZIP](../downloads/PaneHarbor/PaneHarbor-personal-mac.zip) · [SHA-256](../downloads/PaneHarbor/PaneHarbor-personal-mac.zip.sha256)
- [VS Code 확장 VSIX](../downloads/PaneHarbor/paneharbor-open-0.1.1.vsix) · [SHA-256](../downloads/PaneHarbor/paneharbor-open-0.1.1.vsix.sha256)
- [이번 추가의 검증 범위와 주의사항](../docs/releases/2026-10-03-paneharbor-introduction.md)

개인 설치 ZIP을 풀어 `Install PaneHarbor.command`를 실행하면 `/Applications/PaneHarbor.app`에 복사합니다. 기존 `PaneHarbor.app`은 같은 폴더의 `.saved-bundle`로 백업합니다. 별도로 설치된 `PaneHarbor Preview.app`은 교체하지 않습니다. 설치 앱은 ad-hoc 서명이며 Developer ID 공증본이 아닙니다. 설치 스크립트는 서명을 검사한 뒤 다운로드 격리 속성을 제거합니다. 출처를 신뢰하는 본인 Mac에서만 사용하세요.

처음 실행하면 **폴더 선택…**으로 작업할 폴더를 직접 허용하세요. 접근 권한은 앱의 개인정보 및 접근 설정에서 회수할 수 있습니다. VS Code 확장은 로컬 macOS에서 파일/폴더 우클릭 → **Open in PaneHarbor**를 제공합니다. 기본 앱 경로는 `/Applications/PaneHarbor.app`이고, Preview 앱을 계속 쓴다면 `paneharbor.applicationPath`를 직접 설정해야 합니다. VSIX는 VS Code의 **확장: VSIX에서 설치…**로 설치할 수 있습니다.

## 기능과 제한

목록·아이콘·썸네일, 폴더 트리, 두 창·탭, 새 폴더/파일과 이름 변경, 일괄 이름 변경, 복사·이동·휴지통·Undo, ZIP, 검색, SMB, macOS 서비스, 한국어/영어 및 Mac/Windows 단축키를 제공합니다. 홈·데스크탑·문서·다운로드·응용 프로그램 바로가기는 클릭할 때 필요한 폴더 접근을 요청합니다. 권한 선택을 취소하면 현재 위치가 유지됩니다.

내용 검색은 10 MiB 이하 UTF-8/UTF-16 일반 텍스트에 한정됩니다. PDF/Office·바이너리·심볼릭 링크·ZIP 내부 검색은 지원하지 않습니다. 외부 NAS, Intel 실기, 드래그 대상 전달은 충분히 검증되지 않았습니다. 원격 서버·동기화·클라우드 전송 전문 도구의 완전한 대체를 약속하지 않습니다.

## 개발

```bash
swift test -j 4 -Xswiftc -warnings-as-errors
scripts/package_personal.sh
```

`scripts/archive-local.sh`는 Xcode 아카이브용입니다. App Store 배포에는 실제 소유자 팀·Mac App Store 서명/프로비저닝, App Store Connect 정보와 별도 검증이 필요합니다. 로컬 빌드나 개인 설치 ZIP은 그 증거가 아닙니다. VS Code 확장은 [`integrations/vscode`](integrations/vscode)를 확인하세요.

ZIPFoundation 0.9.20 MIT 고지는 앱의 `ThirdPartyNotices.txt`에 포함됩니다. [벤더 출처와 로컬 시간 수정](Vendor/ZIPFoundation/UPSTREAM.md)을 확인하세요.
