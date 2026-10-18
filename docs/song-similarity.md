# Song similarity and "recommended next song" (v1 design)

Written 2026-10-17. Status: draft for the owner. Items marked **[UNVERIFIED]** were not confirmed and must be checked before they are relied on.

## 1. Goal

Resurrect a large collection of mp3s ripped from CDs. v1 delivers one recommendation signal, **song similarity**:

- A **server** (a command-line tool on the owner's Mac) analyses the library once and writes a compact **similarity file**.
- The **app** (Mac and iPhone) reads that file and picks "the next song" on-device, with every song available locally and no network.
- The app collects a **thumbs up / thumbs down** on each recommendation. A **collector** on the server reads that feedback later and produces a better file.

Other signals (tempo and key match, lyrics, listening history) are out of scope for v1. The file format leaves room for them.

## 2. Decisions already made

| Decision | Choice |
|---|---|
| Users | The owner and the owner's sons. A household, not the public. |
| Library | One shared library pool. A song is the same song for every profile. |
| Identity | A random profile UUID per person. No passwords, no Apple ID, no email. |
| Pooled feedback | Yes. All profiles' feedback goes to the server. |
| Privacy | Not a concern in this first cut. Revisit before anyone outside the household uses it. |

## 3. Research summary

No published benchmark compares the main candidates on music similarity. Papers disagree by task, so the model is chosen by a bake-off on the owner's own library (section 8), not from the literature.

- **MERT, MusicFM, MuQ.** One recommender study found MERT best on cold-start nearest-neighbour retrieval (HitRate@20 0.283, against 0.245 for MusicFM and 0.173 for MuQ) and MusicFM best on the "hot" test, https://arxiv.org/html/2604.23077v1. MuQ's own paper claims it beats MERT and MusicFM, which is self-reported, https://arxiv.org/html/2501.01108v1.
- **CLAP and MuQ-MuLan.** Trained with text, so they can answer "melancholy piano" as well as "like this song". CLAP embeddings clustered mostly by vocal against instrumental in one study, https://arxiv.org/pdf/2508.06516. MuQ-MuLan needs 24 kHz input.
- **Discogs-EffNet (Essentia).** Small, with contrastive variants trained for similarity, https://essentia.upf.edu/models.html. A secondary source says the weights are CC BY-NC-SA 4.0 **[UNVERIFIED: official page not reached]**.
- **Licences.** The `muq` code is MIT; no licence statement was found for the MuQ-MuLan weights. MERT's and CLAP's weight licences were not checked. Check every weight licence before anyone outside the household uses the app.

## 4. Architecture

```
mp3 files ──► server: decode, window, embed, reduce ──► similarity file ──► app: next song
                       ▲                                                       │
                       └──── collector: merges feedback, trains, new file ◄────┘ thumbs events
```

The server is a process on the Mac. The transport between server and devices is the shared iCloud container (`CloudFolder`), which already holds the playlists. There is no hosted service in v1.

## 5. The similarity file

- **Key.** The audio file's content hash, the same key the lyric sheet store uses. A song is therefore the same row for every profile and every device.
- **Header.** Format version, model name, model version, embedding dimension, track count, creation time.
- **Vectors.** One L2-normalised row per track, float16, reduced by PCA to a few hundred dimensions at most. The dimension is a named constant chosen by the bake-off.
- **Optional neighbour lists.** The top K nearest tracks per track, precomputed, so the phone can pick a next song with no arithmetic. K is a named constant.
- **Size.** 5,000 tracks at 128 dimensions in float16 is about 1.3 MB. At 768 dimensions it is about 8 MB.
- **Per-user adapter** (added by the collector, not in the first file). A small matrix or taste vector per profile, about 32 KB each at 128 dimensions.

## 6. Next-song selection (on-device)

1. The query is the centroid of the last few played songs, plus the profile's feedback shift (below).
2. Rank every candidate by cosine similarity using Accelerate. Brute force is enough below roughly 100,000 tracks; no approximate index.
3. Exclude songs played recently and apply a small diversity penalty, so the list does not collapse onto one album.
4. If the library has no vector for the current song (new file), fall back to the existing behaviour and say so in the log.

The selection logic lives in `PlayawayCore` so Mac and iPhone share it. It runs outside the audio render path and allocates nothing in it.

## 7. Feedback and identity

**Profile.** A random UUID created the first time a profile is made and stored in the iCloud container, so one person on Mac and iPhone is one profile. Each device also has its own `device_id`.

**Event.** One line per thumbs press:

```
event_id, profile_id, device_id, timestamp,
seed_track (content hash), candidate_track (content hash),
verdict (up | down), model_version, context (what was playing)
```

- The rating belongs to the **pair** (seed to candidate), not to one song.
- `event_id` is unique. The collector drops duplicates.
- Each device appends to its own file, `feedback/<profile_id>/<device_id>.jsonl`, so no two devices write one file and the sync service cannot create conflicts.

**Use on the device, from day one.** The query moves toward thumbs-up songs and away from thumbs-down songs for that profile.

**Collector (later).**
1. Read and merge every feedback file, dropping duplicate events.
2. Train a shared metric from pooled votes.
3. Train a per-profile adapter on top, once a profile has enough votes. The minimum is a named constant, decided by experiment.
4. Write a new similarity file with a new model version. Events keep their model version so old and new votes are not mixed unknowingly.

"Similar" is subjective: pooled votes from people with different tastes conflict, so the pooled model and the personal adapters are trained separately and the profile id stays on every row.

## 8. Bake-off (first piece of work)

Choose the embedding model by measurement, on the owner's own library.

- **Labels for free.** Pairs from the same album or artist (from tags) and pairs from the owner's playlists count as "should be near".
- **Candidates.** MERT-95M, MuQ, Discogs-EffNet, CLAP.
- **Baseline.** Tags only (artist, album, genre). If a model does not clearly beat the tags baseline, the server is not yet worth building.
- **Metric.** The share of a song's top 10 neighbours that are labelled "near". Report per model, and report the spread across genres, since CD rips mix classical, live and spoken word.
- **Tooling.** Python run with `uv run`. Results go in a table in this document.

## 9. Open questions

- Which model wins the bake-off, and is its weight licence acceptable?
- How many votes does a profile need before its adapter beats the shared model?
- What does the app do for songs with no sensible neighbours (classical, spoken word)? Proposal: show "no recommendation" rather than a poor one.
- If the library grows or other people join: real accounts, a hosted collector and a privacy policy are then required. Not in v1.

## 10. Tests required (when built)

- Two devices, one profile: duplicate events are dropped by the collector.
- A file with a model version the app does not know is rejected without a crash.
- Next-song selection is deterministic for a fixed file and history.
- The mac and iPhone paths share one `PlayawayCore` implementation and one set of story tests.
- Tests are silent, and none launches the app without the owner's permission.
