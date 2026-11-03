# PERMISSIONS

Roles, what they may do, and how it's enforced. `PerchCore` enforces all of this on the device; the UI only reflects it. A test must exist for every "no" in the matrix.

## Roles

| Role | Who | Notes |
|---|---|---|
| `parent` | Robin, partner | Full access. |
| `teen` | future | Requests need approval; limited home control. Unused today but keep the role so the matrix doesn't need redesign later. |
| `kid` | Arthur | Rating-limited, PIN-locked profile, no door/alarm, own room only. |

Each profile has: `role`, `plexUserId`, `seerrUserId`, `rooms[]` (HA areas it may control), `ratingCeiling` (BBFC: U, PG, 12A, 15, 18; derived from Plex, Admin may lower it), `pinRequiredToExit`, `aiEnabled`, `aiLevel`.

**Rating ceiling mapping (Plex is the source of truth):**

| Plex Home user | BBFC ceiling in Perch |
|---|---|
| Restricted, profile "Little Kid" | U |
| Restricted, profile "Older Kid" | PG |
| Restricted, profile "Teen" | 12A |
| Restricted, custom allowed ratings | the highest allowed rating mapped (G/U -> U, PG -> PG, PG-13/12/12A -> 12A, R/15 -> 15, NC-17/18 -> 18) |
| Unrestricted | 18 |

Admin can lower any profile's ceiling; it can never raise it above what Plex allows. Discover, recommendation, seasonal and AI results use the Perch ceiling; the library itself is filtered by Plex.

**Role defaults:** account owner and unrestricted Home users -> parent; restricted Home users -> kid; teen only by assignment in Admin.

**Admin** requires the parent role **and** the Admin PIN; a kid or teen session cannot open it even with the PIN.

There are two PINs: Plex Home PINs for profiles (verified by plex.tv) and the Admin PIN (see `MODULES.md`).

**Top Shelf** runs outside any profile, on the tvOS home screen, so it gets a `topshelf` pseudo-role: read-only, lowest rating ceiling in the household, no Continue watching items above that ceiling.

## Matrix

| Action | parent | teen | kid |
|---|---|---|---|
| Browse library (within rating ceiling) | yes | yes | yes |
| Play | yes | yes | yes |
| Switch profile / exit profile | yes | yes | PIN |
| Open Settings | yes | limited | PIN |
| Open Admin | yes | no | no |
| Edit setup or run setup again (`editSetup`) | PIN-fresh, audited | no | no |
| Request a title | yes (auto-approve) | yes (queued) | yes (queued) |
| Approve requests | yes | no | no |
| See doorbell overlay | yes | yes | yes |
| Unlock door | PIN-fresh | no | no |
| View cameras | yes | yes | view-only, no history |
| Lights / scenes | all rooms | own rooms + shared | own room only |
| Blinds, amp, inputs | yes | shared rooms | no |
| Alarm | PIN-fresh | no | no |
| Send messages to the TV | yes | yes | no |
| Use Ask (AI) | yes (level set in Admin) | only if enabled in Admin, rating-limited, max level 3 | no |
| Change row order / collections | yes | own profile | no |
| Year in review (own) | yes | yes | yes (parent can disable) |

"PIN-fresh" = Admin PIN entered in the last 5 minutes on this device.

## Enforcement

- `PerchCore` checks the matrix on every privileged action.
- Roles default from Plex Home (owner and unrestricted users parent, restricted users kid, teen only by assignment) and are editable behind the Admin PIN.
- Home actions go through an explicit `domain.service` allow-list per role. Anything not listed is denied, even if Home Assistant would allow it.
- `editSetup` is parent only and needs a fresh Admin PIN; teen and kid are denied whatever PIN they type.
- Leaving a kid profile always needs the target adult's Plex PIN, or the Admin PIN when that adult has none. The rule keys on the kid role, not on `pinRequiredToExit`, and lives in `PerchCore` (`ProfileSwitchPolicy`).
- Door and alarm actions require the Admin PIN entered in the last 5 minutes.
- Seerr requests are created as the profile's Seerr user, so Seerr's approval rules also apply.
- AI permission levels (1 to 4 as in `MODULES.md`) are enforced before any tool runs.
- Rating ceilings filter library, discover, recommendations, seasonal rows and AI results.

## Device-level lock (optional, 1.3)

tvOS has no Guided Access. Options, from lightest to strongest:
1. **In-app lock** (default): Plex PIN to leave the kids' profile. The Home button still exits the app.
2. **Screen Time on the Apple TV:** restrict other apps and content ratings. No supervision needed.
3. **Single App Mode (only with Robin's approval):** supervise the Apple TV with Apple Configurator on the Mac (requires erasing the device once) and push a Single App Mode profile, or use an MDM. The Apple TV then only runs Perch. Best for a dedicated kids' TV. Warning: a TestFlight build expires after 90 days and a locked device can't open anything else, so keep the re-upload reminder and prefer a development-signed Xcode install (valid for a year) on a locked device. Document the steps in a `docs/howto/` note when done.

## Audit

Every privileged action (unlock, alarm, approve, admin change, AI home action) is logged on the device with profile, time, entity and outcome, visible in Admin.
