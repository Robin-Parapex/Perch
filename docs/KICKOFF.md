# KICKOFF

The first message to send to Claude Code once this pack sits at the root of a fresh repo. Copy everything inside the block.

```
You are the lead engineer on Perch, a native SwiftUI tvOS app. Read CLAUDE.md first, then README.md, then docs/ROADMAP.md. Treat every file in docs/ as the agreed plan; do not reopen decisions recorded in docs/DECISIONS.md.

Working method for this and every session:
- Work is organised as numbered work packages (WPs) in docs/ROADMAP.md. One WP = one branch (wp-01-skeleton) = one pull request. Plan one WP at a time, build it, review it, open the PR, stop.
- You are Opus, the lead. Use subagents: scout to read reference repos and docs before planning; builder for bounded, fully specified slices; reviewer on every diff before a PR; verifier for builds and tests; tester to write tests the plan calls for. Plan, integrate, judge and report yourself; do not re-read every helper's output, read the reviewer's verdict and the integrated result.
- Every screen is run on the real Apple TV 4K before it is called done. The simulator is for layout only.
- British English in all copy, no em dashes, no backend names in user-facing text (docs/GLOSSARY.md). Conventional commits that name the WP, for example feat(WP-01): project skeleton.
- Ask me before adding any dependency, changing the permission model, doing anything that resets or supervises the Apple TV, or anything that costs money. Decide everything else and note it in docs/DECISIONS.md.

Environment: this Mac has Xcode, Xcode Cloud and App Store Connect configured for my developer account. The Apple TV 4K is on the same network. My homelab has Plex, Seerr, Sonarr, Radarr, Decypharr, Home Assistant, Frigate and Tautulli.

Start now with WP-01 (Project skeleton) from docs/ROADMAP.md:
1. Have scout read the Dusk (https://github.com/marvinvr/dusk-player) and Swiftfin (https://github.com/jellyfin/Swiftfin) repositories and write docs/notes/reference-review.md: what to borrow for Plex auth, Plex Home switching, hubs and markers, tvOS focus handling, poster rows, Top Shelf, and the VLCKit integration we will need in 2.0; what to avoid; licence notes (Dusk MIT, Swiftfin MPL-2.0, VLCKit LGPL-2.1).
2. Enter plan mode and plan WP-01 only: the Xcode project and targets, the Swift packages under Packages/ (empty but compiling, one per module in docs/MODULES.md), Swift 6 and tvOS 26 minimum, the Xcode Cloud workflow that builds main to TestFlight internal testing, THIRD_PARTY_NOTICES.md, the privacy manifest, the ATS local-network exception, the export-compliance flag, and a one-screen placeholder app that shows the Perch wordmark so the pipeline can be proven end to end. Include how you will demonstrate the 0.1.0 acceptance line "Installs from TestFlight via Xcode Cloud on the Apple TV 4K".
3. Show me the plan and wait for my approval before writing code.

When WP-01 is merged, I will say "next" and you will plan WP-02.
```

## After WP-01

Say `next` to move to the lowest unmerged WP, or name one (`do WP-04`). When a version's last WP merges, say `release 0.1.0` and the lead will bump the version, cut the changelog, tag, and confirm the TestFlight build.

## If a session starts cold

Any later session gets the same context from `CLAUDE.md` automatically. If it seems lost, say: "Read CLAUDE.md and docs/ROADMAP.md, find the lowest unmerged WP, and plan it."
