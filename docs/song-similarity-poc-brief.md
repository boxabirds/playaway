# PoC brief: song similarity bake-off (offline, on the owner's library)

Written 2026-10-17. Companion to `docs/song-similarity.md` (design) section 8. Items marked **[UNVERIFIED]** were not confirmed and must be checked before they are relied on. Thresholds marked **[PROPOSED]** are the author's starting points, for the owner to change before the run, never after seeing results.

## 1. Goal

Answer one question: **does a learned audio embedding find neighbours in the owner's ripped-CD library that are better than tags alone, and which model does it best?**

The PoC produces a table of scores per model, a per-genre breakdown, and a go / no-go on building the server. It does not build the server, the similarity file, the app feature or the feedback loop.

## 2. Inputs

- **The library:** a folder of mp3 files ripped from CDs. Path supplied by the owner (not yet given). Read-only: the script never writes to, moves or retags the library.
- **Tags:** artist, album, genre, track number, read from ID3. Many rips will have missing or wrong tags; the script reports how many files have each field before scoring.
- **Playlists:** the owner's existing Playaway playlist documents, as a second source of "should be near" pairs. Optional; the first run can use tags only.

## 3. Labels ("should be near")

Ground truth comes free from the library, and it is imperfect on purpose. Report which kind each score uses.

1. **Same album.** Two tracks from one album. Strong, but biased: album mates share production, so a model can score well by recognising the mix and the studio, not the song.
2. **Same artist, different album.** Weaker "near", but tests whether the model generalises past production.
3. **Same playlist** (owner-made). The closest thing to taste, and probably the most honest. Fewer pairs.

Known weakness: tags are not similarity. Two songs by one artist can sound unlike each other, and two unrelated artists can sound alike. The score measures agreement with metadata, not truth, and the final test is the owner's ears (section 7).

## 4. Candidates

| Candidate | Why it is in | Check before running |
|---|---|---|
| MERT (start with the 95M model) | Best on cold-start retrieval in one recommender study, https://arxiv.org/html/2604.23077v1 | Weight licence **[UNVERIFIED]**; expected input sample rate **[UNVERIFIED]**; which layer to take embeddings from (the layers differ in quality; test a few) |
| MuQ | Claims to beat MERT and MusicFM (self-reported), https://arxiv.org/html/2501.01108v1 | Code is MIT; weight licence **[UNVERIFIED]**; needs 24 kHz input |
| Discogs-EffNet (Essentia) | Small and fast, with contrastive variants trained for similarity, https://essentia.upf.edu/models.html | Weights reported CC BY-NC-SA 4.0 by a secondary source **[UNVERIFIED]**; input sample rate **[UNVERIFIED]** |
| CLAP | Text and audio in one space, so it also tests "find the moment" style queries | Which checkpoint; weight licence **[UNVERIFIED]**; input sample rate **[UNVERIFIED]** |
| Baseline: tags only | The bar every model must clear | None. Score it with the same labels: it will win same-album pairs by construction, so report it per label kind |
| Baseline: random | Sanity floor | None |

MusicFM is left out of the first run to keep it small. Add it only if the first run is inconclusive.

## 5. Method

1. **Audit the library.** Count files, total duration, and tag coverage. Print and stop if tag coverage is too low to make labels (threshold below).
2. **Decode** each file once to mono at the sample rate each model needs. Cache the decoded audio on disk in the scratchpad, not in the library.
3. **Window.** Take several windows per song, spread across the song, and skip the first and last seconds (silence, applause on live albums). Window length and count are named constants in the script, identical for all models so the comparison is fair.
4. **Embed** each window with each model. Average the windows, then L2-normalise. Record the seconds per song for each model, since server time matters.
5. **Neighbours.** For every song, rank all others by cosine similarity and take the top 10.
6. **Score** (section 6) per model, per label kind, per genre.
7. **Test the reduction.** Reduce each model's vectors with PCA to the sizes in the design doc (128 dimensions and one larger) and rescore. The file format depends on how much is lost.
8. **Save** every embedding matrix and the score table. Embeddings are not recomputed to change a metric.

Tooling: Python run with `uv run`, scripts kept outside any downloaded model directory, and `python -I` on anything that reads untrusted downloaded files. Model weights are downloaded into their own empty directories. The run is silent and uses no audio output.

## 6. Metrics

- **Precision@10:** of a song's 10 nearest neighbours, the share labelled "near". Averaged over songs that have at least one labelled partner.
- **Recall@50 for same-album mates:** how many of a track's album mates appear in its top 50.
- **Per-genre spread:** the same metrics grouped by tag genre. A model that scores well overall and badly on classical, spoken word or live recordings is a finding, not a footnote.
- **Hubness:** how many songs appear in other songs' top 10 far more often than average. Embedding spaces often have a few "hub" tracks that show up everywhere, which makes next-song picks feel repetitive. Report the top 20 hubs by name.
- **Cost:** seconds per song and peak memory per model, on the owner's Mac.

## 7. Pass / fail

All thresholds are **[PROPOSED]** and fixed before the run.

- **Library usable:** at least 70% of files have artist and album tags. Below that, fix tags first or use playlists as the main labels.
- **A model is worth building around** if it beats the tags-only baseline on same-artist-different-album precision@10 (the label where tags have no unfair advantage) and beats random by a wide margin on every label kind.
- **Go** if at least one model passes and its 128-dimension reduction loses no more than a small, stated fraction of its full score.
- **Ears test (required, cannot be skipped).** For the winner, the owner picks 10 songs they know and listens to the top 5 neighbours of each, rating each neighbour good or bad. Metadata agreement can pass while the lists sound wrong. If the owner's ears disagree with the metric, the metric is wrong and the result is not a go.
- **No-go** if no model beats tags on same-artist-different-album. Then the server is not worth building yet, and the next step is to question the labels, not to try more models.

## 8. Risks

- **Labels flatter production over song.** Album mates share a mix. Counted separately for this reason.
- **Tag quality.** CD rips from old metadata services are often wrong or blank.
- **Genre mix.** One library holds classical, live, spoken word and pop. A single average hides the failures.
- **Short windows miss structure.** Songs change section. The averaging choice may matter more than the model; test two window counts on the best model if time allows.
- **Licences.** A model that wins but cannot be shipped is a research result only. Record each licence before the run so the winner's status is known.

## 9. Outputs

- A score table (models by label kind), the per-genre table, the hub list, and the cost table, all written into `docs/song-similarity.md` section 8 with the date and the library size.
- The saved embeddings, in the scratchpad, so section 5 step 7 and later runs do not recompute them.
- A one-line recommendation: which model, which dimension, or "no-go".

## 10. Out of scope

Server, similarity file writer, app UI, thumbs feedback, profiles, collector, tempo and key signals, lyrics.

## 11. Open items for the owner

1. The path to the ripped mp3 folder (and whether the whole library or a sample of it for the first run).
2. Whether to include Playaway playlists as labels in run one.
3. Confirm or change the **[PROPOSED]** thresholds in section 7 before the run starts.
