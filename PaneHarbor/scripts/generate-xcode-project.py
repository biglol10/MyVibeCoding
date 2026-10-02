#!/usr/bin/env python3
"""Generate the independent macOS application target from owned Swift sources."""
from pathlib import Path
import hashlib, json
r = Path(__file__).resolve().parents[1]
def uid(label): return hashlib.sha256(label.encode()).hexdigest()[:24].upper()
def q(value): return json.dumps(str(value))
objects = []
def obj(label, body):
    key = uid(label); objects.append(f'{key} = {{ {body} }};'); return key
source_refs = []; source_builds = []; resource_refs = []; resource_builds = []
for path in sorted((r/'Sources/PaneHarbor').rglob('*.swift')):
    rel = path.relative_to(r)
    ref = obj('ref:'+str(rel), f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
    source_refs.append(ref)
    source_builds.append(obj('build:'+str(rel), f'isa = PBXBuildFile; fileRef = {ref};'))
for name, kind in [('AppIcon.icns','image.icns'),('PrivacyInfo.xcprivacy','text.xml'),('ThirdPartyNotices.txt','text')]:
    rel = 'Sources/PaneHarbor/Resources/'+name
    ref = obj('ref:'+rel, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
    resource_refs.append(ref)
    resource_builds.append(obj('build:'+rel, f'isa = PBXBuildFile; fileRef = {ref};'))
localization_refs = []
for lang in ['en', 'ko']:
    rel = f'Sources/PaneHarbor/Resources/{lang}.lproj/Localizable.strings'
    localization_refs.append(obj('ref:'+rel, f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = {lang}; path = {q(rel)}; sourceTree = SOURCE_ROOT;'))
variant = obj('localization', f'isa = PBXVariantGroup; children = ({",".join(localization_refs)},); name = Localizable.strings; sourceTree = "<group>";')
resource_refs.append(variant)
resource_builds.append(obj('build:localization', f'isa = PBXBuildFile; fileRef = {variant};'))
def array(items): return '(' + ','.join(items) + (',' if items else '') + ')'
product = obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PaneHarbor.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj('products',f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
main = obj('main',f'isa = PBXGroup; children = {array(source_refs+resource_refs+[products])}; sourceTree = "<group>";')
package = obj('package','isa = XCLocalSwiftPackageReference; relativePath = Vendor/ZIPFoundation;')
zipdep = obj('zipdep',f'isa = XCSwiftPackageProductDependency; package = {package}; productName = ZIPFoundation;')
zipbuild = obj('zipbuild',f'isa = PBXBuildFile; productRef = {zipdep};')
sources = obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(source_builds)}; runOnlyForDeploymentPostprocessing = 0;')
resources = obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;')
frameworks = obj('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({zipbuild},); runOnlyForDeploymentPostprocessing = 0;')
project_configs=[]; target_configs=[]
for config in ['Debug','Release']:
    project_configs.append(obj('project:'+config,f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 15.0; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; }};'))
    target_configs.append(obj('target:'+config,f'''isa = XCBuildConfiguration; name = {config}; buildSettings = {{
    PRODUCT_NAME = PaneHarbor; PRODUCT_BUNDLE_IDENTIFIER = com.biglol.paneharbor.mac;
    INFOPLIST_FILE = Config/Info.plist; GENERATE_INFOPLIST_FILE = NO;
    CODE_SIGN_ENTITLEMENTS = Config/PaneHarbor.entitlements; CODE_SIGN_STYLE = Automatic;
    ENABLE_APP_SANDBOX = YES; ENABLE_HARDENED_RUNTIME = YES; ENABLE_USER_SELECTED_FILES = readwrite;
    ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;
    COMBINE_HIDPI_IMAGES = YES; SWIFT_TREAT_WARNINGS_AS_ERRORS = YES;
    SWIFT_OPTIMIZATION_LEVEL = {q('-Onone' if config=='Debug' else '-O')};
    ONLY_ACTIVE_ARCH = {'YES' if config=='Debug' else 'NO'};
    ARCHS = {q('$(ARCHS_STANDARD)')}; MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 1;
    LD_RUNPATH_SEARCH_PATHS = {q('$(inherited) @executable_path/../Frameworks')};
    }};'''))
pcfg=obj('project-configs',f'isa = XCConfigurationList; buildConfigurations = {array(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tcfg=obj('target-configs',f'isa = XCConfigurationList; buildConfigurations = {array(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {tcfg}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = PaneHarbor; productName = PaneHarbor; productReference = {product}; productType = "com.apple.product-type.application"; packageProductDependencies = ({zipdep},);')
project=obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; }}; buildConfigurationList = {pcfg}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,ko,Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},); packageReferences = ({package},);')
folder=r/'PaneHarbor.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {project}; }}\n')
scheme=folder/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="PaneHarbor.app" BlueprintName="PaneHarbor" ReferencedContainer="container:PaneHarbor.xcodeproj"/>'
(scheme/'PaneHarbor.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(folder)
