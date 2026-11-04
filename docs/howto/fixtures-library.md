# Codec fixtures library

A set of 30 second test clips, one per row of the playback decision table, to check what Perch logs for each.

1. Run `scripts/make-fixtures.sh` on the Mac (add `--no-4k` to skip the 4K sample). It writes everything to `build/fixtures/Perch Fixtures/` and checks each clip with ffprobe. It takes about two minutes; existing clips are skipped unless you pass `--force`.
2. Copy that one folder to the NAS. It is about 55 MB without the 4K clip and about 360 MB with it.
3. In Plex, add a library of type "Other Videos" pointing at the folder, name it "Perch Fixtures", and let it scan. There is no title matching: clips show by file name.
4. Open `README.txt` in the folder. It lists the decision Perch should log for each file.

Not covered here, because ffmpeg cannot make them honestly: Dolby Vision 5, 7 and 8.1, DTS:X, Atmos, and real PGS subtitles. Those are covered by unit tests on metadata fixtures only. Clip 11 uses a VOBSUB image track as the stand-in.
