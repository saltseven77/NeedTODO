"""Idempotent Xcode extension wiring; only stdlib is needed on Windows/macOS."""
from pathlib import Path
p = Path(__file__).resolve().parents[1] / 'ios/Runner.xcodeproj/project.pbxproj'
s = p.read_text(encoding='utf-8')
if 'NeedTODOWidget.appex' in s:
    raise SystemExit('Widget target already configured')
entries = '''
/* NeedTODO WidgetKit extension */
AA0000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NeedTODOWidget.swift; sourceTree = "<group>";};
AA0000000000000000000002 = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = NeedTODOWidget.appex; sourceTree = BUILT_PRODUCTS_DIR;};
AA0000000000000000000003 = {isa = PBXBuildFile; fileRef = AA0000000000000000000001;};
AA0000000000000000000004 = {isa = PBXBuildFile; fileRef = AA0000000000000000000002; settings = {ATTRIBUTES = (RemoveHeadersOnCopy,);};};
AA0000000000000000000005 = {isa = PBXGroup; children = (AA0000000000000000000001,); path = NeedTODOWidget; sourceTree = "<group>";};
AA0000000000000000000006 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (AA0000000000000000000003,); runOnlyForDeploymentPostprocessing = 0;};
AA0000000000000000000007 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
AA0000000000000000000008 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
AA0000000000000000000009 = {isa = PBXNativeTarget; buildConfigurationList = AA000000000000000000000A; buildPhases = (AA0000000000000000000006, AA0000000000000000000007, AA0000000000000000000008,); buildRules = (); dependencies = (); name = NeedTODOWidget; productName = NeedTODOWidget; productReference = AA0000000000000000000002; productType = "com.apple.product-type.app-extension";};
AA000000000000000000000A = {isa = XCConfigurationList; buildConfigurations = (AA000000000000000000000B, AA000000000000000000000C, AA000000000000000000000D,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
AA000000000000000000000E = {isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = (AA0000000000000000000004,); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;};
AA000000000000000000000F = {isa = PBXContainerItemProxy; containerPortal = 97C146E61CF9000F007C117D; proxyType = 1; remoteGlobalIDString = AA0000000000000000000009; remoteInfo = NeedTODOWidget;};
AA0000000000000000000010 = {isa = PBXTargetDependency; target = AA0000000000000000000009; targetProxy = AA000000000000000000000F;};
'''
for i, name in [('B','Debug'),('C','Release'),('D','Profile')]:
    entries += f'''AA000000000000000000000{i} = {{isa = XCBuildConfiguration; buildSettings = {{APPLICATION_EXTENSION_API_ONLY = YES; CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS = NeedTODOWidget/NeedTODOWidget.entitlements; INFOPLIST_FILE = NeedTODOWidget/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 17.0; PRODUCT_BUNDLE_IDENTIFIER = com.needtodo.needtodo.widget; PRODUCT_NAME = "$(TARGET_NAME)"; SDKROOT = iphoneos; SKIP_INSTALL = YES; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2"; LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks");}}; name = {name};}};\n'''
s = s.replace('objects = {', 'objects = {\n' + entries, 1)
s = s.replace('9740EEB11CF90186004384FC /* Flutter */,', 'AA0000000000000000000005,\n\t\t\t\t9740EEB11CF90186004384FC /* Flutter */,', 1)
s = s.replace('97C146EE1CF9000F007C117D /* Runner.app */,', 'AA0000000000000000000002,\n\t\t\t\t97C146EE1CF9000F007C117D /* Runner.app */,', 1)
s = s.replace('3B06AD1E1E4923F5004D2608 /* Thin Binary */,', 'AA000000000000000000000E,\n\t\t\t\t3B06AD1E1E4923F5004D2608 /* Thin Binary */,', 1)
start = s.index('97C146ED1CF9000F007C117D /* Runner */ = {')
end = s.index('/* End PBXNativeTarget section */', start)
target = s[start:end].replace('dependencies = (', 'dependencies = (\n\t\t\t\tAA0000000000000000000010,', 1)
s = s[:start] + target + s[end:]
s = s.replace('targets = (', 'targets = (\n\t\t\t\tAA0000000000000000000009,', 1)
s = s.replace('INFOPLIST_FILE = Runner/Info.plist;', 'INFOPLIST_FILE = Runner/Info.plist;\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;')
p.write_text(s, encoding='utf-8')
print('WidgetKit target embedded in Runner')
