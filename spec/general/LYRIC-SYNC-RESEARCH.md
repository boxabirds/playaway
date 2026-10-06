# Lyric-synced playback: research on native word-level timing for the Mac

Status: research, 2026-10-06. Updated the same day with the owner's decision (section 10): lyrics come from the music audio itself. Nothing was built. No candidate was run on a song in this session. Every number below was read from the source named next to it. Where I could not read a primary source, the item is marked unverified.

## 1. Bottom line

1. **WhisperX does produce word-level timings, but it is not a native Mac component.** It is a Python pipeline: Whisper for the text, then a separate wav2vec2 phoneme model that force-aligns the words to the audio. Its README documents GPU use only with CUDA 12.8, and CPU use (including macOS) with `--compute_type int8 --device cpu`. It does not mention Apple Silicon or Metal. Shipping a Python stack inside a notarized Mac app is, in my judgment, the wrong shape for this product. The technique is what is worth taking.
2. **Native Mac options for the Whisper part exist and are mature**: WhisperKit (Swift, Core ML), whisper.cpp (Metal, optional Core ML encoder) and MLX Whisper (Python). All three give word timestamps by a different method from WhisperX: they read the decoder's cross-attention weights and run dynamic time warping (DTW). The WhisperX paper measures that method as less precise than forced alignment, though not by a wide margin on speech.
3. **"Extremely accurate" is a speech result, not a singing result.** On read speech WhisperX puts 82.4% of word boundaries within 50 ms (Rousso et al., 2024). On singing, the published lyrics-alignment systems I found reach an average absolute error of about 0.2 to 0.4 s, and that is when they are given the correct lyrics. I found no published word-timing accuracy for WhisperX or Whisper-DTW on singing. That is the main gap, and it can be closed by measuring.
4. **Transcribing lyrics from audio alone is much worse than aligning known lyrics.** Whisper large-v2 reaches about 20 to 23% word error rate on the Jam-ALT lyrics benchmark (Syed et al., 2025). One word in five is wrong, and a synced display would show the wrong words.
5. **So the design should start from known lyrics and align them**, and use transcription only as a fallback. Where the lyrics come from (embedded tag, sidecar file, an online database, the user) is a product and legal decision that is not settled here.

## 2. What WhisperX actually is

Source: WhisperX README, https://github.com/m-bain/whisperX, and the paper, https://arxiv.org/abs/2303.00747.

- Text: OpenAI Whisper in several sizes (the README lists small to large-v3). I believe it runs through the faster-whisper backend, but that is from general knowledge and I did not read it in this session.
- Word times: a language-specific wav2vec2 phoneme model aligns the transcript to the audio. For English the default is a model trained on 960 hours of audiobook speech (LibriSpeech). The paper says the base 960 h model "should be the default alignment model".
- Segmenting: a voice activity detector cuts the audio into chunks of up to about 30 s ("Cut & Merge"). This also reduces Whisper's hallucination and repetition.
- Licence: BSD-2-Clause.
- Listed limits: words with no characters in the alignment model's dictionary (for example "2014." or "£13.60") cannot be aligned; overlapping speech is handled badly; a language-specific model is needed.
- Not mentioned anywhere on the README: music, singing, Apple Silicon, Metal.

## 3. Candidates

| Component | What it does | Runs on a Mac as | Word-timing method | Licence | Notes and evidence |
|---|---|---|---|---|---|
| WhisperX | ASR plus forced alignment | Python. CUDA or CPU only per README | wav2vec2 forced alignment | BSD-2-Clause | Documented macOS use is CPU int8. Not a native fit. |
| WhisperKit (Argmax) | Whisper on Core ML | Swift package, macOS 14 or later | Cross-attention DTW (read in `SegmentSeeker.swift`: `addWordTimestamps`, `dynamicTimeWarping`, `findAlignment`; no separate alignment model) | MIT | Open source covers WhisperKit, TTSKit, SpeakerKit. Advanced features are in a paid Argmax Pro SDK. Recommended large-v3 variant is about 626 MB. |
| whisper.cpp | Whisper in C/C++ | Metal GPU; optional Core ML encoder on the Neural Engine (README: "more than x3 faster compared with CPU-only"). XCFramework and Swift package available | `-ml 1` splits segments into words. An experimental DTW mode exists (`dtw_token_timestamps`, per-token `t_dtw`, alignment-head presets up to large-v3-turbo, read in `whisper.h`) | MIT | README does not discuss timestamp accuracy. DTW is marked EXPERIMENTAL in the header. |
| MLX Whisper | Whisper on Apple's MLX | Python (`pip install mlx-whisper`) | `word_timestamps=True`; implemented in `timing.py` with alignment-head cross-attention, median filter and DTW, no separate aligner | not stated on the page I read | Python again, so the same packaging objection as WhisperX. |
| Apple Speech (SpeechAnalyzer, SpeechTranscriber) | System speech-to-text | Part of macOS 26 | A time-range attribute `audioTimeRange` exists. Whether it is per word is unverified. | System framework | Confirmed in this Mac's macOS SDK interface: `SpeechTranscriber` with presets such as `timeIndexedTranscriptionWithAlternatives`, and `AttributeScopes.SpeechAttributes.audioTimeRange`. Behaviour on singing is untested. |
| Qwen3-ForcedAligner-0.6B | Forced aligner: audio plus text in, word or character times out | Offered by the speech-swift toolkit for MLX and Core ML (per its README; its licence is not stated there) | Dedicated aligner model | Apache-2.0 (model card) | Model card: 11 languages, audio up to 5 minutes, and "Speech audio only". Claimed average alignment shift 42.9 ms against WhisperX 133.2 ms on the vendor's own benchmark. That is a vendor claim on speech, not a singing result. |
| Demucs MLX (Swift) | Vocal and stem separation | Swift package, Apple Silicon, macOS 14 or later | Not a timing tool: it removes the accompaniment | MIT for the code; weights licence not stated on the page | README claim: a 3:19 track in 14.8 s on an M1 Pro (batch size 8). Uses about 1.2 GB at batch size 1. |

