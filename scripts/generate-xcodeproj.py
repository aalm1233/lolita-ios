#!/usr/bin/env python3
"""Generate Lolita.xcodeproj in JSON format for Xcode 16+."""
import os, sys, hashlib, json
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SOURCES_DIR = PROJECT_ROOT / "Sources"
XCODEPROJ_DIR = PROJECT_ROOT / "Lolita.xcodeproj"
PBXPROJ = XCODEPROJ_DIR / "project.pbxproj"

def gen_uuid(seed=""):
    return hashlib.md5((seed + str(os.urandom(8).hex())).encode()).hexdigest()[:24].upper()

swift_files = sorted([str(f.relative_to(PROJECT_ROOT)) for f in SOURCES_DIR.rglob("*.swift") if f.name != "Info.plist"])
has_plist = (SOURCES_DIR / "Info.plist").exists()

# Generate stable UUIDs
uids = {}
def uid(key):
    if key not in uids: uids[key] = gen_uuid(key)
    return uids[key]

objects = {}

# --- File references for Swift sources ---
for f in swift_files:
    objects[uid("file_" + f)] = {
        "isa": "PBXFileReference",
        "lastKnownFileType": "sourcecode.swift",
        "path": Path(f).name,
        "sourceTree": "<group>"
    }

# Info.plist (referenced only via INFOPLIST_FILE build setting, not as resource)
if has_plist:
    objects[uid("file_Sources/Info.plist")] = {
        "isa": "PBXFileReference",
        "lastKnownFileType": "text.plist.xml",
        "path": "Info.plist",
        "sourceTree": "<group>"
    }

# Product
objects[uid("product")] = {
    "isa": "PBXFileReference",
    "explicitFileType": "wrapper.application",
    "includeInIndex": "0",
    "path": "Lolita.app",
    "sourceTree": "BUILT_PRODUCTS_DIR"
}

# --- Build files ---
for f in swift_files:
    objects[uid("build_" + f)] = {
        "isa": "PBXBuildFile",
        "fileRef": uid("file_" + f)
    }
# Info.plist is handled via INFOPLIST_FILE build setting, NOT as a resource

# --- Groups ---
# Subgroups for directories
dirs = sorted(set(Path(f).parent.as_posix() for f in swift_files if Path(f).parent != Path("Sources")))
for d in dirs:
    group_files = [uid("file_" + f) for f in swift_files if Path(f).parent.as_posix() == d]
    objects[uid("group_" + d)] = {
        "isa": "PBXGroup",
        "children": group_files,
        "name": Path(d).name,
        "path": d.replace("Sources/", ""),
        "sourceTree": "<group>"
    }

# Sources group
sources_children = []
for d in dirs:
    sources_children.append(uid("group_" + d))
for f in swift_files:
    if Path(f).parent == Path("Sources"):
        sources_children.append(uid("file_" + f))
if has_plist:
    sources_children.append(uid("file_Sources/Info.plist"))

objects[uid("group_Sources")] = {
    "isa": "PBXGroup",
    "children": sources_children,
    "name": "Sources",
    "path": "Sources",
    "sourceTree": "<group>"
}

# Products group
objects[uid("group_Products")] = {
    "isa": "PBXGroup",
    "children": [uid("product")],
    "name": "Products",
    "sourceTree": "<group>"
}

# Main group
objects[uid("group_main")] = {
    "isa": "PBXGroup",
    "children": [uid("group_Sources"), uid("group_Products")],
    "sourceTree": "<group>"
}

# --- Build phases ---
sources_bp = uid("sources_bp")
objects[sources_bp] = {
    "isa": "PBXSourcesBuildPhase",
    "buildActionMask": "2147483647",
    "files": [uid("build_" + f) for f in swift_files],
    "runOnlyForDeploymentPostprocessing": "0"
}

resources_bp = uid("resources_bp")
objects[resources_bp] = {
    "isa": "PBXResourcesBuildPhase",
    "buildActionMask": "2147483647",
    "files": [],
    "runOnlyForDeploymentPostprocessing": "0"
}

frameworks_bp = uid("frameworks_bp")
objects[frameworks_bp] = {
    "isa": "PBXFrameworksBuildPhase",
    "buildActionMask": "2147483647",
    "files": [],
    "runOnlyForDeploymentPostprocessing": "0"
}

# --- SPM remote package references ---
gr_ref = uid("spm_grdb_ref")
objects[gr_ref] = {
    "isa": "XCRemoteSwiftPackageReference",
    "repositoryURL": "https://github.com/groue/GRDB.swift.git",
    "requirement": {
        "kind": "upToNextMajorVersion",
        "minimumVersion": "6.29.0"
    }
}
kf_ref = uid("spm_kf_ref")
objects[kf_ref] = {
    "isa": "XCRemoteSwiftPackageReference",
    "repositoryURL": "https://github.com/onevcat/Kingfisher.git",
    "requirement": {
        "kind": "upToNextMajorVersion",
        "minimumVersion": "8.0.0"
    }
}

