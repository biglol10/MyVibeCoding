#!/usr/bin/env python3
"""Generate the small native Xcode project without a machine-wide generator dependency."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
objects = {}
def identifier(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(name, value):
    key = identifier(name)
    objects[key] = value
    return key
def quote(value): return json.dumps(str(value))
def array(items): return '(' + ', '.join(items) + ',)'

source_refs, source_builds = [], []
for path in sorted((root / 'Sources').rglob('*.swift')):
    relative = str(path.relative_to(root))
    ref = add(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(relative)}; sourceTree = SOURCE_ROOT;')
    source_refs.append(ref)
    source_builds.append(add(relative + ':build', f'isa = PBXBuildFile; fileRef = {ref};'))
resources = []
resource_refs = []
for path, filetype in [('Sources/App/Resources/Editor', 'folder'), ('Sources/App/Resources/AppIcon.icns', 'image.icns'), ('Sources/App/Resources/ThirdPartyNotices.txt', 'text')]:
    ref = add(path, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = {quote(path)}; sourceTree = SOURCE_ROOT;')
    resource_refs.append(ref)
    resources.append(add(path + ':build', f'isa = PBXBuildFile; fileRef = {ref};'))
product = add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = MyMarkdownViewer.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; name = Products; children = {array([product])}; sourceTree = "<group>";')
group = add('mainGroup', f'isa = PBXGroup; children = {array(source_refs + resource_refs + [products])}; sourceTree = "<group>";')
sources_phase = add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(source_builds)}; runOnlyForDeploymentPostprocessing = 0;')
resources_phase = add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resources)}; runOnlyForDeploymentPostprocessing = 0;')
frameworks_phase = add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs = [], []
for configuration in ['Debug', 'Release']:
    optimization = '-Onone' if configuration == 'Debug' else '-O'
    project_configs.append(add('project:' + configuration, f'isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{ MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; }};'))
    target_configs.append(add('target:' + configuration, f'''isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{
        PRODUCT_NAME = MyMarkdownViewer; PRODUCT_BUNDLE_IDENTIFIER = com.personal.MyMarkdownViewer;
        INFOPLIST_FILE = Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO;
        CODE_SIGN_ENTITLEMENTS = Resources/MyMarkdownViewer.entitlements;
        ENABLE_APP_SANDBOX = YES; ENABLE_HARDENED_RUNTIME = YES;
        CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-";
        SWIFT_OPTIMIZATION_LEVEL = "{optimization}"; SWIFT_STRICT_CONCURRENCY = complete;
        LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
        COMBINE_HIDPI_IMAGES = YES; SWIFT_EMIT_LOC_STRINGS = NO;
    }};'''))
pc = add('projectConfigs', f'isa = XCConfigurationList; buildConfigurations = {array(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tc = add('targetConfigs', f'isa = XCConfigurationList; buildConfigurations = {array(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = add('appTarget', f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = {array([sources_phase, frameworks_phase, resources_phase])}; buildRules = (); dependencies = (); name = MyMarkdownViewer; productName = MyMarkdownViewer; productReference = {product}; productType = "com.apple.product-type.application";')
project = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ko; hasScannedForEncodings = 0; knownRegions = (ko,en,Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([target])};')
directory = root / 'MyMarkdownViewer.xcodeproj'
directory.mkdir(exist_ok=True)
(directory / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(f'{key} = {{ {value} }};' for key, value in objects.items()) + f'\n}}; rootObject = {project}; }}\n')
scheme_dir = directory / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="MyMarkdownViewer.app" BlueprintName="MyMarkdownViewer" ReferencedContainer="container:MyMarkdownViewer.xcodeproj"/>'
(scheme_dir / 'MyMarkdownViewer.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated MyMarkdownViewer.xcodeproj')
