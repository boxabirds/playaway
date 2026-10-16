# Playaway vision: Spotify, local music and AI on today's hardware

Written 2026-10-16. Part 1 is a baseline catalogue of Spotify's music playback features on iOS, researched from public sources (Spotify support pages first, press and Spotify Community second); anything not confirmed by a source is marked [unverified]. Part 2 is design: four features for Playaway that use the phone's own hardware, with costs, risks and a measure for each.

Playaway: an iPhone and Mac player for the person's own audio files. No streaming, no library import, playlists as documents, iCloud Drive sync. Domain play.away.software, repo github.com/boxabirds/playaway.

---

## Part 1: Spotify's music playback on iOS, catalogued

### Grouping rule

The catalogue is grouped **by function**: what the listener is doing (A to H below). Each feature has exactly one entry, under the function it serves. Surfaces (Now Playing view, mini player, queue, lock screen and Control Center, Dynamic Island, CarPlay, widgets, Siri, Apple Watch) are not a second catalogue: section I is a matrix that says which function IDs each surface exposes and what is specific to that surface. Where a surface has behaviour that exists nowhere else (the lock screen widget, the Watch's own downloads), that behaviour is a row in section I and nowhere else.

Scope: music only. Podcasts and audiobooks are excluded, including their speed and sleep controls.

Two columns recur:

- **Tier**: Free or Premium, as the support page states it. "Not stated" means the page does not say.
- **Needs Spotify's catalogue or servers?** Yes means the feature depends on Spotify's content, metadata, recommendation or streaming infrastructure and so cannot be applied to local files as-is. No means it is a property of the player and a local-files player can have it. Partly means the mechanism is local but the data behind it is server-side.

### Common anatomy (so entries can refer to it)

- **Now Playing bar** (the mini player): a bar at the bottom of every screen while something plays. Tap opens the Now Playing view. Swiping the bar left or right changes to the next or previous track (Spotify Community staff reply) [S23].
- **Now Playing view**: full-screen. Top: a chevron to close, the context name (playlist or album), a three-dot menu. Middle: album art, or Canvas looping video behind it. Below: title and artist, the plus (save) button, the progress bar, then the control row (shuffle, previous, play/pause, next, repeat). Bottom row: the Connect device icon, share icon, queue icon. Below the controls: the Lyrics preview card. Swiping the album art left or right changes track [S23]. The exact placement of the Connect, share and queue icons is from the support pages for those features; the row order is [unverified].
- **Three-dot menu** (in Now Playing): Add to playlist, Add to queue, Sleep timer, Lyrics preview toggle, Share, Go to album/artist, and more [S8, S14].
- **Settings and privacy > Playback**: Crossfade slider, Automix, Gapless playback, Autoplay, Equalizer, Enable Audio Normalization and its Loud/Normal/Quiet level, Include Smart Shuffle in play modes [S2, S3, S4, S5, S17].
- **Settings and privacy > Media Quality**: streaming quality for Wi-Fi and cellular, download quality, Auto-adjust [S6].

### A. Transport: play, pause, skip, previous, scrub

| ID | Feature | How it works on iOS | States and edge cases | Tier | Needs catalogue? |
|---|---|---|---|---|---|
| A1 | Play / pause | One button: Now Playing bar, Now Playing view (large centre button), lock screen, Control Center, Dynamic Island, CarPlay, Watch, Siri. | Playback is remote-controllable: when the phone is the Connect controller for another device the button drives that device [S9]. | Free, Premium | No |
| A2 | Next | Next button in the Now Playing view; swipe art or bar left [S23]; lock screen next; Siri "skip". | **Free on mobile**: since 15 Sep 2025 free users can "pick and play" chosen tracks for an undisclosed daily allowance of on-demand time; when it runs out, the older limit of a restricted number of skips per hour returns (the historic figure is six per hour, reported but not in a current Spotify page) [S24, S25]. Premium: unlimited. | Free (limited), Premium | No (the limit is a business rule, not a technical one) |
| A3 | Previous | Previous button; swipe art or bar right. | Whether a first tap restarts the current track after some seconds and a second tap goes back, as in most players, is [unverified] for Spotify's iOS app. | Free (limited as A2), Premium | No |
| A4 | Scrub | Drag the handle on the progress bar in the Now Playing view; times shown either side. The lock screen and Control Center progress bar is the system's and is draggable. | A Spotify Community bug report says tapping a point on the iOS bar does not seek, only dragging the handle does; whether that is still so is [unverified] [S22]. Free users cannot scrub when in the shuffle-only state [unverified]. | Free, Premium | No |

### B. What plays next: order, shuffle, repeat, queue, autoplay, DJ

| ID | Feature | How it works on iOS | States and edge cases | Tier | Needs catalogue? |
|---|---|---|---|---|---|
| B1 | Shuffle (plain) | Shuffle button in the control row, or on the playlist/album/artist page. Off: tracks play in order. On: tracks play randomly [S1]. | Premium can pick a **shuffle style** in settings: "Fewer repeats" tracks what was recently played and picks among several random sequences by a freshness score (reduces, does not eliminate, repeats); "Standard" gives every track an equal chance and ignores recent plays [S1]. | Free, Premium (style choice Premium) | No |
| B2 | Smart Shuffle | Third position in the shuffle cycle: off, Shuffle, Smart Shuffle ("tracks and personalized recommendations play randomly"). Recommended tracks carry an "Enhance" badge beside the artist name in the Now Playing bar [S1]. | Premium turns it off for good with Settings > Playback > "Include Smart Shuffle in play modes". **Free on mobile: Smart Shuffle is always active** [S1]. Works on the user's own playlists and Liked Songs. | Premium (optional), Free (forced) | **Yes** (recommendations) |
| B3 | Repeat | Repeat button, cycles: off, repeat all (icon green), repeat one (icon shows "1"), off [S26]. | Repeat overrides Autoplay (Community staff) [S17]. Third-party guides say repeat is Premium-only on mobile [unverified] [S26]. | Premium on mobile [unverified] | No |
| B4 | Queue | Queue icon at the bottom of the Now Playing view. Add: a track's three-dot menu > Add to queue, or swipe right on a track. Reorder: press and hold the drag handle and move. Remove: swipe left. Clear: queue icon > Clear [S8]. | The support page labels the mobile section "For: Premium"; press reports that queuing stays Premium-only after the 2025 free-tier change [S8, S24]. Spotify has no separate "Play next" command on iOS distinct from Add to queue, as far as the support page goes [unverified]. The queue view shows the manual queue above the continuation from the current context ("Next up" / "Next from") [unverified naming]. | Premium | No |
| B5 | Autoplay | Settings > Playback > Autoplay. When an album, playlist or set of songs ends, Spotify continues with related tracks [S17]. | Repeat overrides it. One setting applies to all devices on the account (Community staff, 2023) [S17]. | Free, Premium | **Yes** (related-track selection) |
| B6 | AI DJ | A "DJ" item that plays a personalised stream with spoken commentary between songs. Press and hold the DJ button, wait for the beep, and say a request ("electronic beats for a midday run") [S27]. | Voice requests are English only and in 60 countries at the time of reporting. | Premium | **Yes** (entirely) |

### C. Transitions and sound: crossfade, gapless, automix, mix, quality, loudness, EQ, speed

| ID | Feature | How it works on iOS | States and edge cases | Tier | Needs catalogue? |
|---|---|---|---|---|---|
| C1 | Crossfade | Settings > Playback > Crossfade: drag the slider to set the length. "Overlaps 2 tracks by fading out of the first while fading in the next" [S2]. | Slider range is not stated on the support page (commonly reported as 0 to 12 seconds) [unverified]. Cannot be set while using Spotify Connect [S2]. A Community thread reports that any crossfade above 0 disables Automix [S2b]. | Premium | No |
| C2 | Gapless playback | Settings > Playback > Track transitions > Gapless playback toggle. "Removes any gaps or pauses that may occur in between tracks" [S2]. | Cannot be set over Connect. | Not stated | No |
| C3 | Automix | Settings > Playback > Track transitions > Automix toggle. "Allows beat-matched seamless transitions between songs on select Spotify playlists". "Works even on Shuffle" [S2]. | Only on Spotify-made playlists (Community moderator). Not over Connect. | Premium | **Yes** (only Spotify's own playlists; server-side transition data) |
| C4 | Mix (custom transitions) | Open one of your own playlists > "Mix" in the toolbar. "Auto" makes instant blends; presets such as "Fade" and "Rise"; or edit the transition by hand with volume, EQ and effect curves over a waveform with beat markers, with BPM and Camelot key shown to help beatmatching. Saved mixes stay with the playlist; a Mix button toggles them on and off; Premium friends can collaborate [S28, S29]. | Beta from August 2025; desktop editing from May 2026 [S29]. Only on playlists the user created. | Premium | **Partly** (the beat, waveform and key data is Spotify's; the editing is a player function) |
| C5 | Streaming and download quality | Settings > Media Quality. Levels: Automatic (depends on network), Low (about 24 kbit/s), Normal (about 96), High (about 160), Very high (about 320), Lossless (up to 24-bit/44.1 kHz FLAC). Separate settings for Wi-Fi, cellular and downloads. Auto-adjust (on by default) lowers quality to avoid stuttering [S6]. | Lossless launched 10 Sep 2025 for Premium, must be switched on per device and per connection type; a "Lossless" label shows in the Now Playing view/bar and the Connect picker; Bluetooth cannot carry it, so Spotify recommends wired or Wi-Fi/Connect playback [S7, S7b]. Over Connect, quality is changed on the phone for the target device [S9]. | Very high and Lossless: Premium | **Yes** as a stream choice; for local files quality is a property of the file |
| C6 | Volume normalization | Settings > Playback > "Enable Audio Normalization". "Balances soft and loud songs". Level: Loud (for noisy surroundings, "less dynamic levels"), Normal (default), Quiet [S4]. | Not changeable over Connect. | Premium | No (needs per-track loudness, which can be computed locally) |
| C7 | Equalizer | Settings > Playback > Equalizer toggle. "Choose a preset, or drag the dots on the equalizer" [S5]. | The page names neither the presets nor the band count (commonly reported as six bands) [unverified]. Not over Connect. | Not stated | No |
| C8 | Volume | The phone's hardware buttons and the system slider. Over Connect, an in-app slider in the Connect menu; Apple discontinued the technology that let the hardware buttons drive a Connect device [S9]. | In a Jam, shared volume only on Chromecast and Amazon Cast, not Bluetooth or AirPlay [S10]. | Free, Premium | No |
| C9 | Playback speed (music) | **None.** Speed controls exist for podcasts and audiobooks only (Community staff) [S30]. | May 2026 user reports of a "Change song speed" item in a song's three-dot menu, not confirmed by Spotify [unverified] [S30b]. | n/a | n/a |

### D. What is shown while playing: lyrics, canvas

| ID | Feature | How it works on iOS | States and edge cases | Tier | Needs catalogue? |
|---|---|---|---|---|---|
| D1 | Time-synced lyrics | A "Lyrics preview" card under the art (or over Canvas) in the Now Playing view; scroll down to the Lyrics section and tap it for full screen. Lines are shown "as they're sung", the current line highlighted [S14]. | Lyrics preview is on by default; toggle via the three-dot menu > Lyrics, which applies to all tracks. Not on music videos. Availability varies by song, market and device by rights agreements [S14]. Lyrics come from Musixmatch (press, 2021) [S15]. Lyrics are on Free and Premium [S14]. There is no scoring or microphone karaoke mode on the support page; "Sing it with Spotify" is marketing wording. | Free, Premium | **Yes** (licensed text and timings from Spotify's servers) |
| D2 | Share lyrics | In full-screen lyrics, tap the share icon at the bottom, tap lines to highlight them, tap Share, pick a social app; a lyric card is generated [S14]. | | Free, Premium | **Yes** (same text) |
| D3 | Canvas | Short looping video behind the art in the Now Playing view, supplied by the artist. Settings > Content and display > Canvas toggle; since April 2026 the same place switches off all video in the app, and the choice applies across devices [S16, S16b]. | Canvas-like video can still appear on some audio ads. | Free, Premium | **Yes** (artist-uploaded assets) |

### E. Where it plays: devices and routes

| ID | Feature | How it works on iOS | States and edge cases | Tier | Needs catalogue? |
|---|---|---|---|---|---|
| E1 | Spotify Connect | Tap the "Connect device" icon at the bottom of the Now Playing view and pick a device; the phone becomes a remote and the device streams from Spotify directly [S9]. | First connection needs the same Wi-Fi; iPhone must allow Local Network access; playback may need reconnecting after a pause over 10 minutes; identically named devices must be tried in turn [S9]. Audio settings (C1, C2, C3, C6, C7) cannot be changed over Connect. | Not stated | **Yes** (the device pulls the stream from Spotify) |
| E2 | AirPlay and Bluetooth | The same device list offers AirPlay and Bluetooth routes, and the system AirPlay picker in Control Center works too; both carry the phone's own audio output [S9b]. | AirPlay needs the same network; Bluetooth does not need the internet. Lossless cannot be carried over Bluetooth (C5). | Free, Premium | No (system routes) |

### F. Sessions and social: sleep timer, Jam, share, like

| ID | Feature | How it works on iOS | States and edge cases | Tier | Needs catalogue? |
|---|---|---|---|---|---|
| F1 | Sleep timer | Now Playing view > three-dot menu > Sleep timer. Durations reported by several guides: 5, 10, 15, 30, 45 minutes, 1 hour, or End of track; turn off via the same menu ("Turn off timer") [S11]. | I could not reach a current Spotify support page for the music sleep timer; durations are from third-party guides [unverified]. One guide says the in-app timer does not act on Connect playback [unverified] [S11b]. | Free, Premium | No |
| F2 | Jam | Mobile: Connect device icon > "Start a Jam"; Spotify may offer to start one automatically when connecting to a smart or Bluetooth speaker. Invite by QR code, "Share link", bringing phones within 1 m with Bluetooth on, or automatic invitations on the same Wi-Fi. Guests choose remote or in person, then Join. Anyone in the Jam can control playback unless the host turns off "Let others change what's playing", after which guests only add songs. Host can remove participants; if the host leaves, the Jam ends. CarPlay: "Queue & Jam" from the Now Playing view [S10]. | Premium to start or host; Premium to join remotely; Free can join in person. No participant limit stated. | Premium (host) | **Yes** (entirely) |
| F3 | Save / like from the player | The plus button in the Now Playing view (replaced the heart in March 2023). First tap saves to Liked Songs and the icon becomes a green check; a second tap opens the playlist picker with checks against playlists the song is already in [S18]. | Existing saves were unaffected by the change. Siri "like this" does the same [S19]. | Free, Premium | No (the equivalent for local files is add-to-playlist) |
| F4 | Share from the player | Share icon in the Now Playing view: link, message, Instagram Stories (art plus an audio snippet, viewers tap "Open on Spotify"), Instagram Notes; August 2025 added audio previews and real-time listening notes [S20, S20b]. | Lyric sharing is D2. | Free, Premium | **Yes** (links resolve to Spotify's catalogue) |

### G. Offline

| ID | Feature | How it works on iOS | States and edge cases | Tier | Needs catalogue? |
|---|---|---|---|---|---|
| G1 | Downloads for playback | On an album or playlist, tap the download arrow; individual songs cannot be downloaded, add them to a playlist first. Up to 10,000 tracks per device on up to 5 devices; exceeding 5 removes downloads from the least recently used device. Must go online at least once every 30 days to keep downloads. Settings > Data-saving and offline: Offline mode toggle (non-downloaded content greys out) and Downloads over cellular [S12]. | Download quality is a separate Media Quality setting (C5). | Premium (music) | **Yes** (the whole mechanism; local files are already local, but the "is this file on this device" state has a direct analogue in iCloud Drive placeholders) |

### H. History

| ID | Feature | How it works on iOS | States and edge cases | Tier | Needs catalogue? |
|---|---|---|---|---|---|
| H1 | Playback history | Profile picture > Listening history, grouped by date; also a "Recently played" row on Home (which shows albums, artists and playlists rather than tracks) [S21]. | Third-party guides report no way to delete entries on mobile and about three months of history [unverified] [S21]. A Private Session pauses listening activity shown to friends [S9]. | Free, Premium | No (local history is trivial; Spotify's is also the basis for recommendations) |

### I. Surfaces: which functions each exposes, and what is specific to it

| Surface | Functions exposed | Surface-specific behaviour | Source |
|---|---|---|---|
| Now Playing bar (mini player) | A1, A2, A3 (swipe) | Tap opens the Now Playing view. "Enhance" badge marks Smart Shuffle picks (B2). "Lossless" label (C5). | S1, S7b, S23 |
| Now Playing view | A1 to A4, B1 to B4, D1 to D3, E1, F1 (menu), F3, F4 | Swipe art to change track; swipe down to close. | S8, S14, S23 |
| Queue view | B4 | Separate screen, reached from the Now Playing view. | S8 |
| Lock screen and Control Center | A1 to A4, C8, E2 | iOS's system Now Playing controls, fed by the app; the progress bar is the system's. The **Spotify lock screen widget** (iOS 16+, Spotify 8.8.26+) is added via long-press > Customize > Lock Screen; while music plays it shows the previous control view and tapping opens the app; if greyed out, Spotify suggests re-login and checking the "Devices Lock Screen" setting [S31]. iOS 26 opened animated lock-screen artwork to third-party players; whether Spotify adopted it is [unverified] [S32]. | S31, S32 |
| Dynamic Island | A1, A2, A3 | The system's Now Playing presence for any background-audio app (iOS 16.1+); tapping it expands to a mini player with controls and the AirPlay route [S33]. | S33 |
| CarPlay | A1 to A4, B4, F2, Siri | Spotify's CarPlay app with Home, Now Playing, "Queue & Jam". The phone-side **Car View** was retired in late 2021 with no replacement; the "Hey Spotify" wake word was removed from the phone app in July 2022; the Car Thing accessory stopped working in December 2024 [S34, S35, S36]. One guide says Siri in CarPlay needs Premium on iOS 15.4+ [unverified] [S37]. | S10, S34 to S37 |
| Siri | A1, A2, C8, F3, B6, plus play by song/album/artist/playlist/mood | Add "on Spotify" to the request if Siri plays from another app; Siri learns the preference with use. Siri with Apple Intelligence needs iPhone 15 Pro or later, iOS 27, English; classic Siri needs iOS 14+. Commands listed: play songs, albums, artists, playlists; play music for a mood or activity; play your DJ; recommend something; create a playlist; like; skip, play/pause, volume [S19]. | S19 |
| Home screen widgets | H1 (content) | Two sizes: the larger shows up to five recently played covers (artists, playlists, albums), the smaller the last played cover; tapping starts it [S31b]. | S31b |
| Apple Watch | A1, A2, A3, C8, E1 (as remote), G1 (its own) | Series 4 or later, watchOS 10 or later. Premium: stream over cellular or Wi-Fi, and download for offline ("at least 10 hours depending on model", 100 downloads per playlist) from the watch or from the phone's three-dot menu "Download to Apple Watch". Free: remote control of other devices only [S13]. | S13 |

### Summary: what transfers to a local-files player

Transfers as-is (player functions): A1 to A4, B1, B3, B4, C1, C2, C6, C7, C8, E2, F1, F3 (as add-to-playlist), H1, and the system surfaces (lock screen, Control Center, Dynamic Island, CarPlay via the CarPlay audio template, Siri via App Intents, widgets, Watch).

Transfers only with on-device analysis in place of Spotify's servers: C3/C4 (beat and key data), C6 (per-track loudness), D1/D2 (lyric text and timing), B2/B5 (recommendation from the person's own library only), G1 (iCloud Drive placeholder state as the analogue of "downloaded").

Does not transfer: B6 (DJ), D3 (Canvas), E1 (Connect), F2 (Jam), F4 as Spotify links, C5 as a stream choice.

---

## Part 2: Four features for Playaway

### How these four were chosen

Candidates: lyric transcription (required), song-structure navigation, key/tempo-matched crossfade, "find the moment" semantic search, stem control, smart playlists, voice-only control, spatial audio. The framing is "Spotify, local music and AI": the feature must be one Spotify sells (Part 1) or plainly cannot sell for local files, it must run on the phone the person already owns, and it must be honest about the accuracy ceiling.

Chosen: **1. Lyrics on the device** (required, and already under way), **2. Structure navigation** (MusicUnderstanding gives the data for nearly nothing; Spotify has no equivalent), **3. Mix: matched crossfade and loudness** (Spotify's Automix, Mix and normalisation are Premium, server-side and catalogue-only; the same analysis pass as feature 2 pays for most of it), **4. Find the moment** (builds on feature 1's transcripts and on feature 2/3's analysis; only possible because the files are the person's own).

Rejected, with reasons:

- **Stem control (mute vocals, boost bass).** The separator is the slowest and heaviest thing in the current pipeline: about 25x real time on a Mac, unmeasured on a phone, and a two-stem UVR MDX-Net model that is not a four-stem one. Live separation during playback is out; precomputed stems double or quadruple storage per song. Karaoke additionally needs lyrics good enough to sing from, which feature 1 cannot yet promise. Revisit when feature 1 settles the separator's phone cost.
- **Smart playlists from listening and analysis.** Spotify's analogues (Smart Shuffle, Autoplay, DJ) draw on a catalogue of 100M tracks; across one person's few thousand files the output is a sort order, not discovery. Feature 4 covers the useful part ("songs like this one") as a search result instead of a generated playlist.
- **Voice-only control.** App Intents and Siri already give "play X", "skip", "pause"; a bespoke wake word in-app is what Spotify removed in 2022. No win.
- **Spatial or head-tracked audio.** AVAudioEnvironmentNode and CMHeadphoneMotionManager make it possible, but for stereo music it is an effect, not a job. Nothing in the product's three jobs (play this file, play this playlist, manage playlists) asks for it.

### Shared groundwork: one analysis per song, done once, done on the Mac when possible

All four features need per-song data that costs seconds to minutes to compute. The design principle, applied everywhere below:

- **An analysis record per song**, keyed by the audio file's content hash (as the lyric sheet store already does), holding: MusicUnderstanding results (rhythm, key, structure, pace, loudness, instrument activity), the lyric sheet, and line embeddings. Computed in the background, never in the audio render path, never blocking playback.
- **Synced through iCloud Drive** next to the playlists, so whichever device finishes first serves the other. The owner's own numbers make this the main lever: Whisper large-v3 is "much slower" on the phone than on the Mac, the separator runs 25x real time on the Mac and is unmeasured on the phone, and SpeechTranscriber did 5:51 of audio in 3.1 s on an M-series Mac. The Mac does the heavy passes while plugged in; the phone reads the result. The phone falls back to its own, cheaper pass only when the Mac has not been seen.
- **Schedule by battery state**: heavy passes (Whisper, separation) only while charging or above a battery floor, with `ProcessInfo.thermalState` checked; light passes (Apple Speech, MusicUnderstanding) on demand.

What is not known and must be measured first: MusicUnderstanding's time per song on an iPhone (Apple publishes no figure; the WWDC session only says to request only the analyses you need [A3]).

---

### Feature 1: Lyrics on the device

**User outcome.** Pull the player card up and read the words of the song as they are sung, for any file, without the song being in anyone's catalogue. Tap a line to jump to it. The person knows the words are a machine's guess and can fix a line.

**What exists today.** `LyricsPipeline` (separate vocals when asked, transcribe, gate words to vocal ranges, group into lines, keep in `LyricSheetStore`); two engines (`SpeechAnalyzerTranscriber` on iOS 26, `WhisperKitTranscriber` large-v3, 626 MB download); `MDXNetSeparator` (Core ML, UVR MDX-Net, own vDSP STFT); `StemEnergyActivity` and `MusicUnderstandingActivity` vocal gates (the latter reads `InstrumentActivityResult.ranges[.vocal]` and `StructureResult.phrases`); `LyricsPanel` in the player card (Make Lyrics, progress with time estimate, lines with the current one bold, low-confidence lines dimmed, instrumental marker, tap-to-seek); an Experiments screen with engine choice, separator toggle, model downloads and a benchmark.

**How it works in the UI (changes from today).**

- *Player card, lyrics panel.* No "Make Lyrics" button in the normal path: the first time a song is played with lyrics on, the panel shows "Listening for the words…" with the existing progress row and a Cancel, and the Apple Speech pass runs immediately. Words appear within seconds on the phone (the owner's finding: Apple is fast). A small "draft" caption marks an Apple-only sheet. When a Whisper (or Mac-made) sheet arrives later, the panel swaps to it with no animation beyond the caption changing to the engine name; the swap never happens while the person is scrolling (the existing `userScrollHold` rule).
- *Correction.* Long-press a line to edit its text in place; the edit is stored in the sheet with the word timings kept, and syncs with the sheet. A corrected line is never overwritten by a later engine pass. This is the only "karaoke" promise that can be kept at the current accuracy.
- *Instrumentals.* The existing "· · ·" marker is driven by MusicUnderstanding vocal ranges on iOS 27, by stem energy on iOS 26 with the separator, and by nothing otherwise.
- *Line breaking.* Lines are cut at MusicUnderstanding phrase boundaries first, then by the pause rule; this is the one place the structure data improves the text without touching the words.
- *Floating controller.* Nothing new. Lyrics are a card-only surface, as now.
- *Playlist screen.* A row's context menu gets "Make Lyrics" (and "Make Lyrics for Playlist") so a person can prepare a playlist while charging. The row shows no lyric state; the card does.
- *Experiments screen.* Stays for engine choice and the benchmark until the defaults below are settled, then shrinks to one toggle.

**Default pipeline.** Apple Speech on the raw mix first, gated by MusicUnderstanding vocal ranges, shown as a draft. Then, when charging (or on the Mac), Whisper large-v3 on the raw mix, gated the same way, replacing the draft. The separator is off by default: published results say separation barely helps Whisper, and on the Winterreise study singing style, not accompaniment, drove the errors [R1, R2]. The separator remains an Experiments option for songs where the draft is unreadable.

**On-device capability.** Speech framework `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26; per-word `audioTimeRange` and per-word confidence, as verified by the owner); WhisperKit large-v3 via Core ML (ANE/GPU); MusicUnderstanding (iOS 27) `instrumentActivity` and `structure`; Core ML UVR MDX-Net separator (optional); Foundation Models (iOS 26) as an optional post-pass for casing and punctuation only, never for "fixing" words it cannot hear.

**Cost.** Apple Speech: seconds per song on the phone, no download (system model). Whisper large-v3: 626 MB once; minutes per song on the phone (owner's observation; exact figure per device to be benchmarked with the existing benchmark button), about 3 s per song class of speed on the Mac. Separator: adds roughly 1/25 of the song's duration on the Mac, phone unmeasured. Storage: a sheet is a few kilobytes per song. Battery: Whisper on the phone is a sustained ANE/GPU load for minutes; hence charging-only by default.

**Accuracy: known versus guessed.** Known: Whisper is about 20% word error on sung lyrics in published benchmarks and separation gives little [R1]; Apple's model is trained on speech and is less accurate than Whisper on singing (owner's phone tests); timing from Apple's word boundaries is good enough for line highlighting (a third-party refinement tool reports about 110 ms mean error on clean speech) [R3]. Guessed: that 20% WER reads as "right enough to follow" for pop vocals and "wrong" for rap and heavily processed vocals; that the phrase-boundary line breaking makes a visible difference. Not known: Apple's WER on singing, Whisper's time per song on each phone model.

**Risks.** The accuracy ceiling: there is no on-device path to Spotify-grade lyrics for every song, and the product must say so in the panel (it does). Hallucinated words over instrumentals when the gate is weak (iOS 26 without the separator has no gate). Model licensing for the separator checkpoint. Lyrics shown are transcriptions of the person's own file, not licensed lyrics; sharing them as cards (D2) is out.

**How we'd know it works.** On a fixed set of 20 songs with known lyrics across four styles, median WER under 20% for the final sheet and line-highlight offset under 300 ms; in use, fewer than one line edit per song on average.

---

### Feature 2: Structure navigation: skip to the part you want, loop a section

**User outcome.** On the scrubber, see the song's sections. Tap one to jump there. Hold one to loop it on bar boundaries. Double-tap Next to go to the next section rather than the next song. Spotify has nothing like this for any tier.

**How it works in the UI.**

- *Player card, scrubber.* Under the slider, a row of section ticks drawn from `StructureResult.sections`, the current one filled. Tap a tick: seek to the section start, snapped to the nearest beat from `RhythmResult`. Sections are unlabelled by Apple (the framework returns boundaries: sections, segments, phrases; the session says "you can think of a section as a chorus, verse, intro or bridge" but does not label them) [A1, A3]. So the ticks carry no names; the ones that repeat (near-identical length and loudness profile) are drawn heavier, which is the product's guess at "chorus".
- *Loop a section.* Long-press a tick: the section loops. The repeat button shows a section glyph while looping; tapping it clears the loop. The loop's end is the section end snapped back to a bar boundary so it never cuts mid-beat. This reuses the engine's existing loop mechanism (the scrub loop already lives inside the engine under the single audio lease).
- *Next within the song.* Double-tap Next in the card or the floating controller: next section. Single tap stays "next song". This is the one gesture that touches the floating controller.
- *Floating controller.* Nothing visible changes; the double-tap only.
- *Playlist screen.* Nothing. Structure is a card feature.
- *Fallback.* iOS 26 or an unanalysed song: no ticks, no section gestures. The scrubber looks exactly as today.

**On-device capability.** MusicUnderstanding (iOS 27) `MusicUnderstandingSession(asset:)` with `analyze(for: [.structure, .rhythm, .loudness])`; `AVURLAssetPreferPreciseDurationAndTimingKey` set as Apple recommends [A3]. Snapping uses `RhythmResult` beats and bars. The owner's code already calls this session for phrases.

**Cost.** One analysis per song, cached in the song's analysis record and synced. Time per song on the phone is unmeasured (Apple publishes none); request only the three analysis types. Storage: a few hundred bytes to a few kilobytes per song (beat lists are the largest part). Battery: one background pass per song, cheap compared with feature 1.

**Accuracy: known versus guessed.** Known: the framework returns a hierarchy of sections, segments and phrases and beat positions with BPM, on-device, offline [A1, A3]. Guessed: that section boundaries land where a listener would put them for pop and rock; that the "repeated section = chorus" heuristic is right more often than not; that beat snapping is clean for music with a steady tempo and poor for rubato, classical and ambient. Not known: boundary precision in seconds, behaviour on songs without a clear structure.

**Risks.** Unlabelled sections make "skip to chorus" a guess; the UI must not print "Chorus" unless the heuristic is validated. Classical and spoken-word files produce meaningless ticks (hide ticks when sections are fewer than three or the tempo is nil). Gesture overload on the scrubber: tap and long-press on ticks must not fight the slider's drag; ticks sit below the slider, not on it.

**How we'd know it works.** On 30 songs, a person marks where the chorus starts; the heavy tick lands within 2 s of it in at least 80% of songs; section-loop boundaries are judged "clean" (no audible cut) in 90% of loops.

---

### Feature 3: Mix: matched crossfade and loudness for local files

**User outcome.** A playlist can be played as a continuous set: each song hands over to the next on a bar, in a compatible key when it can, at a consistent loudness. Spotify sells this three ways, all Premium and all restricted to its own catalogue (Automix on Spotify's playlists, Mix on the user's, normalisation on streams). Playaway does it for the person's own files.

**How it works in the UI.**

- *Playlist screen.* In the playlist's menu, "Mix: Off / Smooth / Matched". It is a property of the playlist document, so it syncs and the Mac honours it. Off: today's behaviour (gapless where the files allow). Smooth: a plain crossfade of a fixed length, started on a bar boundary near the end of the outgoing song. Matched: the transition below.
- *Player card.* During the last section of a song in Matched mode, a small caption under the scrubber: "Next: Song title, in 8 bars". The scrubber's section ticks (feature 2) show where the handover will start. No knobs, no curves, no waveform editor: Spotify's Mix editor is a DJ tool for people making shareable sets; Playaway's playlists are for listening.
- *Floating controller.* Nothing new.
- *Loudness.* A single setting, in Settings, "Even out volume" with Spotify's three levels (Quiet, Normal, Loud) mapping to a target of about -18, -16 and -14 LUFS with a true-peak limiter; gain is applied per song from its measured integrated loudness. This is C6 from Part 1 done locally and it works in all three Mix modes.
- *Fallback rules (the honest part).* Matched falls back to Smooth when: the two songs' BPM differ by more than 8% after allowing a half or double tempo; either tempo is nil; either structure has fewer than three sections; the key relation is a clash (more than two steps on the Camelot wheel) and the handover would overlap sung vocals in both songs (vocal ranges from instrument activity). Smooth falls back to gapless when either file is shorter than twice the crossfade.

**How a matched transition is built.** Out-point: the start of the outgoing song's last section, or 16 bars before the end if the last section is longer. In-point: the start of the incoming song's first section after its intro (second section). Tempo: the incoming song is nudged by up to 4% toward the outgoing song's BPM for the overlap, then eased to its own tempo over 8 bars. Alignment: the incoming first beat lands on the outgoing bar's downbeat. Levels: an equal-power crossfade over 8 bars, with a high-pass sweep on the outgoing song's low end over the last 4 bars so two bass lines never sum. All offsets are computed in advance from the analysis record; nothing is analysed in the render path.

**On-device capability.** MusicUnderstanding `rhythm` (beats, bars, BPM), `key` (tonic and mode over time ranges), `loudness` (ITU-R BS.1770 integrated, short-term, momentary, peak), `structure`, `instrumentActivity` [A1]. Tempo nudging with `AVAudioUnitTimePitch` (tempo without pitch change) or `AVAudioUnitVarispeed` (with); a second player node and a mixer in the existing `AVAudioEngine` graph; a limiter via `AVAudioUnitEffect` or a hand-written one in vDSP. The engine currently enforces one audio lease so that two sources can never sound together; Matched mode is the one case where two sources must sound together under one lease, so the lease must own both nodes. This is the largest engineering change in the four features.

**Cost.** Analysis: the same pass as feature 2 plus key and loudness. Runtime: two decoders and one time-pitch unit during the overlap only; a time-pitch unit costs measurable CPU and must be bypassed outside the overlap. Memory: two decode buffers. Storage: nothing beyond the analysis record. Battery: slight; the overlap is 8 bars per song.

**Accuracy: known versus guessed.** Known: the loudness figures follow BS.1770, so normalisation will match what broadcast and streaming services do [A1]; beat positions and BPM are provided; key is provided over time ranges. Guessed: that Apple's beat grid is tight enough to align two songs by ear (an error of 20 ms is a flam, 50 ms is a mess); that the second-section in-point is a musical place to arrive for most pop; that the fallback thresholds are right. Not known: how often two consecutive songs in an ordinary person's playlist pass the Matched rules at all. If that rate is under half, Matched is a demo, and Smooth plus loudness is the product.

**Risks.** A bad beatmatch sounds worse than no crossfade; the fallback rules are the product, not the matching. Tempo nudging on acoustic or vocal-heavy music is audible even at 4%; vocal-over-vocal overlap must be avoided by the vocal-range rule. The engine change touches the one invariant the codebase guards most carefully (one sound at a time); the sound ledger over the test suite must be extended so two-source overlap is allowed only inside a transition window. Files with silence padding defeat the out-point unless trailing silence is trimmed from the loudness data first.

**How we'd know it works.** Blind A/B of 40 transitions from real playlists: Matched judged "as good or better" than Smooth in at least 70% of the transitions where it engaged, never "broken" in more than 5%; loudness: the spread of integrated loudness across a played playlist falls from the files' own spread to under 2 LU.

---

### Feature 4: Find the moment: search the person's songs by what is sung and how they feel

**User outcome.** Type "the one about the lighthouse" or "slow, minor, piano, about leaving" on the Playlists screen and get moments: a song and a timestamp, with the matching line shown. Tap one and it plays from there. Also, from the player card: "More like this" lists the person's own songs nearest in tempo, key, pace and loudness. Spotify's search runs on its servers over its catalogue; this runs on the phone over the person's files, including the ones no catalogue has.

**How it works in the UI.**

- *Playlists screen.* A search field at the top (standard `.searchable`). Results in two groups: "Moments" (song, artist, the matched lyric line with the matching words bold, a timestamp) and "Songs" (title match, then feel match). Tap a moment: the song starts at the line's start time, the player card opens with the lyrics panel scrolled to that line. Tap a song: it plays from the top.
- *Player card.* A "More like this" row below the controls (above the lyrics panel) when the song has an analysis record: up to five of the person's songs, nearest by the feel vector; tap to play next (which gives Playaway a "play next" that Spotify's iOS app does not clearly have, B4).
- *Playlist screen.* The same search, scoped to the playlist.
- *Floating controller.* Nothing.
- *Honesty in the UI.* Moment results come from machine transcriptions, and the result row says "from transcribed lyrics". A query that matches no transcript falls through to title, artist and album text; it never shows nothing when there is a title hit.

**How it works underneath.**

- *Text index.* Every lyric line (feature 1's sheets) is indexed two ways: exact and fuzzy words (a trigram or stemmed-token index, in SQLite FTS5 or in memory for a few thousand songs), and a sentence embedding. Exact and fuzzy word matching does most of the real work: people remember words, and at 20% WER a line still contains most of them.
- *Embeddings.* `NLEmbedding.sentenceEmbedding(for:)` (NaturalLanguage, on-device; Apple's own documentation points to `NLEmbedding` for similarity and reserves `NLContextualEmbedding` for classification and tagging) [A4]. One vector per line, cosine similarity to the query vector, brute force over the index (a few hundred thousand vectors at most; fine in Accelerate).
- *Feel vector.* From the analysis record: BPM, key (as a point on the circle of fifths so neighbours are near), pace, integrated loudness, vocal share (from instrument activity), duration. Normalised, weighted, nearest-neighbour. No learning; a fixed distance.
- *Query understanding.* Optional: the Foundation Models framework (iOS 26, about 3B parameters, on-device, with `@Generable` structured output) turns "slow minor piano songs about leaving" into `{ tempo: slow, mode: minor, words: ["leaving"] }` [A5]. This is a nice-to-have; a hand-written parser for "slow", "fast", "minor", "major" covers most of it and does not need Apple Intelligence hardware.

**On-device capability.** NaturalLanguage `NLEmbedding` sentence embeddings; SQLite FTS5 (in the system's SQLite) or an in-memory index; Accelerate for similarity; MusicUnderstanding results from features 2 and 3; Foundation Models optionally. Nothing leaves the phone.

**Cost.** Embedding a line is milliseconds; a song of 100 lines is well under a second after transcription. Storage: a 512-dimensional float vector is 2 KB; 100 lines per song is 200 KB; 5,000 songs is 1 GB, which is too much. Store 16-bit halves and only lines with confidence above the low-confidence threshold, or embed per phrase-group rather than per line: target under 50 KB per song, 250 MB for 5,000 songs. Battery: negligible after transcription. The whole feature's real cost is feature 1's cost, which it inherits.

**Accuracy: known versus guessed.** Known: transcripts are about 20% wrong by word; every wrong word is a missed exact match and noise in the embedding. Known: `NLEmbedding` assets may need to be present on the device and sentence embeddings have returned nil on some OS versions in developer reports [A4]; the index must degrade to word search. Guessed: that recall for a remembered phrase of four or more words is high enough to feel like magic; that "more like this" by the feel vector produces lists a person would call sensible for pop and electronic music and nonsense for a mixed library of classical and podcasts-as-files. Not known: all of it until measured; there is no published benchmark for lyric search over noisy transcripts.

**Risks.** It is only as good as feature 1, and it makes feature 1's errors visible in a new place. A library without lyrics made yet searches titles only, so the first-run experience depends on the background pass having run (the Mac does it; feature 1's groundwork). Index size if done naively. Foundation Models availability is limited to Apple Intelligence devices and regions; the feature must not depend on it.

**How we'd know it works.** 50 queries written by the owner from memory of songs in the test library, before looking at the transcripts: the right moment in the top three for at least 70% of queries that quote words, and the right song in the top three for at least 50% of queries that describe feel.

---

### Order of work and what to measure first

1. Measure, on the oldest supported iPhone: MusicUnderstanding full `analyze()` time per song; Whisper large-v3 time per song; the separator's time per song. These three numbers decide the defaults for every feature above. The benchmark button exists; add the analyses to it.
2. Build the analysis record and its iCloud Drive sync, with the Mac as the preferred producer. This is shared by all four features and is cheap.
3. Feature 1 defaults (Apple draft, Whisper refinement when charging, phrase-based line breaking, line correction).
4. Feature 2 (ticks and loop) on top of the record: the smallest UI, the biggest "Spotify cannot do this" moment.
5. Feature 3 loudness first (pure gain, no engine change), then Smooth, then Matched behind the fallback rules.
6. Feature 4 word search first (no embeddings), then "more like this", then embeddings if word search leaves people wanting.

---

## Sources

Spotify (support pages and newsroom first; press and Community where no support page could be reached)

- [S1] Spotify Support: Shuffle play and Smart Shuffle, https://support.spotify.com/us/article/shuffle-play/
- [S2] Spotify Support: Track transitions (crossfade, Automix, gapless), https://support.spotify.com/us/article/tracks-transitions/
- [S2b] Spotify Community: Automix not working if crossfade is enabled (iOS), https://community.spotify.com/t5/iOS-iPhone-iPad/auto-mix-not-working-if-crossfade-is-enabled/m-p/5472972
- [S3] Spotify Support: Volume normalization (iOS and Android paths), https://support.spotify.com/us/article/volume-normalization/
- [S4] Spotify Support: Audio normalization, https://support.spotify.com/us/article/audio-normalization/
- [S5] Spotify Support: Equalizer, https://support.spotify.com/us/article/equalizer/
- [S6] Spotify Support: Audio quality, https://support.spotify.com/us/article/audio-quality/
- [S7] TechRadar: Spotify Lossless is finally here (Sept 2025), https://www.techradar.com/audio/spotify/audiophiles-rejoice-spotify-lossless-is-finally-here-and-its-a-huge-step-for-the-streaming-service
- [S7b] Sound & Vision: Premium subscribers get Spotify's lossless audio (Lossless indicator, Bluetooth), https://www.soundandvision.com/content/premium-subscribers-get-spotifys-long-awaited-lossless-audio
- [S8] Spotify Support: Play queue, https://support.spotify.com/us/article/play-queue/
- [S9] Spotify Support: Spotify Connect, https://support.spotify.com/us/article/spotify-connect/
- [S9b] iPhone Life: How to play Spotify on HomePod using AirPlay (device list shows AirPlay and Bluetooth), https://iphonelife.com/node/278779
- [S10] Spotify Support: Jam, https://support.spotify.com/us/article/jam/
- [S11] How-To Geek: How to set up a sleep timer in Spotify, https://www.howtogeek.com/749269/how-to-set-up-a-sleep-timer-in-spotify/
- [S11b] iGeeksBlog: How to set a Spotify sleep timer on iPhone and Mac, https://www.igeeksblog.com/how-to-set-spotify-sleep-timer-on-iphone-mac
- [S12] Spotify Support: Listen offline, https://support.spotify.com/us/article/listen-offline/
- [S13] Spotify Support: Spotify on Apple Watch, https://support.spotify.com/us/article/apple-watch
- [S14] Spotify Support: Lyrics, https://support.spotify.com/us/article/lyrics/
- [S15] Music Business Association: Spotify rolls out real-time lyrics globally (Musixmatch), https://musicbiz.org/news/music-biz-member-spotify-rolls-out-real-time-lyrics-feature-globally/
- [S16] Spotify Community: View album cover instead of a video in loop (Canvas toggle path), https://community.spotify.com/t5/Other-Podcasts-Partners-etc/View-album-cover-instead-of-seeing-a-video-in-loop/m-p/7132384
- [S16b] TechCrunch: Spotify now lets everyone turn off all videos in its app (April 2026), https://techcrunch.com/2026/04/09/spotify-now-lets-everyone-turn-off-all-videos-in-its-app/
- [S17] Spotify Support: Autoplay, https://support.spotify.com/us/article/autoplay/ ; Community staff on repeat overriding Autoplay, https://community.spotify.com/t5/Desktop-Windows/Why-does-Spotify-play-random-songs-when-a-playlist-finishes/m-p/5401715
- [S18] Spotify Community blog: The Heart button is being replaced with a Plus button, https://community.spotify.com/t5/Community-Blog/The-Heart-button-is-being-replaced-with-a-Plus-button/bc-p/6020353
- [S19] Spotify Support: Siri and Spotify, https://support.spotify.com/us/article/siri/
- [S20] Spotify Newsroom: Instagram sharing with audio previews and real-time listening notes (Aug 2025), https://newsroom.spotify.com/2025-08-21/spotify-takes-instagram-sharing-to-the-next-level-with-audio-previews-and-real-time-listening-notes/
- [S20b] Techloy: You can now share Spotify songs with sound on Instagram, https://www.techloy.com/you-can-now-share-spotify-songs-with-sound-on-instagram/
- [S21] Tom's Guide: How to see your Spotify listening history, https://tomsguide.com/how-to/how-to-see-your-spotify-listening-history ; Android Authority (no deletion on mobile), https://androidauthority.com/spotify-listening-history-3072454
- [S22] Spotify Community: Can't tap into scrub/seek bar on iOS, https://community.spotify.com/t5/iOS-iPhone-iPad/BUG-Can-t-tap-into-scrub-seek-bar-on-iOS-devices/td-p/5936342
- [S23] Spotify Community staff reply on swiping the album cover or the play bar to change track, https://community.spotify.com/t5/Other-Podcasts-Partners-etc/Remove-the-feature-for-swipe-back-to-the-main-menu-for-mobile/td-p/5735163
- [S24] TechCrunch: Spotify will now let free users pick and play tracks (15 Sep 2025), https://techcrunch.com/2025/09/15/spotify-will-now-let-free-users-pick-and-play-tracks/
- [S25] MobileSyrup: Spotify's free users can now pick songs but there is a small catch, https://mobilesyrup.com/2025/09/16/spotifys-free-users-can-now-pick-songs-but-there-is-a-small-catch/
- [S26] Android Authority: How to repeat a song on Spotify, https://androidauthority.com/how-to-repeat-song-spotify-3073051 ; Technipages (Premium-only on mobile claim), https://www.technipages.com/how-to-loop-a-song-on-spotify-android-ios-web
- [S27] Tom's Guide: Spotify's AI DJ now takes requests, https://www.tomsguide.com/entertainment/music-streaming/spotifys-ai-dj-now-takes-requests-heres-how-it-works
- [S28] Android Authority: Spotify playlists get custom transitions (Mix), https://www.androidauthority.com/spotify-playlists-custom-transitions-3588565/
- [S29] Spotify Newsroom tag page for transitions (Mix beta, Mixed By hub, desktop May 2026), https://newsroom.spotify.com/tag/transitions
- [S30] Spotify Community staff: playback speed only for podcasts and audiobooks, https://community.spotify.com/t5/Desktop-Mac/How-to-adjust-playback-speed-on-Mac-Desktop/m-p/5657394
- [S30b] PiunikaWeb: Spotify testing option to change song speed (May 2026, user reports), https://piunikaweb.com/2026/05/23/spotify-testing-option-to-change-song-speed-bpm/
- [S31] Spotify Support: Spotify lock screen widget on iPhone, https://support.spotify.com/article/spotify-iphone-widget
- [S31b] Galaxus: Thanks to widget, Spotify gets better on iPhones (home screen widget sizes), https://galaxus.at/en/page/thanks-to-widget-spotify-gets-better-on-iphones-27325
- [S32] Benzinga: Apple opens iOS 26 lock screen animation to Spotify and other third-party music apps (report), https://cdn1.benzinga.com/markets/tech/25/06/45942472/apple-opens-ios-26-lock-screen-animation-to-spotify-and-other-third-party-music-apps-report
- [S33] Tom's Guide: iOS 16.1 Live Activities and Dynamic Island apps (Spotify mini player), https://tomsguide.com/news/ios-161-live-activities
- [S34] TechRadar: Spotify is retiring Car View, https://www.techradar.com/news/spotify-is-retiring-the-car-view-mode-that-made-listening-while-driving-easier
- [S35] Spotify Community: "Hey Spotify" disappeared from iPhone app (deprecated 18 July 2022), https://community.spotify.com/t5/iOS-iPhone-iPad/Hey-Spotify-disappeared-from-iPhone-app/m-p/5448572
- [S36] Spotify Support: Car Thing discontinued, https://support.spotify.com/us/article/car-thing-discontinued
- [S37] CarTechStudio: Spotify on Apple CarPlay (Siri Premium claim, unverified), https://cartechstudio.com/blogs/in-vehicle-apps/spotify-apple-carplay

Apple frameworks

- [A1] Apple Developer Documentation: Music Understanding framework (iOS 27; rhythm, key, loudness, pace, structure, instrument activity), https://developer.apple.com/documentation/musicunderstanding
- [A2] Apple Developer: SpeechAnalyzer and SpeechTranscriber (Speech framework, iOS 26); third-party write-up of `audioTimeRange` attribute, https://dev.to/arshtechpro/wwdc-2025-the-next-evolution-of-speech-to-text-using-speechanalyzer-6lo
- [A3] WWDC26 session 253: Meet the Music Understanding framework, https://developer.apple.com/videos/play/wwdc2026/253/
- [A4] Apple Developer Documentation: NLContextualEmbedding (notes NLEmbedding for similarity), https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding ; developer forum report of nil sentence embeddings, https://developer.apple.com/forums/thread/672465
- [A5] Create with Swift: Exploring the Foundation Models framework (iOS 26, on-device model, @Generable), https://createwithswift.com/exploring-the-foundation-models-framework/

Research

- [R1] Syed et al. 2025, Exploiting Music Source Separation for Automatic Lyrics Transcription with Whisper (Jam-ALT, MUSDB-ALT), https://arxiv.org/abs/2506.15514
- [R2] Berendes, Schwär, Müller 2024, Lyrics Transcription in Western Classical Music with Whisper: Winterreise case study (WER 0.56 sung vs 0.14 spoken; singing style dominates), https://aclanthology.org/2024.nlp4musa-1.3/
- [R3] Desert Ant Labs, Align: on-device word-timestamp refinement for Apple SpeechAnalyzer (113.5 ms mean error reported for Apple's raw boundaries on clean speech), https://huggingface.co/desert-ant-labs/align

Playaway sources read for Part 2: `docs/prd.md`, `docs/view-lyrics-poc-brief.md`, `ios/App/PlayerChrome.swift`, `ios/App/LyricsPanel.swift`, `ios/App/ExperimentsView.swift`, `Sources/PlayawayCore/Lyrics/*`, `Sources/PlayawayLyrics/StemVAD.swift`.
