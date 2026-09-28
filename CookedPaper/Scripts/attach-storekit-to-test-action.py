#!/usr/bin/env python3
"""
Run by XcodeGen's `postGenCommand` (see project.yml) immediately after every
`xcodegen generate`. XcodeGen writes a scheme's StoreKit Configuration into
LaunchAction only -- there is no equivalent field on its TestAction model, so
`xcodebuild test` (which the UI test target runs under) would otherwise launch
the app with no local StoreKit catalog, and the paywall would never resolve any
products to buy.

Rather than hand-construct the StoreKitConfigurationFileReference XML element
(its `identifier` attribute encodes a project-relative file reference in a
format that's easy to get subtly wrong without a real Xcode to verify against),
this copies the element XcodeGen already generated correctly for LaunchAction
into TestAction too. Idempotent: safe to run on every generate.
"""
import copy
import glob
import sys
import xml.etree.ElementTree as ET

SCHEME_GLOB = "CookedPaper.xcodeproj/xcshareddata/xcschemes/*.xcscheme"


def main() -> int:
    schemes = glob.glob(SCHEME_GLOB)
    if not schemes:
        print(f"attach-storekit-to-test-action: no schemes matched {SCHEME_GLOB!r}", file=sys.stderr)
        return 1

    for scheme_path in schemes:
        tree = ET.parse(scheme_path)
        root = tree.getroot()

        launch_action = root.find("LaunchAction")
        test_action = root.find("TestAction")
        if launch_action is None or test_action is None:
            continue

        storekit_ref = launch_action.find("StoreKitConfigurationFileReference")
        if storekit_ref is None:
            print(f"attach-storekit-to-test-action: {scheme_path} has no StoreKit "
                  f"configuration on LaunchAction -- nothing to copy, check project.yml's "
                  f"run.storeKitConfiguration key")
            continue

        if test_action.find("StoreKitConfigurationFileReference") is not None:
            continue  # already patched -- e.g. a re-run without a clean generate

        test_action.insert(0, copy.deepcopy(storekit_ref))
        tree.write(scheme_path, encoding="UTF-8", xml_declaration=True)
        print(f"attach-storekit-to-test-action: attached StoreKit configuration to "
              f"TestAction in {scheme_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
