# Open in PaneHarbor (local PoC)

macOS VS Code Explorer에서 로컬 파일/폴더를 우클릭 → **Open in PaneHarbor**.
폴더는 이동하고 파일은 상위 폴더에서 선택합니다. 우클릭한 항목 하나가 대상이며, 여러 선택 항목을 일괄 실행하지 않습니다.

앱 설치 후 로컬 VSIX를 만들고 설치합니다:

```sh
cd integrations/vscode
npm test
npx @vscode/vsce package --allow-missing-repository --out ../../build/paneharbor-open-0.1.1.vsix
code --install-extension ../../build/paneharbor-open-0.1.1.vsix --force
```

`PaneHarbor: Application Path` 설정 기본값은 `/Applications/PaneHarbor.app`입니다.
`extensionKind: ui`로 로컬 Mac에서 실행하며 원격/가상 URI는 거부합니다. 셸 없이 `/usr/bin/open`에 개별 인수를 전달합니다.
폴더의 기본 파일 열기 인수를 먼저 전달해 macOS에 폴더 열기 의도를 전달하고, 뒤이어 `paneharbor://open?path=<encodeURIComponent(path)>`로 대상을 전달합니다. 공백/한글/특수문자를 보존합니다. 시스템 파일 접근 권한은 macOS가 관리합니다.
이 확장은 파일을 수정하거나 파일 내용을 읽지 않습니다.

VS Code 공식 [Contribution Points](https://code.visualstudio.com/api/references/contribution-points#contributes.menus)의 `explorer/context`, `when`, `group@order`를 사용합니다.
`navigation@21`은 기본 Reveal in Finder 바로 다음 배치를 시도합니다. 다른 확장/VS Code 버전에 따라 위치는 달라질 수 있습니다.

제거: `code --uninstall-extension biglol-local.paneharbor-open`.