## 4. Accuracy evidence

### Speech (where WhisperX is strong)

Rousso et al., "Tradition or Innovation", https://arxiv.org/abs/2406.19363. Word boundaries, two English speech corpora:

| TIMIT (read speech) | within 10 ms | 25 ms | 50 ms | 100 ms | mean error | median |
|---|---|---|---|---|---|---|
| Montreal Forced Aligner (classic) | 41.6% | 72.8% | 89.4% | 97.4% | 21.9 ms | 12.5 ms |
| MMS (wav2vec2) | 18.6% | 43.5% | 75.7% | 94.7% | 68.5 ms | 29.3 ms |
| WhisperX | 22.4% | 52.7% | 82.4% | 94.2% | 34.3 ms | 23.5 ms |

On the Buckeye conversational corpus, whose utterances run to minutes, WhisperX drifted: 67.4% within 50 ms and a mean error of 11,685 ms without a 500 ms sanity threshold, and 81.8% and 36.4 ms with it. The authors conclude that the classic aligner still beats both neural methods on speech. Their test used only speech, with no singing or music.

WhisperX paper, Table 2 (collar 200 ms; Whisper's word times inferred by DTW):

| Corpus | Whisper (DTW) precision / recall | WhisperX precision / recall |
|---|---|---|
| AMI | 78.9 / 52.1 | 84.1 / 60.3 |
| Switchboard | 85.4 / 62.8 | 93.2 / 65.4 |

The paper's own wording: using Whisper alone for word-level times "significantly underperforms in word segmentation precision and recall". So forced alignment improves on DTW, by a few to eight points of precision in this table.

### Singing: aligning known lyrics

- Stoller, Durand, Ewert (2019), https://arxiv.org/abs/1902.06797. Mean absolute error of predicted word start times on the Mauch pop dataset: previous MIREX 2017 systems 9.03 to 22.23 s; their end-to-end model 0.35 s. On their Jamendo set (20 songs, nine genres): 0.82 s. Retrained on separated vocals: 0.27 s and 0.38 s. They note poor results on slurred hip-hop and metal.
- Contrastive-learning aligner (2023), https://arxiv.org/abs/2306.07744: "the first to yield an average absolute error below 0.2 seconds on the standard Jamendo dataset". It also releases word-level alignments for JamendoLyrics Multi-Lang, which makes a good test set.
- Reading across: published singing alignment is in the hundreds of milliseconds, not tens. I did not find word-level numbers for WhisperX or Qwen3-ForcedAligner on singing.

### Singing: transcribing without lyrics

Syed et al. (2025), https://arxiv.org/abs/2506.15514. Whisper large-v2 through faster-whisper, beam 5, language supplied, Jam-ALT benchmark, whole songs:

| Audio | Whisper's own segmenting | With a volume-based segmenter on separated vocals |
|---|---|---|
| Original mix | 23.02% WER | 20.35% WER |
| Separated vocals (Demucs) | 22.87% | 20.72% |

Separating the vocals barely changed the Jam-ALT error rate. The gain came from better segment boundaries. On the second dataset, MUSDB-ALT, separation helped more (25.82% to 21.90% with Whisper's own segmenting, 20.07% with the segmenter; 14.98% on true vocal stems). The paper calls the 20.35% figure state of the art for an open-source system, and reports that over half of the backing vocals and non-lexical sounds ("ooh", "la") are deleted in both datasets.

One search-tool summary of this paper claimed 15 to 25 point error reductions from separation. The tables above contradict that, so I did not use it. I mention this because other summaries I read were also loose, and every number in this document was checked against the paper or page itself.

## 5. What this means for the feature

- **Aligning lyrics the app already has is the accurate path.** The inputs could be lyrics embedded in the file's tags, a sidecar file, a lookup, or text the person pastes. I found that LRCLIB is an MIT-licensed, openly accessible synced-lyrics service with about three million entries, with public database dumps (per search results). The pages I read did not state whether entries may be used in this app, and did not say whether the synced entries are line-level or word-level. The LRC format those services use is line-level in my understanding, which would not give the word-level timing wanted here; that is unverified. Lyrics are copyrighted text, so any source needs a rights check. That is not legal advice.
- **Transcribing from audio is a fallback**, and the person should see that those words are machine guesses.
- **Expect hundreds of milliseconds, not tens, on real songs.** Whether that feels synced is a product question. In my judgment a line-level highlight tolerates much more error than a word-by-word karaoke highlight, and 200 ms is likely noticeable on words. That judgment is untested and should be tried with people.
- **Pick the accuracy bar before picking the model.** Word highlighting needs the most accuracy; a line that lights up and scrolls needs far less.

## 6. A native pipeline to test (not a decision)

1. Get the lyrics text. If there is none, go to step 3 for the text.
2. Optional: separate the vocals with Demucs MLX (Swift package). Syed et al. suggest it may matter less than good segmentation on some music, so measure it.
3. Segment on vocal activity, then, only if there was no text, transcribe with WhisperKit or whisper.cpp.
4. Force-align the text to the audio. Candidates: Qwen3-ForcedAligner (needs a singing check; the card says speech only, and 5 minute limit means long songs need chunking), or a wav2vec2 CTC aligner converted to Core ML, or the Whisper DTW times as the baseline.
5. Cache the result per file (a sidecar or an app database), so the work is done once per song, in the background.

Everything above would run offline and on device. Model downloads are sizeable (WhisperKit's recommended variant is about 626 MB), so they should be optional and on demand.

## 7. Spike plan

Goal: replace guesses with a measured accuracy per candidate on singing.

- **Test set:** JamendoLyrics Multi-Lang with the released word-level alignments (https://arxiv.org/abs/2306.07744), plus 10 to 20 songs from the owner's own library, hand-checked at a few points.
- **Metrics:** average absolute error of word start times; share of words within 100, 200 and 300 ms; seconds of processing per minute of audio; peak memory.
- **Runs:**
  - A. Whisper DTW word times (WhisperKit and whisper.cpp DTW) on the mix, transcribing.
  - B. The same on Demucs-separated vocals.
  - C. Forced alignment of the correct lyrics on the mix and on the separated vocals (Qwen3-ForcedAligner and one CTC aligner).
  - D. WhisperX on the Mac CPU as the reference for the technique.
- **Exit criteria:** set by the owner after seeing step 5 of the bottom line. I will not propose a threshold until there is data.

## 8. Not verified

- Per-word versus per-phrase granularity of Apple's `audioTimeRange`, and whether Apple's speech models accept singing at all. Apple's documentation page returned empty when fetched, so the SDK interface was the only source.
- Any accuracy number for Whisper-DTW, WhisperX, Qwen3-ForcedAligner or Apple Speech on singing.
- Licences of the Demucs weights, the MLX Whisper repository, and the speech-swift toolkit. Whisper's own weights are MIT, which I know from general knowledge and did not check in this session.
- Real-time speed of WhisperKit and whisper.cpp on this Mac. I quote only what the READMEs claim.
- The HCLAS-X lyric aligner's accuracy (deployed in streaming services, per its abstract); the abstract gives no numbers and I did not read the paper.
- The terms of use of LRCLIB's data.

## 9. Open questions for the owner

1. Where do lyrics come from: tags and sidecar files only, a lookup service, user paste, or all three? Is transcription from audio in scope at all, given about one word in five would be wrong?
2. Word-by-word highlighting, or line-level? This sets the accuracy needed and whether hundreds of milliseconds is acceptable.
3. Which languages? Qwen3-ForcedAligner lists 11; WhisperX needs a model per language.
4. Is a model download of several hundred megabytes acceptable, and is processing time of a minute or more per song in the background acceptable?
5. Where do results live, and may they be written next to the person's audio files? The app today never writes beside them.
6. Does this feature also have to work on the iPhone version? That changes the engine choice, because Demucs MLX and several aligners are Apple Silicon Mac tools.

## 10. Decision: lyrics come from the audio, and what that changes

The owner has decided that the lyrics are transcribed from the song, not looked up. That removes the rights question about lyric text (the app would only process the person's own files, on their own Mac), and it makes the problem harder than section 1 implied.

**The target moves.** The goal was word timing as accurate as WhisperX gets on speech. On this path the error that shows first is the text: the best open-source result I found is about 20% word error on a benchmark where the language was supplied in advance (section 4). A word-by-word display of text that is one-fifth wrong, with words highlighted exactly on the beat, will look precise and be wrong. Timing accuracy only matters on words that are right.

Specific consequences, each from the evidence above or flagged as my judgment:

1. **Language must be detected, not supplied.** The Jam-ALT results gave Whisper the language. In the app there is no such input. Language identification on music is something I did not find a number for.
2. **Instrumental passages and backing vocals.** The same paper reports that over half of backing vocals and non-lexical sounds are deleted, and hallucination (inserted text unrelated to the audio) is tracked as a failure mode. A synced display must handle silence and instrumental breaks without inventing words.
3. **Confidence has to gate the display.** WhisperKit computes a per-word probability from the decoder's token log-probabilities (read in `SegmentSeeker.swift`). In my judgment a line below a confidence bar should not be shown as lyrics, or should be marked as machine-generated. Wrong lyrics shown confidently are worse than none. This is a product rule that needs the owner's decision, and it needs measuring: I have no calibration data for these scores on singing.
4. **Genre will matter.** The 2019 alignment paper reports its worst outliers on slurred hip-hop and metal.
5. **Compute is per song, and a library is large.** The one speed claim I have is Demucs separating a 3:19 track in about 15 s on an M1 Pro (README claim), before the speech model runs. I have no figure for Whisper on this Mac. A library of thousands of songs is hours of background work. The design needs a policy: on first play, on adding to a playlist, or on request, and a place to cache results.
6. **Forced alignment still has a role**, but a different one. After the text is transcribed, aligning it to the audio with a dedicated aligner may give tighter word times than the Whisper decoder's own DTW times. Also, aligning the *correct* lyrics is useful in the test as an upper bound that separates transcription error from timing error.

**Revised pipeline to test:** detect language, then segment on vocal activity (optionally after separating the vocals), then transcribe (WhisperKit or whisper.cpp), then take word times from the decoder's DTW or from a forced aligner, then filter by confidence and cache. Runs entirely offline.

**Revised spike.** Same test set (JamendoLyrics Multi-Lang plus songs chosen by the owner) and same arms as section 7, with these changes and additions:

- Report transcription word error rate **and** timing error on the words that were transcribed correctly, separately. A single combined number hides which half is failing.
- Add the correct-lyrics alignment arm as an upper bound, not as the product path.
- Measure language-detection accuracy with the language not supplied.
- Measure hallucination on instrumental sections (inserted words where the reference has none).
- Measure whether the confidence score separates right lines from wrong ones, and at what threshold a line is trustworthy.
- Measure seconds of processing per minute of audio and peak memory on the Mac the owner actually uses.

**What would make me stop.** If the best arm still gets about one word in five wrong on the owner's own music, a word-by-word display is not defensible, and the fallback is a line-level display of high-confidence lines only, or no feature. That result is plausible given the evidence, and the spike exists to find out before any app code is written.

**Open questions that remain** (the first one in section 9 is now answered):

1. What is the accuracy bar, in terms the owner would accept: for example, the share of lines that must be right before the feature is shown for a song?
2. Is "machine-generated" labelling acceptable on lines below the confidence bar, or should low-confidence lines be hidden?
3. Which languages must work? If the owner's library is mostly English, say so, because it sets the model choice and the language-detection risk.
4. When may processing run: on first play, in the background for a playlist, or only on request?

## Sources

- WhisperX README: https://github.com/m-bain/whisperX
- WhisperX paper (Bain et al.): https://arxiv.org/abs/2303.00747
- Rousso et al., forced alignment comparison: https://arxiv.org/abs/2406.19363
- Stoller et al., lyrics alignment: https://arxiv.org/abs/1902.06797
- Contrastive lyrics alignment: https://arxiv.org/abs/2306.07744
- Syed et al., source separation for lyrics transcription with Whisper: https://arxiv.org/abs/2506.15514
- WhisperKit / argmax-oss-swift: https://github.com/argmaxinc/argmax-oss-swift and `Sources/WhisperKit/Core/Text/SegmentSeeker.swift`
- whisper.cpp: https://github.com/ggml-org/whisper.cpp and `include/whisper.h`
- MLX Whisper: https://github.com/ml-explore/mlx-examples/tree/main/whisper and its `timing.py`
- Qwen3-ForcedAligner-0.6B model card: https://huggingface.co/Qwen/Qwen3-ForcedAligner-0.6B
- speech-swift: https://github.com/soniqo/speech-swift
- demucs-mlx-swift: https://github.com/kylehowells/demucs-mlx-swift
- LRCLIB: https://github.com/tranxuanthang/lrclib
- Apple Speech framework: the macOS 26 SDK interface on this machine (`Speech.framework/Modules/Speech.swiftmodule`)
