# GLOSSARY

Backend names on the left never appear in the app. Use the words on the right.

| Backend / internal | What the family sees |
|---|---|
| Seerr request, pending | **Requested** (and, for kids, "Waiting for a parent") |
| Approved, processing, Sonarr/Radarr queue, Decypharr, Usenet download, symlink | **Getting it ready** (progress bar when known) |
| Partially available (some seasons/episodes) | **Some episodes ready** |
| Available in Plex | **Ready to watch** (NEW badge until played) |
| Declined, failed, no release found after the timeout | **Couldn't find this yet** (with "Try again" for parents) |
| Debrid link expired, stream 4xx/5xx | **Couldn't play this** with **Try again** (parents) |
| Plex partial scan | (nothing shown) |
| Frigate event, person/parcel detection | **Front door**, **Driveway**, with the plain label ("Someone at the door", "Parcel delivered") |
| go2rtc HLS stream | **Live** |
| Home Assistant scene | **Scene** by its friendly name ("Movie night") |
| Rating ceiling, content restriction | **Suitable for this profile** |
| Direct play / direct stream / transcode | (Admin debug overlay only) |
| Tautulli | **Your stats**, **Year in review** |
| TMDB / fanart.tv / ThePosterDB / MediUX | (never named; "Artwork" in Admin) |
| AI provider, model, tokens, budget | **Ask**; when capped: "Ask is taking a break until next month" |
| Role, permission level, Admin PIN recency | **Admin PIN** |
| Plex Home PIN | **Profile PIN** |
| Feedback endpoint, webhook, GitHub issue | **Send feedback** |

Exception: service names (Plex, Seerr, Trakt, Home Assistant, Frigate, Tautulli, the AI provider) may appear in the setup wizard, Settings > Integrations, Help guides and Admin, because the reader there is the person who runs them. Sonarr, Radarr, Decypharr and Usenet appear only in the Help setup guide and Admin.

Other wording rules
- "Profile", not "user" or "account".
- "Request", not "download", "grab" or "add to Sonarr".
- "Film" and "series", not "movie" and "show", in UI copy (UK household).
- Sentence case everywhere. No exclamation marks.
