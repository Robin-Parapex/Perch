# WP-01 Project skeleton: plan

## Context

Perch is an empty repo holding the document pack. WP-01 builds a compiling skeleton and proves the pipeline end to end: Xcode Cloud builds `main`, TestFlight installs it on the Apple TV 4K, and it shows the Perch wordmark. Nothing else ships. Done so far: pack moved to root and committed locally on `main` (`f8b2fc3`, not pushed), branch `wp-01-skeleton` created, `docs/notes/reference-review.md` written (uncommitted).

## Decisions taken (from your answers)

- Team: Parapex Ltd `3TWLQK4535`.
- Identifiers replace the proposed ones: `com.robrolabs.perch`, `com.robrolabs.perch.topshelf`, App Group and Keychain access group `group.com.robrolabs.perch`, URL scheme `perch`. Update `CLAUDE.md` line 14 and any other mention.
- Repo stays public.
- tvOS simulator runtime: approved, `xcodebuild -downloadPlatform tvOS`.
- XcodeGen: `project.yml` is the source, generated `Perch.xcodeproj` is committed. Local dev tool only, nothing in the app, no `ci_post_clone.sh` needed.

## Decided by the lead (recorded in `docs/DECISIONS.md`)

- **ATS:** `NSAllowsArbitraryLoads`, per ROADMAP and DECISIONS. The "local-network exception" wording in KICKOFF is treated as superseded.
- **Local network:** add `NSLocalNetworkUsageDescription`. `ARCHITECTURE.md:87` says tvOS has no prompt, but Apple documents the key for tvOS 14+, so that line is corrected. String: "Perch uses your local network to reach your media server and home devices." Real prompt behaviour gets checked on the Apple TV.
- **Package dependencies:** every module depends on `PerchCore` only (`MODULES.md`).
- **Placeholder art:** wordmark is "Perch" in SF Pro on `#0b0b0f`. Icon layers and Top Shelf images are generated placeholders, since the design canvas exports are not in the repo. Swap them when you have exports.

## Build

Branch `wp-01-skeleton`, small commits like `feat(WP-01): ...`. Helpers do not commit.

1. **Environment** (`verifier`): download the tvOS runtime, confirm a simulator destination exists.
2. **Packages** (`builder`): `Packages/{PerchCore,PerchDesign,PerchPlex,PerchPlayer,PerchSeerr,PerchTrakt,PerchHome,PerchFrigate,PerchAI,PerchTautulli}`. Each has `Package.swift` (Swift 6 language mode, `.tvOS("26.0")`), one public placeholder type, and one Swift Testing test target. No remote dependencies, so no `Package.resolved` yet (needed at WP-08 for Nuke).
3. **Project and targets** (`builder`, after step 2): `project.yml` generating `Perch.xcodeproj`:
   - `PerchApp`: tvOS 26.0, Swift 6, strict concurrency complete, `MARKETING_VERSION` 0.1.0, automatic signing, links all ten packages so the compile proof covers them. Shows the wordmark on one screen. `PerchApp/Features/`, `PerchApp/Resources/`.
   - `PerchTopShelf`: extension with `com.apple.tv-top-shelf`, a `ContentProvider` returning nil so tvOS uses the static image (approach from Dusk, one-line source comment), `APPLICATION_EXTENSION_API_ONLY`, embedded in the app.
   - `PerchUITests`: one smoke test that launches and finds the wordmark.
   - Shared scheme `PerchApp` committed.
   - Info.plist: ATS, local network string, `ITSAppUsesNonExemptEncryption=false`, `CFBundleURLTypes` for `perch`.
   - Entitlements on both targets: App Group `group.com.robrolabs.perch`.
   - `PrivacyInfo.xcprivacy` in both bundles: no tracking, no collected data. The app declares `NSPrivacyAccessedAPICategoryUserDefaults` with `CA92.1`, checked against Apple's table at build time. App Group reason is left out until WP-17, if it is needed at all.
   - Assets: `AppIcon.brandassets` with layered imagestacks (400x240 and 1280x768, 2 layers), Top Shelf 1920x720 and wide 2320x720. Sizes follow Dusk and Swiftfin; two were not confirmed on Apple pages, so a local archive validation settles them.
4. **Gate** (`builder`): `scripts/gate.sh` runs all package tests and a tvOS simulator build plus UI test. `.claude/pr.json` with `repo`, `gate`, `merger: robin`, push needing your word.
5. **Records** (`scribe`): `THIRD_PARTY_NOTICES.md` (nothing borrowed yet; the rules from the review), `CHANGELOG.md`, `DECISIONS.md`, `CLAUDE.md` and ARCHITECTURE fixes, and `docs/howto/xcode-cloud.md` with the exact workflow settings: scheme `PerchApp`, start condition branch `main`, Archive for tvOS, TestFlight internal only, Xcode matching 27.2 or Latest Release.
6. **Check** (`verifier`, then `reviewer` once): gate green, then an Opus review of the whole diff. Any fix gets a scoped recheck.

Perch is outside the Parapex programme, so no STATUS.md or tracker rows.

## Your manual steps

The lead stops and waits at each.

1. Give the word to push `main` and `wp-01-skeleton`. I open a draft PR with `/pr open`.
2. Pair the Apple TV: Xcode > Window > Devices and Simulators, then on the TV Settings > Remotes and Devices > Remote App and Devices. It is not paired with this Mac today. Turn on Developer Mode if asked.
3. Register `com.robrolabs.perch`, `com.robrolabs.perch.topshelf` and the App Group under Parapex Ltd (opening the project in Xcode with automatic signing does this).
4. Create the app record in App Store Connect with `com.robrolabs.perch`.
5. Create the Xcode Cloud workflow from Xcode (Product > Xcode Cloud) per the how-to and grant it the repo.
6. Add yourself as an internal tester.
7. Merge. Xcode Cloud only builds `main`, so the merge is what triggers the proof.

## Verification

- **Local:** `scripts/gate.sh` green; `xcodebuild archive` for `generic/platform=tvOS` succeeds, signed by Xcode once step 3 is done. This does not upload anything.
- **Hardware before merge:** install from Xcode over the network to the Apple TV; wordmark shows, Menu/Back exits cleanly, static Top Shelf image shows when the icon is focused. Record the result in the PR.
- **Acceptance after merge ("Installs from TestFlight via Xcode Cloud on the Apple TV 4K"):** the merge produces a green Xcode Cloud build, that build reaches internal testing, you install it from the TestFlight app on the Apple TV and it launches to the wordmark. You confirm, and the build number goes in a PR comment and `CHANGELOG.md`. Only your confirmation closes this; a simulator or local archive does not count.

The acceptance check can only complete after merge, so the PR description lists it as pending and says why.

## What stays unverified until then

Which assets App Store Connect actually rejects, whether 27.2 is offered in the Xcode Cloud list, and tvOS 26 local network prompt behaviour. A failure in any of these gets a patch on a follow-up branch.