# SPM package product dependencies (must reference remote refs above)
gr_pkg = uid("spm_grdb_pkg")
objects[gr_pkg] = {
    "isa": "XCSwiftPackageProductDependency",
    "package": gr_ref,
    "productName": "GRDB"
}
kf_pkg = uid("spm_kf_pkg")
objects[kf_pkg] = {
    "isa": "XCSwiftPackageProductDependency",
    "package": kf_ref,
    "productName": "Kingfisher"
}

# --- Build configs ---
debug_cfg = uid("config_debug")
objects[debug_cfg] = {
    "isa": "XCBuildConfiguration",
    "buildSettings": {
        "ARCHS": "$(ARCHS_STANDARD)",
        "CLANG_ENABLE_MODULES": "YES",
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MACOSX_DEPLOYMENT_TARGET": "12.0",
        "ONLY_ACTIVE_ARCH": "YES",
        "SDKROOT": "auto",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "SWIFT_VERSION": "6.0"
    },
    "name": "Debug"
}

release_cfg = uid("config_release")
objects[release_cfg] = {
    "isa": "XCBuildConfiguration",
    "buildSettings": {
        "ARCHS": "$(ARCHS_STANDARD)",
        "CLANG_ENABLE_MODULES": "YES",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MACOSX_DEPLOYMENT_TARGET": "12.0",
        "SDKROOT": "auto",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
        "SWIFT_VERSION": "6.0"
    },
    "name": "Release"
}

t_debug_cfg = uid("config_target_debug")
objects[t_debug_cfg] = {
    "isa": "XCBuildConfiguration",
    "buildSettings": {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "M5MJ2R5MT7",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Sources/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.lolita.ios",
        "PRODUCT_NAME": "Lolita",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1,2"
    },
    "name": "Debug"
}

t_release_cfg = uid("config_target_release")
objects[t_release_cfg] = {
    "isa": "XCBuildConfiguration",
    "buildSettings": {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "M5MJ2R5MT7",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Sources/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.lolita.ios",
        "PRODUCT_NAME": "Lolita",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1,2"
    },
    "name": "Release"
}

# Configuration lists
cfg_list_proj = uid("config_list_proj")
objects[cfg_list_proj] = {
    "isa": "XCConfigurationList",
    "buildConfigurations": [debug_cfg, release_cfg],
    "defaultConfigurationIsVisible": "0",
    "defaultConfigurationName": "Release"
}

cfg_list_target = uid("config_list_target")
objects[cfg_list_target] = {
    "isa": "XCConfigurationList",
    "buildConfigurations": [t_debug_cfg, t_release_cfg],
    "defaultConfigurationIsVisible": "0",
    "defaultConfigurationName": "Release"
}

# SPM target dependencies (must be PBXTargetDependency wrapping the package)
gr_tdep = uid("tgt_dep_grdb")
objects[gr_tdep] = {
    "isa": "PBXTargetDependency",
    "productRef": gr_pkg
}
kf_tdep = uid("tgt_dep_kf")
objects[kf_tdep] = {
    "isa": "PBXTargetDependency",
    "productRef": kf_pkg
}

# --- Native target ---
target_id = uid("target")
objects[target_id] = {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": cfg_list_target,
    "buildPhases": [sources_bp, resources_bp, frameworks_bp],
    "buildRules": [],
    "dependencies": [gr_tdep, kf_tdep],
    "packageProductDependencies": [gr_pkg, kf_pkg],
    "name": "Lolita",
    "productName": "Lolita",
    "productReference": uid("product"),
    "productType": "com.apple.product-type.application"
}

# --- Project ---
project_id = uid("project")
objects[project_id] = {
    "isa": "PBXProject",
    "attributes": {
        "BuildIndependentTargetsInParallel": "1",
        "LastSwiftUpdateCheck": "2600",
        "LastUpgradeCheck": "2600"
    },
    "buildConfigurationList": cfg_list_proj,
    "compatibilityVersion": "Xcode 16.0",
    "developmentRegion": "zh-Hans",
    "hasScannedForEncodings": "0",
    "knownRegions": ["en", "zh-Hans"],
    "mainGroup": uid("group_main"),
    "packageReferences": [gr_ref, kf_ref],
    "productRefGroup": uid("group_Products"),
    "projectDirPath": "",
    "projectRoot": "",
    "targets": [target_id]
}

# --- Write JSON pbxproj ---
XCODEPROJ_DIR.mkdir(parents=True, exist_ok=True)

data = {
    "archiveVersion": "1",
    "objectVersion": "60",
    "objects": objects,
    "rootObject": project_id
}

with open(PBXPROJ, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

# Verify
with open(PBXPROJ) as f:
    json.load(f)

print(f"Generated {PBXPROJ}")
print(f"  {len(swift_files)} Swift source files")
print(f"  Format: JSON (Xcode 16+)")
print(f"\nOpen: open {XCODEPROJ_DIR}")
