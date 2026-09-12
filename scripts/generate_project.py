#!/usr/bin/env python3
"""Generate the dependency-free Xcode project. Run after adding Swift/resources files."""
from pathlib import Path
import hashlib
ROOT = Path(__file__).resolve().parent.parent
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, body):
    objects[uid(name)] = body
    return uid(name)
def quoted(text): return '"' + str(text).replace('"', '\\"') + '"'
def array(values): return '(' + ', '.join(values) + (',' if values else '') + ')'
def ref(path, kind):
    return add(path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(path)}; sourceTree = SOURCE_ROOT;')
def build_file(path, kind):
    fid = ref(path, kind)
    return add('build:' + path, f'isa = PBXBuildFile; fileRef = {fid};')
swift = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'PenPhoto').glob('*.swift'))
tests = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'PenPhotoTests').glob('*.swift'))
ui_tests = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'PenPhotoUITests').glob('*.swift'))
ui_sources = [build_file(p, 'sourcecode.swift') for p in ui_tests]
resources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'PenPhoto/Resources').iterdir() if p.is_file() or p.suffix == '.xcassets')
sources = [build_file(p, 'sourcecode.swift') for p in swift]
test_sources = [build_file(p, 'sourcecode.swift') for p in tests]
fixture_files = [str(p.relative_to(ROOT)) for p in (ROOT / 'PenPhotoTests/Fixtures').glob('*.png')]
fixture_builds = [build_file(p, 'image.png') for p in fixture_files]
resource_files = [build_file(p, 'folder.assetcatalog' if p.endswith('.xcassets') else 'file') for p in resources]
info = ref('PenPhoto/Info.plist', 'text.plist.xml')
signing = ref('Config/Signing.xcconfig', 'text.xcconfig')
app_product = add('app_product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = PenPhoto.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add('test_product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = PenPhotoTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
def phase(name, kind, files): return add(name, f'isa = {kind}; buildActionMask = 2147483647; files = {array(files)}; runOnlyForDeploymentPostprocessing = 0;')
app_phases = [phase('sources', 'PBXSourcesBuildPhase', sources), phase('frameworks', 'PBXFrameworksBuildPhase', []), phase('resources', 'PBXResourcesBuildPhase', resource_files)]
test_phases = [phase('test_sources', 'PBXSourcesBuildPhase', test_sources), phase('test_frameworks', 'PBXFrameworksBuildPhase', []), phase('test_resources', 'PBXResourcesBuildPhase', fixture_builds)]
def config_list(name, settings):
    configs = []
    for mode in ['Debug', 'Release']:
        values = dict(settings)
        values['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if mode == 'Debug' else '-O'
        values['DEBUG_INFORMATION_FORMAT'] = 'dwarf' if mode == 'Debug' else 'dwarf-with-dsym'
        if mode == 'Debug':
            values['ENABLE_TESTABILITY'] = 'YES'
            values['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) DEBUG'
        body = ' '.join(f'{k} = {quoted(v)};' for k, v in values.items())
        base = f'baseConfigurationReference = {signing}; ' if name == 'project' else ''
        configs.append(add(name + mode, f'isa = XCBuildConfiguration; {base}buildSettings = {{ {body} }}; name = {mode};'))
    return add(name + 'configs', f'isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project_config = config_list('project', {'SDKROOT':'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET':'17.0', 'SWIFT_VERSION':'5.0', 'CLANG_ENABLE_MODULES':'YES', 'TARGETED_DEVICE_FAMILY':'1', 'SWIFT_STRICT_CONCURRENCY':'minimal', 'CODE_SIGN_STYLE':'Automatic'})
app_config = config_list('app', {'PRODUCT_NAME':'$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER':'$(PENPHOTO_BUNDLE_IDENTIFIER)', 'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon', 'INFOPLIST_FILE':'PenPhoto/Info.plist', 'GENERATE_INFOPLIST_FILE':'NO', 'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST':'NO', 'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks'})
test_config = config_list('test', {'PRODUCT_NAME':'$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER':'$(PENPHOTO_BUNDLE_IDENTIFIER).tests', 'GENERATE_INFOPLIST_FILE':'YES', 'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/PenPhoto.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PenPhoto', 'BUNDLE_LOADER':'$(TEST_HOST)', 'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @loader_path/Frameworks'})
app_target = add('app_target', f'isa = PBXNativeTarget; buildConfigurationList = {app_config}; buildPhases = {array(app_phases)}; buildRules = (); dependencies = (); name = PenPhoto; productName = PenPhoto; productReference = {app_product}; productType = "com.apple.product-type.application";')
proxy = add('proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = PenPhoto;')
dep = add('dependency', f'isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};')
test_target = add('test_target', f'isa = PBXNativeTarget; buildConfigurationList = {test_config}; buildPhases = {array(test_phases)}; buildRules = (); dependencies = ({dep},); name = PenPhotoTests; productName = PenPhotoTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";')
products = add('products', f'isa = PBXGroup; children = ({app_product}, {test_product},); name = Products; sourceTree = "<group>";')
ui_product = add('ui_product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = PenPhotoUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
ui_config = config_list('ui', {'PRODUCT_NAME':'$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER':'$(PENPHOTO_BUNDLE_IDENTIFIER).uitests', 'GENERATE_INFOPLIST_FILE':'YES', 'TEST_TARGET_NAME':'PenPhoto'})
ui_phases = [phase('ui_sources', 'PBXSourcesBuildPhase', ui_sources), phase('ui_frameworks', 'PBXFrameworksBuildPhase', [])]
ui_target = add('ui_target', f'isa = PBXNativeTarget; buildConfigurationList = {ui_config}; buildPhases = {array(ui_phases)}; buildRules = (); dependencies = ({dep},); name = PenPhotoUITests; productName = PenPhotoUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";')
main = add('main', f'isa = PBXGroup; children = {array([uid(p) for p in swift + tests + ui_tests + resources + fixture_files] + [info, signing, products])}; sourceTree = "<group>";')
project = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ja; knownRegions = (ja, en, Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({app_target}, {test_target}, {ui_target},);')
folder = ROOT / 'PenPhoto.xcodeproj'; folder.mkdir(exist_ok=True)
(folder / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(f'{key} = {{ {body} }};' for key, body in objects.items()) + f'\n}}; rootObject = {project}; }}\n')
scheme = folder / 'xcshareddata/xcschemes'; scheme.mkdir(parents=True, exist_ok=True)
app_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="PenPhoto.app" BlueprintName="PenPhoto" ReferencedContainer="container:PenPhoto.xcodeproj"/>'
test_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="PenPhotoTests.xctest" BlueprintName="PenPhotoTests" ReferencedContainer="container:PenPhoto.xcodeproj"/>'
ui_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="PenPhotoUITests.xctest" BlueprintName="PenPhotoUITests" ReferencedContainer="container:PenPhoto.xcodeproj"/>'
(scheme / 'PenPhoto.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference><TestableReference skipped="NO">{ui_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated PenPhoto.xcodeproj')
