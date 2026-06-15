# PrepOSApp — macOS app target

The SwiftUI shell over the `PrepOSKit` package. The Xcode project is **generated** from
[`project.yml`](project.yml) with [XcodeGen](https://github.com/yonsm/XcodeGen) so the repo
stays diffable — the `.xcodeproj` and `.entitlements` are derived artifacts and are
gitignored.

## Generate & open

```bash
brew install xcodegen      # once
cd App && xcodegen generate
open PrepOS.xcodeproj       # or build from the command line below
```

## Build / run from the command line

```bash
cd App
xcodebuild -project PrepOS.xcodeproj -scheme PrepOSApp -destination 'platform=macOS' \
  build CODE_SIGNING_ALLOWED=NO
```

(If `xcode-select -p` still points at the Command Line Tools, prefix with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.)

## What's here now

An empty, navigable skeleton (scaffold-plan.md §4): a sidebar of the main surfaces
(Today/This Week, Needs Sorting, Buckets, Digests) with placeholder detail views, plus a
Settings scene that reads the real `AppConfig` thresholds from `PrepOSCore`. Later phases
fill these in: capture surfaces, the cockpit, triage, the agentic workspace.

## Entitlements (least privilege — Security Constitution §7)

Defined inline in `project.yml`: App Sandbox, outgoing network (TLS), user-selected file
access. **No** microphone, camera, or broad filesystem entitlements. Hardened Runtime is
enabled for signed builds (disabled automatically under local ad-hoc signing).
