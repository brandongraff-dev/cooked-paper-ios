# iOS CI

`ios-build-and-screenshot.yml` builds CookedPaper on a macOS runner and runs the
full test suite — `CookedPaperTests` plus the `CookedPaperUITests` screenshot
walkthrough — against a simulator. It uploads two artifacts either way: a flat
`ui-screenshots` folder of numbered PNGs, and the raw `xcresult-bundle` (same
screenshots plus full logs) as a fallback if the PNG-extraction step's syntax turns
out wrong for whatever Xcode version the runner has. There is no Mac in this
project's dev loop, so these screenshots are currently the only way to see the app
running.

This workflow has never run before. A first attempt failing is expected and is not
by itself evidence the app is broken — read the failing step's log, starting with
the two diagnostic steps that print the Xcode versions and simulators actually
available on the runner, before drawing conclusions about the code.

To re-run without a new commit: `gh workflow run ios-build-and-screenshot.yml`, or
open the workflow in the repo's Actions tab and use "Run workflow".
