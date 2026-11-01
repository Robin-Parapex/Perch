# Perch

A native tvOS app for the Brown household. One app that the Apple TV lives in: Plex playback, requests, discovery, Apple Music, and the home (lights, cameras, doorbell), built in SwiftUI and installed through TestFlight. Private, family use only. Never published to the App Store.

Name: **Perch** (the balcony seat with the best view; a place to settle for the evening). Logo concepts and splash live on the "Perch Logo and Splash" design canvas.

## Why this exists

Plezy works for playback but its requests are unreliable, and no off-the-shelf client will show a doorbell over a film, dim the theatre lights on play, or tell the kids' profile it can't unlock the front door. Plex's own redesign has gone the wrong way (more clicks, slower, inconsistent with tvOS). We want the Apple TV app's feel with our own content and our own home behind it.

## What's in this pack

| File | Read it when |
|---|---|
| `CLAUDE.md` | Every session. Working rules, stack, non-negotiables, how work runs. |
| `docs/SPEC.md` | You need to know what a feature should do. The full product spec, screen by screen. |
| `docs/ROADMAP.md` | You are deciding what to build next. Versions, what's in each, MVP line, acceptance checks. |
| `docs/ARCHITECTURE.md` | You are planning a work package. Module layout, services, data flow, auth. |
| `docs/DESIGN.md` | You are building any screen. Design language, motion, focus, artwork, the premium bar. |
| `docs/MODULES.md` | You are adding or changing a module, the setup wizard, settings pages, keys, PINs, polling, or AI providers and permissions. |
| `docs/INTEGRATIONS.md` | You are touching Plex, Seerr, Home Assistant, Frigate, TMDB, Tautulli, MusicKit or AI. |
| `docs/PERMISSIONS.md` | Anything touching profiles, PINs, kids, or home control. |
| `docs/REFERENCES.md` | You want to see how someone else did it, or need API docs. |
| `docs/DECISIONS.md` | You wonder why something was chosen. Append to it when a new decision is made. |
| `docs/GLOSSARY.md` | A term is unclear (user-facing wording vs backend names). |
| `docs/KICKOFF.md` | You are starting the very first session: the opening prompt and how to drive the sessions after it. |

## How to use this pack with Claude Code

1. Create the repo, drop this pack in at the root, commit.
2. Start a Claude Code session in the repo. `CLAUDE.md` loads automatically.
3. Say which work package (WP) from `docs/ROADMAP.md` you want, for example "do WP-04", or say "next". Claude Code should plan that WP only, against `SPEC.md` and `ARCHITECTURE.md`, then build it.
4. Each WP is one branch and one pull request, ending with its acceptance checks passing on the real Apple TV and a line in `CHANGELOG.md`.
5. Nothing beyond the current WP is planned in detail. The roadmap says *what*; the WP plan says *how*.

## Status

Pre-development. Plan complete as of 1 November 2026; work starts with WP-01 in `docs/ROADMAP.md`. Five layout mockups and the logo and splash concepts exist on Claude design canvases and are references only.
