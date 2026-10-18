# PoC brief: "View lyrics" for an audio player (on-device, Apple platforms)

Written 2026-10-16. Research compiled from web sources; items marked **[UNVERIFIED]** were not confirmed and must be checked before relying on them. Treat this as a brief for an agent: build the smallest thing that answers the open questions in section 8.

## 1. Goal

Add a "View lyrics" feature to an existing audio player. For a given track, produce time-synced lyric text entirely on-device (no cloud), and show it scrolling in time with playback.

Pipeline:

```
track audio -> vocal separation -> speech/lyrics transcription (word timestamps) -> lyric view synced to playback
```

Why separate first: transcribing a full mix is poor. A vocals stem is much cleaner input. Word timings also let the UI show gaps (instrumental sections).

## 2. Target platforms

- macOS 27 ("Golden Gate", shipped 2026-09-14), Apple silicon only (Intel and Rosetta dropped).
- iOS 27. Minimum OS can be recent or latest.
- macOS 26 / iOS 26 is the floor for the transcription API; the best separation path (Core AI) needs 27.

## 3. Transcription: Apple SpeechAnalyzer / SpeechTranscriber

- Introduced in iOS 26 / macOS 26, replacing SFSpeechRecognizer. Runs fully on-device with a system-managed speech model; no network in the transcription path.
- Benchmarks (speech, not singing): on 5,559 LibriSpeech clips on an M2 Pro, 2.12% WER clean and 4.56% noisy, versus Whisper Small at 3.74% / 7.95%, at about 3x the speed. A separate vendor-published (non-independent) test on an M5 Max found 12 word edits vs whisper.cpp small.en's 26 over 607 words.
- CLI for quick experiments: `yap` (github.com/finnvoor/yap). Takes audio or video, outputs SRT, JSON, VTT, TXT. Apple silicon + macOS 26+.
- **Key caveat:** no benchmark found covers singing. The model is trained on speech. Expect degradation on held vowels, melisma, vibrato, pitch-shifted or doubled vocals, and reverb tails. This is the main PoC risk.
- Word-level timing: expected to be available via per-word time ranges in the results **[UNVERIFIED: confirm exact API (attributes such as audio time range on the transcription result) in the Speech framework docs]**.
- Fallbacks if singing accuracy is poor: whisper.cpp or MLX Whisper (Whisper models have seen more music, but can hallucinate text over silence/instrumental gaps; gate with voice-activity detection or the separation stem's energy).

## 4. Apple's built-in LLMs (Foundation Models) - role in this feature

- Foundation Models framework: Swift API to the on-device model behind Apple Intelligence. In iOS/macOS 27 it also accepts image input, Private Cloud Compute models, and third-party providers via a Language Model protocol.
- macOS 27 ships `/usr/bin/fm`, a CLI for the on-device model. On-device context window reported as 8,192 tokens; PCC model reportedly 32K (shared input+output budget).
- **Models are text/image only. They cannot hear audio**, so they are not a transcriber.
- Possible optional use: post-process the raw transcript (line breaking, punctuation, casing, repeated-chorus collapsing). Keep prompts small given the 8K window. Not needed for the first PoC.
- Music Understanding framework (new in 27): Apple says it analyses audio across six dimensions on-device. **[UNVERIFIED: whether lyrics, vocal activity, or section/structure are among them. Check the WWDC26 "Meet the Music Understanding framework" session before building anything that duplicates it.]**
- Logic Pro 11 has a stem splitter, but it is an app feature, not an API.

## 5. Vocal separation on-device

### Recommendation

Use a **vocal-specialised model** (2-stem vocal/instrumental). Only the vocals are needed, so a 4-stem model is wasted compute.

1. **Prototype in MLX on a Mac** to pick the model by ear and by downstream transcription accuracy.
2. **Ship via Core AI (macOS/iOS 27)** with STFT/iSTFT done in Swift.
3. HTDemucs is the safe fallback, not the best choice for vocals.

### Options found

| Option | Platform | Notes |
|---|---|---|
| `demucs-mlx` (pip) | Mac, MLX/Metal | ~73x realtime on M4 Max, 2.6x faster than PyTorch MPS. MIT. Good for prototyping. |
| `pymss` (pip) | Mac, MLX default | Supports bs_roformer, mel_band_roformer, htdemucs, mdx23c, bandit, scnet, apollo, vr. Easiest way to A/B models. |
| `mlx-audio-separator` (pip) | Mac, MLX | Ports python-audio-separator; Roformer, MDXC, MDX, VR, Demucs. Needs macOS 13+, Apple silicon. |
| HTDemucs on Core AI (`TrevorJS/htdemucs-CoreAI`, `arraypress/stems-demucs`) | macOS 27 | 42M params, 168 MB fp32 `.aimodel`. 4 stems. MIT. |
| BS-RoFormer on Core AI (`arraypress/stems-roformer`) | macOS 27 | 132M params, 528 MB. 4 stems. MUSDB18 test: vocals 11.08 dB SDR (avg 9.65). Heavier/slower; best vocal quality candidate. |
| MDX23C InstVoc HQ on Core AI fp16 (`arraypress/stems-mdx`) | macOS 27 | 214 MB. Vocal/instrumental only. 0.27 s per chunk on GPU; 30 s mix in ~3 s (~10x realtime). Good size/quality balance. |
| HTDemucs Core ML (`slaughters85j/htdemucs-coreml`) | macOS 15+ | **Must be fp32** (fp16 destroys spectral reconstruction). ANE rejects the graph, so it runs GPU/CPU. ~405 MB. 0.18 s/chunk on GPU on M1 Ultra (~42x realtime). |
| UVR MDX-Net Core ML fp16 (`gyoom/UVR-MDX-CoreML`) | iOS + macOS | fp16 mlpackages targeting ANE/GPU/CPU. Learned core only (STFT outside). Candidate for iOS. |
| Mini-BS-RoFormer V2 Core ML (`schism-audio/mini-bs-roformer-v2-coreml`) | iOS + macOS | 46.8M version is **CC-BY-NC (non-commercial)**; MIT 18M or HTDemucs ports available for commercial use. fp16 variant targets ANE. Stem order is bass/drums/other/vocals (not Demucs order). |

Open source Swift host code: `swift-vocal-isolation` (MIT), used by the `stems` CLI (`--engine demucs|roformer`). Reuse before writing DSP from scratch.

### iOS notes

- Core AI is listed by Apple under iOS 27, but the community separator ports found only state "macOS 27, Apple silicon". **[UNVERIFIED: iOS support for these `.aimodel` files.]**
- Memory is the constraint: chunk processing, prefer models in the ~100-250 MB range.
- Core AI tooling is young (one port used `coreai-core 1.0.0b2`, beta).

## 6. "Models cover only the network" - the DSP you must write

The model files contain only the neural network. You write everything around it:

1. **Chunk** audio into fixed segments with overlap (HTDemucs: 7.8 s = 343,980 samples at 44.1 kHz; overlap 0.25; triangular crossfade).
2. **STFT** with the exact trained parameters (FFT size, hop, window, padding, normalisation). Examples:
   - HTDemucs: 4096-sample periodic Hann, hop 1024, centred, normalised; reflect-pad by 1536 samples plus remainder; keep bins 0..<2048 of frames 2..<338.
   - MDX23C InstVoc HQ: n_fft 8192, hop 1024, periodic Hann, centred; bins 0-4095; chunk = 261,120 samples.
   - BS-RoFormer: n_fft 2048, hop 441, periodic Hann, unnormalised; chunk 485,100 samples; DC bin zeroed; applies a complex mask.
3. **Network** (the model file).
4. **Inverse STFT** with matching parameters.
5. **Overlap-add / crossfade** chunks back together.

Wrong parameters do not error; they produce muddy, phase-smeared, or swapped stems. Validate against the Python reference on identical audio (SDR/PSNR comparison); some ports publish test vectors. Complex spectrograms are fed as channels: [L_re, L_im, R_re, R_im]. Use Accelerate/vDSP for FFTs.

## 7. Suggested PoC architecture

- `LyricsPipeline` actor: `separateVocals(url) -> URL(vocals.wav)`, then `transcribe(url) -> [TimedWord]`, then `LyricLines` (group words into lines using pauses > ~0.6 s and max length).
- `TimedWord { text, start, end, confidence? }`.
- Cache results per track (hash of audio file) on disk; separation is the expensive step and must not rerun.
- Run in the background with progress; show "Generating lyrics..." state. Never block playback.
- Lyric view: scrolling list, current line highlighted from `AVPlayer`/engine playback time; tap a line to seek; show an instrumental marker for gaps beyond a threshold.
- Make the separation model and transcriber pluggable (protocols) so models can be swapped during evaluation.

## 8. PoC questions to answer (in this order)

1. Does SpeechTranscriber give usable word timestamps, and what is the API? (Check docs; confirm with a short Swift script.)
2. On 3-5 test tracks of varied style (clear pop vocal, fast rap, melismatic ballad, heavily processed/doubled vocal), what is the word error rate of SpeechAnalyzer on (a) the raw mix and (b) the separated vocal? Use tracks where ground-truth lyrics are known. Compare against whisper.cpp / MLX Whisper on the same inputs.
3. Which separator gives the best downstream transcription accuracy: MDX23C InstVoc vs BS-RoFormer vs HTDemucs? Prototype with `pymss` or `demucs-mlx` before any Swift porting.
4. Is separation fast enough? Target: well under realtime on a recent Mac; measure on the lowest-spec iPhone/Mac that must be supported.
5. Does Music Understanding framework in 27 already expose lyrics or vocal-activity? If so, simplify.
6. Does the chosen Core AI model actually run on iOS 27?
7. How are hallucinated words handled in instrumental gaps? (Gate by vocal-stem energy / VAD.)

## 9. Risks

- Singing recognition accuracy is unproven for Apple's speech model (biggest risk).
- Separation artefacts can hurt transcription more than backing music does.
- DSP parameter mismatches fail silently.
- Model licences vary per checkpoint (Demucs MIT; one RoFormer port CC-BY-NC). Check before shipping commercially.
- Core AI is beta-era tooling; APIs may shift.
- Lyrics shown are machine transcriptions of the user's own audio, not licensed lyrics; label them as auto-generated and possibly inaccurate.

## 10. Sources

- Apple SpeechAnalyzer overview: https://blog.addpipe.com/apple-speechanalyzer-api/
- SpeechAnalyzer vs Whisper benchmark summary: https://www.developersdigest.tech/blog/apple-speechanalyzer-vs-whisper-benchmark
- SpeechAnalyzer vs whisper.cpp (vendor-published): https://dev.to/iravoice/apple-speechanalyzer-vs-whispercpp-a-40-speaker-mac-benchmark-40i4
- yap CLI: https://github.com/finnvoor/yap
- macOS 27 / `fm` CLI / model family: https://rits.shanghai.nyu.edu/ai/apple-foundation-models-macos-27/
- What's new in iOS 27 (Apple): https://developer.apple.com/wwdc26/guides/ios/
- What's new in macOS 27 (Apple): https://developer.apple.com/wwdc26/guides/macos/
- Core ML vs MLX vs Foundation Models: https://blakecrosley.com/blog/core-ml-vs-mlx-vs-foundation-models
- HTDemucs Core ML: https://huggingface.co/slaughters85j/htdemucs-coreml
- HTDemucs Core AI: https://huggingface.co/TrevorJS/htdemucs-CoreAI and https://huggingface.co/arraypress/stems-demucs
- MDX23C InstVoc HQ Core AI: https://huggingface.co/arraypress/stems-mdx
- BS-RoFormer Core AI: https://huggingface.co/arraypress/stems-roformer
- UVR MDX-Net Core ML: https://huggingface.co/gyoom/UVR-MDX-CoreML
- Mini-BS-RoFormer V2 Core ML: https://huggingface.co/schism-audio/mini-bs-roformer-v2-coreml
- demucs-mlx: https://pypi.org/project/demucs-mlx/
- pymss: https://pypi.org/project/pymss/2.0.5/
- mlx-audio-separator: https://pypi.org/project/mlx-audio-separator/
