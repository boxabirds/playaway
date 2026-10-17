# Playaway vision: an artist's own SoundCloud, on Cloudflare

Written 2026-10-17. A companion to `docs/vision.md` (Spotify as the baseline for a local-files player). This document turns the other way: not what a listener gets from the industry's catalogue, but what an artist needs to publish their own catalogue, audio and video, on infrastructure they control, with fans who can talk back.

Working name in this document: **the site** (the artist's deployment) and **the app** (Playaway on Mac and iPhone). Nothing here is built. Where a claim about SoundCloud, TikTok or Cloudflare comes from memory and was not checked against a current source, it is marked [unverified]. No pricing figures are given anywhere; look them up when the design is costed.

## Premise, and how it was read

The brief: make it easy for an artist to create their own SoundCloud-style service on Cloudflare, growing to video hosting; the SoundCloud playback UI is different from Spotify's and fans can comment; three parts (admin, fan experience, Cloudflare technical design); by default the web plays the free content, and the app gives access to local content.

Two readings of "the app gives them access to local content" are possible:

1. **Members get the files.** A fan who is a member (free or paying) opens the artist's release in the Playaway app; the files are downloaded into the app's iCloud Drive folder as the fan's own local files, playable offline on Mac and iPhone with everything in `docs/vision.md` (lyrics, structure navigation, matched mix). The web is the shop window and the free listen; the app is the record collection.
2. **The artist publishes from local files.** The Mac app is the publishing tool: a Playaway playlist becomes a release; the Mac computes the waveform, loudness and lyric sheet and uploads them.

This document takes **both**, because they are the two ends of the same pipe and they are what makes this different from a plain SoundCloud clone: the artist's masters are local files on their Mac, the fan's copy ends up as local files on their phone, and the site in the middle is a Cloudflare deployment the artist owns. Reading 1 is the fan-facing promise; reading 2 is the admin-facing one.

## What it is, in one page

- **Roles.** Owner (an account that owns one or more labels), label admin, artist (a profile under a label; a solo artist is a label with one artist), fan (anonymous visitor), member (signed-in fan; free, or paying by subscription or by purchase).
- **Content.** A *piece* is one audio track or one video. A *release* groups pieces (single, EP, album, live set, video series). A *post* is a blog entry that can embed pieces. An *event* is a show or tour date. A *merch item* is a thing to buy, digital (the files) or physical (a link out, or built-in checkout).
- **Tiers per piece.** Public (anyone plays all of it), preview (anyone plays an excerpt; members play all), members (sign-in required), paid (purchase or subscription required). Set per piece, defaulted per release.
- **Talking back.** Timed comments pinned to the waveform (audio) or the timeline (video), emoji reactions at a time, replies, and the artist's own replies shown as the artist. Members only, by default; the owner can open it to anyone with a bot check.
- **Where it runs.** One Cloudflare Worker per artist deployment (static site plus API), D1 for metadata, R2 for audio and downloads, Stream for video, Durable Objects for live rooms, Queues for after-upload work, Stripe for money. Deployed from a template with one command; custom domain on the artist's own zone.
- **The app.** Publishes from the Mac; collects into the phone and the Mac. Same identity as the site.

---

## Part 1: Admin

### 1.1 Objects and ownership

| Object | Owned by | Fields (first version) | Notes |
|---|---|---|---|
| Account | itself | email, passkeys, display name | No passwords anywhere. One person may own several labels; a label may have several admins. |
| Label | Account(s) | name, slug, domain, legal name, country, payout (Stripe account id), branding | A solo artist is a label of one. Multiple labels per account is the brief's requirement, so the label is the tenant, not the account. |
| Artist | Label | name, slug, bio, avatar, header, links, ActivityPub actor | An artist belongs to exactly one label in v1; a collaboration between labels is two artist entries and a shared release [open question]. |
| Release | Label, credited to one or more artists | title, slug, type (single, EP, album, live, video series), date, artwork, notes, default tier, price | Order of pieces is the release's. |
| Piece | Release (or standalone) | title, kind (audio, video), duration, tier, preview window, master asset, renditions, waveform peaks, loudness, lyric sheet, chapters, credits, ISRC (optional) | A piece can be in several releases (a single later on an album). |
| Asset | Piece | R2 key or Stream id, bytes, checksum, codec, sample rate | Masters are kept as uploaded. |
| Post | Label, by an artist | title, slug, markdown, embeds, date, tier | The blog. |
| Event | Artist | date, venue, city, country, ticket link, set list (pieces), status (announced, sold out, cancelled, past) | Also published as an iCalendar feed. |
| Merch item | Label | name, kind (digital, physical link, physical built-in), price, stock, images, link | Digital merch is the files (FLAC, MP3, video) for a release. |
| Link | Artist or Label | kind (site, blog, Instagram, TikTok, YouTube, Bandcamp, Mastodon, Bluesky, X, Spotify, Apple Music, other), URL, show on profile | `rel="me"` on the profile so Mastodon's verification works [unverified that this is still how Mastodon verifies]. |
| Member | Label | account, joined, plan (free, subscription, purchases), Stripe customer id, email opt-in | Membership is per label, not per artist: the fan joins the label's site. |
| Comment | Piece, by a member | time (seconds), text, parent, state (visible, held, removed), pinned-by-artist | Time is nullable for a comment on the piece as a whole. |
| Reaction | Piece, by a member | time, emoji | One per member per second-bucket per emoji, to stop spam. |

### 1.2 Publishing: two paths, the Mac first

**From the Mac app.** The artist drags a Playaway playlist onto "Publish" (or a release the site already knows): the Mac already has the files and, after `docs/vision.md`'s analysis pass, the waveform peaks, per-track loudness, structure (for the preview window), and the lyric sheet. The app uploads the masters to R2 by multipart upload through presigned URLs, uploads the analysis record as JSON, and creates the release in D1 through the site's API. Video goes to Stream through its direct-upload URL [unverified name; Stream has a direct creator upload mechanism]. This is the path that needs no transcoding on Cloudflare: the Mac makes the MP3 or AAC rendition with AVFoundation before upload, and the FLAC or original for download.

**From the browser.** For an artist who does not use the Mac app. Upload in the browser straight to R2 (presigned multipart). Waveform peaks are computed in the browser from the decoded audio before upload (Web Audio decoding is fine for a 10-minute file; a 2-hour live set is a known limit [unverified figure]). Renditions are the artist's problem in v1: upload an MP3 or AAC for streaming and, optionally, a lossless file for download. Server-side transcoding is deliberately not in v1 (see 3.4).

**Release checklist, enforced by the admin UI, not by prose.** Artwork at the required sizes; every piece has a tier; paid pieces have a price or belong to a subscription; previews have a window; at least one rendition; credits; the release date (scheduled publishing is a Queue message with a delay [unverified maximum delay]).

### 1.3 Free, preview, members, paid

- **Public.** Anyone plays the whole piece. The stream URL is cacheable and short-lived anyway (3.2), so a hot-linked URL dies on its own.
- **Preview.** The default for new releases of a paying label. The excerpt is a separate pre-cut file, never the full file with a client-side stop: if the full file is reachable it is downloadable. Default window: 30 seconds starting at the most energetic section found by the Mac's structure analysis, which is usually a chorus; the artist can drag the window on the waveform. A lower-bitrate full-length preview is a second option (radio-quality full track, lossless for members) [design choice, not decided].
- **Members.** Free sign-up (email magic link or passkey). Gives the artist the fan's email, which is the single most valuable thing SoundCloud and Spotify never hand over.
- **Paid.** Two shapes, both through Stripe: a monthly or yearly subscription to the label (Patreon's model) and one-off purchase of a release (Bandcamp's model, with "pay what you want above a floor" as an option). Entitlements are rows in D1 written by Stripe webhooks; the Worker checks them when minting stream and download URLs.
- **Previews of video.** The same: a pre-cut excerpt as its own Stream video; the full video gated by Stream's signed URLs.

### 1.4 Merchandise

- v1 is **digital merch**: the files, per release, in the formats uploaded. That is the Bandcamp bargain, and the Mac and iPhone apps are the delivery mechanism for it (2.5).
- Physical merch is **links out** by default (Shopify, Bandcamp merch, Big Cartel) because stock, shipping, tax and returns are a business, not a feature.
- Built-in physical checkout (Stripe Checkout with stock counts and a shipping address) is a later option for labels that want one storefront. Tax and shipping rates are Stripe's problem then, and the label's.

### 1.5 Concerts and tours

Events with date, venue, city, ticket link, and a set list of pieces so a past show can link to a live recording. Published on the artist page, as an iCalendar feed (fans subscribe in Calendar), and in the RSS feed. A "tour" is a tag over events, not an object. Past shows stay as an archive with the recording if there is one.

### 1.6 Links and social accounts

A list of links on the profile with the platform's icon; the owner orders them. Bidirectional verification with Mastodon via `rel="me"` [unverified]. Nothing is pulled from the platforms (no embedded feeds): the links point out, and syndication (1.8) pushes out.

### 1.7 Blog

Posts in Markdown with embedded pieces (the embed is the site's own player, so a post can carry a listen). Posts have tiers too (a members-only post). Published to RSS/Atom and, if enabled, to the Fediverse (1.8). Comments on posts use the same comment table with a null time.

### 1.8 Syndication

What can honestly be automated and what cannot:

| Channel | Mechanism | Honest status |
|---|---|---|
| RSS/Atom for posts and releases | Generated from D1 by the Worker | Trivial; v1. |
| iCalendar for events | Same | Trivial; v1. |
| Embeds elsewhere (a blog, a forum) | oEmbed endpoint plus Open Graph tags so a pasted link becomes a player or a card | Small; v1. The player embed is the site's own player in an iframe. |
| Podcast-style RSS for audio | An RSS feed with enclosures so podcast apps can subscribe | Small to build, but distributing music through podcast directories can breach their policies and gets music taken down from Apple Podcasts and Spotify [unverified as to current policy]; offer it as a private feed for members only, not as a directory listing. |
| Fediverse (Mastodon and others) | The artist as an ActivityPub actor: new releases and posts are notes; fan replies on Mastodon arrive as comments; follows count as members-lite | Real work (signatures, inbox, delivery, moderation). High value for independent artists, whose fans are disproportionately there [opinion]. v2. |
| Bluesky | AT Protocol posting of a card | Smaller than ActivityPub; posting only, no replies back, in v2. |
| YouTube, TikTok, Instagram, X | Their APIs are restricted for third-party posting and change often | Do **not** promise automation. Instead generate a *post pack*: a vertical video with the waveform and the lyric lines as captions over the artwork, the excerpt the artist chose, the text and the link, downloaded as a folder and posted by hand. This is what most artists actually do today and it never breaks. |
| Spotify, Apple Music, etc. | Distributors (DistroKid, TuneCore) and DDEX | Out of scope. Link out; store the ISRC so the links line up. |

### 1.9 Comments: moderation and control

- Members only by default. Opening comments to anonymous visitors turns on Turnstile and holds every comment for approval.
- Owner controls per label: approve first or publish first; per piece: comments on or off; block a member; report and remove; pin a comment; reply as the artist (shown with the artist's avatar, the SoundCloud convention of the uploader's reply standing out [unverified]).
- Rate limits per member and per IP in the Worker. A word list is a toggle, not a default.
- Everything a member posts is exportable and deletable by them (GDPR is real for a site with EU fans; the owner is the controller, which must be said plainly in the setup).

### 1.10 Analytics, without trackers

Plays, completions, drop-off position (binned), downloads, members joined, by piece and by day, from the Worker's own logs into Analytics Engine [unverified that Analytics Engine fits this; the alternative is counters in Durable Objects]. No third-party pixel. A play counts after 30 seconds or half the piece, whichever is shorter, which matches the industry convention in spirit [unverified figure for any specific platform]. Public play counts on the site are the artist's choice per label, off by default: vanity numbers suit platforms, not artists with a hundred real fans.

---

## Part 2: Fan experience

### 2.1 What SoundCloud got right, and how its player differs from Spotify's

From memory of the SoundCloud web and iOS player; specifics are [unverified] unless they are plainly structural:

- **The waveform is the scrubber.** The whole track is visible as a waveform; the played part is coloured; you click anywhere to seek. You can see the quiet intro and the drop before you hear them. Spotify's progress bar tells you nothing about the music.
- **Timed comments live on the waveform.** Fans' avatars sit at the time they commented; hovering or passing them shows the text ("this part!"). The comments are about moments, not about the track in the abstract. This is the single feature that made SoundCloud social for musicians, and nothing in Spotify has it.
- **The player is persistent.** A bar along the bottom keeps playing while you browse profiles, sets and the stream.
- **The profile is the home page.** An artist's page is a stream of their uploads in reverse order, playable top to bottom; that is the artist's "site" on SoundCloud, and for an unsigned act it is often the only one.
- **Reposts, likes and sets.** Fans curate publicly; reposts put a track in the fan's followers' streams. On a single-artist site a repost has no inside meaning, so it becomes "share" (2.4).
- **Previews as the gate.** SoundCloud's paid tier (Go+) plays 30-second previews of gated catalogue to free users [unverified detail]. The same mechanism serves the member gate here.
- **Downloads as a feature of the upload**, set by the uploader.

What SoundCloud got wrong, which this does not copy: the feed became an algorithmic stream with ads; the artist does not own the fan relationship (no emails); the uploader pays for hosting while the platform owns the audience; the mobile app lost most of the timed-comment affordance to simplification [unverified].

### 2.2 What TikTok got right for video

Also from memory, [unverified] in details:

- **One gesture.** Full-screen vertical video, swipe up for the next one. No chrome to learn.
- **Sound on, looping.** The clip repeats until you leave; a 20-second hook gets heard three times.
- **Feedback without leaving.** Double-tap to like; the comment sheet slides up over the video, which keeps playing; replies, and the creator's reply as a video of its own.
- **The caption is on the video.** Text sits over the picture, so the video carries its own context when shared out.
- **Share makes a clip.** What leaves the app is the video itself with the account's mark on it.

What is not copied: the recommendation feed (there is one artist here, not a billion clips), duets and stitches (rights and effort), and the engineered compulsiveness. The useful residue is: vertical full-screen for short pieces, comments that do not interrupt, reactions in one tap, captions from the lyric sheet, and sharing as a clip rather than as a link.

### 2.3 The listening design

- **Home is the stream.** The artist's newest release at the top, big artwork, play. Below it, the releases, the posts and the next shows, in one column that scrolls. No tabs to learn before the first play. A label with several artists shows the artists as a row and each artist has the same page.
- **The player bar** at the bottom persists across every page: artwork, title, play/pause, a small waveform, and the open control that expands the player to the full view with the big waveform, the comments and the reactions. On the phone the expanded player is the same card the app has (one gesture up and down), so a fan who later installs the app finds nothing new to learn.
- **The waveform with pins.** Comments as avatars at their time. Tap one to read it and reply. While playing, a comment within a second of the position surfaces in a line under the waveform and fades, the SoundCloud behaviour that made the comments feel live. Members tap the waveform and hold to leave a comment at that time; the text field says "at 1:42".
- **Reactions as a heat strip.** Emoji reactions (a small fixed set chosen by the owner, hearts by default) are aggregated per second into a strip under the waveform, so the loved moments are visible before you reach them. One tap on the heart reacts at the current time; this is TikTok's double-tap moved onto the timeline. Members only, so it is a signal and not noise.
- **Lyrics.** If the piece has a lyric sheet (uploaded, or made on the Mac by the Playaway pipeline), the expanded player shows the lines in time, the same component as the app's lyrics panel. The sheet's "may be wrong" label applies only to machine sheets the artist has not corrected; the admin UI lets the artist fix the words, which is the correction loop the transcription experiment never had.
- **Sets** (playlists) by the artist are releases of type "set"; by fans, they are private in v1 (a fan's queue and liked pieces), because public fan curation on a single-artist site mostly produces duplicates.
- **Queue and continuous play** through a release and then on through the artist's catalogue, with gapless playback where the files allow it, and no crossfade by default (the artist's sequencing is the artist's).
- **Nothing autoplays with sound** on page load; the first play is the fan's tap. Keyboard: space, left and right for 5 seconds, up and down for volume. Captions on every video. Dynamic Type on the phone.

### 2.4 Talking back and passing it on

- **Comment, react, reply** as above. The artist's replies carry the artist's avatar and sort to the top of a thread.
- **Share** is the outward repost: a link with an Open Graph card that plays in a message preview where the platform allows it, or a **clip**: the fan picks up to 30 seconds on the waveform and gets a vertical video of artwork plus waveform plus the lyric lines, ready for TikTok, Instagram or a message. Clips are only ever made from public or preview-window audio, so a member cannot cut gated audio into a clip (the Worker renders the clip from the preview rendition, never from the master). Clip rendering is server-side work and needs a renderer (3.4); until then the clip is the audio plus a still image, which iOS Messages still previews.
- **Notifications** by email digest (weekly by default, or on release), by web push for members who ask for it, and by RSS. No notification is sent for a reply to a comment unless the member opts in.

### 2.5 Video

- **Short pieces** (under about 90 seconds, vertical) get the full-screen vertical feed: swipe for the next, loop, double-tap to react at that time, comments sliding up over the playing video. This is the only place the site has a "feed", and it is the artist's own clips in order, not a recommendation.
- **Long pieces** (performances, films) get the landscape player with the same timeline comments and reaction strip under the scrubber, chapters from the artist (or from the structure analysis for music), and captions.
- **Comments on video at their time** can optionally scroll across the picture as they pass (the Niconico and Bilibili convention [unverified naming of the convention]), off by default, on per piece.
- Video quality and adaptive streaming are Stream's job (3.2).

### 2.6 Members get the files: the app as the record collection

The fan-facing form of "the app gives them access to local content":

- On any release the fan is entitled to, the site shows **Open in Playaway**. On the phone that is a universal link into the app; on the Mac the same. The app signs the fan in with the site's identity (the same magic link or passkey, through the system web-auth sheet), fetches the release manifest and downloads the files (FLAC where the artist uploaded it, else the streaming rendition) into the app's iCloud Drive folder under `<Label>/<Artist>/<Release>/`, and writes a Playaway playlist document for the release.
- From then on the files are the fan's own local files, on the Mac and the iPhone through iCloud Drive as the app already syncs, offline, with the lyric sheet and analysis record (the artist's, if published) alongside, so the four features in `docs/vision.md` work on them with no extra work by the fan or the phone.
- The app's existing "in iCloud, not on this device" state is exactly the state these files are in most of the time, which is why the offloaded-placeholder fix this week matters to this design.
- Entitlement revocation (a cancelled subscription) does not reach into the fan's folder. The files are theirs, as a purchased download is on Bandcamp. The artist chooses, per release, whether a subscription gives downloads or only streaming; the default for subscriptions is streaming in the app with the files cached and removed when the subscription lapses, and for purchases it is the files for keeps. This distinction must be explained to artists in the setup, because it is the difference between Patreon and Bandcamp.

---

## Part 3: Technical: the Cloudflare web experience

### 3.1 Shape

One Worker per artist deployment, created from a template (`wrangler deploy` from a clone, or a hosted "deploy to Cloudflare" button that creates the resources [unverified current name for that mechanism]). The Worker serves the static site (its assets) and the API under one origin, on the label's own domain.

| Need | Cloudflare piece | Why this one |
|---|---|---|
| Site and API | Workers with static assets | One origin, one deploy, edge-rendered pages for Open Graph cards and oEmbed. |
| Metadata, members, comments, entitlements | D1 | SQLite, relational, one database per deployment, cheap backups by export. |
| Audio, artwork, downloads, analysis records | R2 | Object storage with no egress fee, which is the whole reason a music site is affordable to self-host [the no-egress policy is Cloudflare's stated position; check the current terms]. Byte-range requests work, which is all progressive audio needs. |
| Video | Stream | Transcoding, adaptive bitrate, signed URLs, thumbnails, and a player, none of which should be built. |
| Sessions, config, rate limits | KV, or signed cookies with no store | Sessions as signed cookies in v1; KV for revocation lists. |
| Live comment and reaction rooms, play counting | Durable Objects | One object per piece being listened to: WebSocket fan-out of new comments and reactions, aggregation of reactions per second, play counters flushed to D1. |
| After-upload work, scheduled publishing, email | Queues | Validate uploads, write peaks if supplied, send digests. |
| Bot check on sign-up and open comments | Turnstile | Free and invisible for most people. |
| Captions and transcripts (optional) | Workers AI speech-to-text | For video captions when the artist uploads none; the lyric sheet for music comes from the Mac pipeline, which is measured, where Workers AI on singing is not. |
| Money | Stripe (not Cloudflare) | Checkout, subscriptions, customer portal, tax; webhooks to the Worker. |
| Email | Email Workers for inbound; an email API (Resend, Postmark, SES) for outbound | Cloudflare does not send transactional email itself [unverified as of today]. |

Multi-tenancy: **one deployment per label** is the recommendation. It is what "their own service" means, the blast radius of a mistake is one artist, and the data is unambiguously theirs. A hosted multi-tenant variant on Workers for Platforms is possible later if a one-click offering is wanted; it changes the business, not the design.

### 3.2 Default: anyone can play the free content

- Public audio is served by the Worker from R2 with range support, `Cache-Control` for the edge, and a short-lived path token so that URLs copied out of the page expire within hours. Progressive MP3 or AAC, no HLS for audio: seeking by byte range is instant and every browser does it. (SoundCloud itself moved between progressive and HLS over the years [unverified]; for a single artist's catalogue progressive is enough.)
- Preview audio is its own object (1.3). The player uses the same code path with a different URL; the UI shows the preview window on the waveform and the gate beyond it.
- Video is Stream's player or Stream's HLS/DASH manifests in the site's own player, with public videos unsigned and gated ones signed.
- Pages are rendered at the edge with the metadata in the HTML (title, artwork, Open Graph, oEmbed discovery) so links unfurl everywhere without JavaScript; the player hydrates on top.

### 3.3 Gated content

- The Worker checks the session and the entitlement rows, then mints a signed URL: for R2 a presigned GET with a short expiry (minutes) for a stream, longer (a day) for a download; for Stream a signed token with the same expiries [unverified that Stream's tokens take arbitrary expiries; they do take an expiry].
- Downloads of a whole release are a zip built by the Worker on the fly from R2 objects (streaming, no temp storage) or, simpler and more robust, a list of per-file links the app and the browser fetch one by one. v1: per-file links.
- The app (2.6) uses the same endpoints with a bearer token from the sign-in.

### 3.4 Upload and processing, and the transcoding question

- Uploads go **directly to R2** from the browser or the Mac through presigned multipart URLs; the Worker never proxies bytes. A Queue message after completion validates the object (size, magic bytes, duration from the container header), records it, and marks the piece ready.
- **Waveform peaks** come with the upload (Mac or browser), as a small JSON array of per-pixel min and max; the Worker stores it in R2 next to the master and the player fetches it. If missing, the piece shows a flat bar until the artist re-uploads; v1 does not compute peaks server-side.
- **Transcoding audio** is the open problem: Workers cannot run ffmpeg. Options: (a) the client does it (the Mac app with AVFoundation, the browser with WebCodecs or an ffmpeg build in WebAssembly, which is slow and heavy); (b) Cloudflare's container offering [Containers were announced as a beta in 2025; availability and limits unverified]; (c) require the artist to upload the streaming rendition. **v1 is (a) for the Mac and (c) for the browser.** The same choice covers clip rendering (2.4): the Mac renders clips for the artist's post packs; fan clips wait for (b) or ship as audio plus still.
- **Video** is uploaded to Stream directly (direct creator upload) and Stream does the rest.
- Masters are never modified. An artist can replace a rendition; the master's checksum is the identity of the piece for the analysis record, which is the same key the app's lyric store uses, so a sheet made on the Mac matches the file the fan downloads.

### 3.5 Comments and reactions, live

- Writes go to D1 through the Worker with the rate limit and moderation state applied. The Worker then posts to the piece's Durable Object, which broadcasts to the open WebSockets (everyone with the expanded player open on that piece) and keeps the per-second reaction histogram in memory, flushed to D1 periodically.
- Reads for a cold page come from D1 (comments) and R2 or D1 (the reaction strip as a small array); live updates from the object. If the object is unavailable, the page works without live updates; nothing depends on the socket.
- Moderation state lives in D1; the object only relays what the Worker accepted.

### 3.6 Identity and money

- **Sign-in**: email magic link first (the Worker sends a link through the outbound email API; the link carries a one-time code), then a passkey offered after the first sign-in. No passwords, no OAuth with the platforms in v1 (the social links point out; nobody signs in with TikTok).
- **Sessions** as signed cookies with a rotation; revocation by a short deny list in KV.
- **Membership and purchases** through Stripe Checkout; the Worker's webhook handler writes entitlements and the Stripe customer portal handles cancellations, so the site never stores card data.
- **The app** signs in through the system web-auth sheet to the same magic-link flow and receives a long-lived token scoped to downloads and streams.

### 3.7 Syndication endpoints

RSS/Atom, iCalendar and oEmbed are routes on the Worker reading D1. Open Graph images are rendered at the edge from the artwork and the title [unverified which image-rendering library runs in Workers today; a pre-rendered image per release at publish time is the fallback]. ActivityPub (v2) adds an actor per artist with its inbox and outbox as routes, a Queue for delivery and retries, and signature verification in the Worker; the comment table gains a "remote" origin so replies from Mastodon appear as comments and can be moderated the same way.

### 3.8 The Mac as publisher

The Mac app gains a "Publish" side: sign in to a label's site, pick a playlist or folder, map it to a release, run the analysis pass if it has not run, encode renditions, upload masters, renditions, peaks and the analysis record, and create or update the release. Everything the app already has (local files, playlists as documents, the lyrics pipeline, iCloud Drive) is reused; the new code is the API client, the encoder and the upload. The AppleScript automation API gets the same verbs (the project rule: UI and AppleScript parity, both tested).

### 3.9 Operations the artist must understand

- **Backups**: a nightly export of D1 and a copy of the R2 bucket to a second bucket or to the Mac (the Mac already has the masters; the site's unique data is the members and the comments). Exports are a folder of JSON and files, so leaving is always possible.
- **Legal**: a DMCA agent and a takedown path even for original music (false claims happen); a privacy page naming the label as the controller; terms for members; age gating where the content needs it. The template ships these as pages to edit, not as advice.
- **Rights**: the site is for music the artist owns or has licensed. Cover versions need mechanical licences in most countries; the admin UI asks and records the answer per piece, it does not enforce it.
- **Costs**: scale with storage and video minutes, not with plays, because of R2's egress policy and Stream's pricing model [unverified beyond the egress point]; give artists a calculator in the admin UI fed by their actual usage, not a guess in a document.

---

## Part 4: Honest assessment

### 4.1 What this is, and what it is not

This is not a feature of Playaway. It is a second product (a hosting platform with accounts, payments, moderation, legal exposure and support) that happens to share Playaway's identity model, player card, lyrics pipeline and file sync. Playaway as it stands has three jobs: play this file, play this playlist, manage playlists. This adds two more for two new kinds of user: publish my catalogue (artist) and collect this artist's catalogue (fan). The shared parts are real and are the reason to do it from here rather than from scratch, but the unshared parts (Stripe, D1 schema, moderation, ActivityPub, the admin UI, the web player) are most of the work.

### 4.2 Who else does this

From memory and [unverified] in every detail; check before positioning against any of them:

- **Bandcamp**: the money model (buy the release, get the files, pay what you want) and the artist page; no timed comments, no video to speak of, takes a cut, not self-hosted.
- **SoundCloud**: the player and the timed comments; the artist pays to host and does not own the audience.
- **Patreon**: the membership model; a poor player; no release structure.
- **Faircamp**: a static site generator that turns a folder of music into a Bandcamp-like site; self-hosted, no accounts, no comments, no payments beyond links. The closest in spirit to "your own site from your own files". A strong reason to make the public, static half of this site at least as good, and to be clear that the dynamic half (members, comments, money) is what Faircamp does not do.
- **Funkwhale**: self-hosted, federated (ActivityPub) audio platform; heavy to run; a reference for the federation design.
- **Ampwall, Mirlo, Nina, Subvert**: newer artist-first storefronts and co-operatives (2023 to 2025); not self-hosted.

The gap this fills, if the reading above is right: **self-hosted on commodity edge infrastructure, audio and video in one, timed comments, membership with the fan's email in the artist's hands, and the fan's copy as real files in a real player.** No one on that list has all of those; whether any artist wants all of those at once is the question the first deployment answers.

### 4.3 The uncomfortable parts

- **The buyer is narrow.** "An artist who can run `wrangler deploy`" is a small set, and the artists who most need their own site are the least likely to be in it. Either a hosted one-click variant exists from early on, or the realistic user is a technical fan or manager running it for an artist. Decide which before building the admin UI, because it changes who the admin UI is for.
- **Payments make it a business for the artist and a support burden for whoever ships the template.** Stripe disputes, VAT on digital goods in the EU, refunds. The template can wire it; it cannot absorb it.
- **Moderation is a job.** Comments at scale need a human. Members-only comments and approve-first defaults keep it survivable for a small artist; they also keep it quiet.
- **Transcoding on Cloudflare is not solved** in this design; the Mac app carries it. That makes the Mac app a hard dependency for the full experience, which is fine for the owner's own use and a real limit for a general release.
- **Opportunity cost.** The lyrics experiment is half measured (the eval has not run on real ground truth), the Mac's iCloud stories are unstarted, and the phone's card has unverified behaviour on a real device. This document costs a day; building its v1 costs months. The honest sequencing is below.

### 4.4 Order of work, if this goes ahead

1. **Public static half** (weeks): template Worker, D1 schema, R2 upload from the Mac, the waveform player with the persistent bar, releases, posts, events, links, RSS, Open Graph. No accounts. Already better than a Linktree, comparable to Faircamp with a better player. Measure: one real artist's catalogue on a real domain.
2. **Members and comments** (weeks): magic-link sign-in, timed comments and reactions with the Durable Object, moderation, email digests. Measure: real comments from real fans on real moments.
3. **Money and files** (weeks): Stripe, previews, entitlements, downloads, "Open in Playaway" on iPhone and Mac. Measure: a purchase that ends as files on a phone.
4. **Video** (weeks): Stream, the vertical feed for short pieces, timeline comments on video, captions.
5. **Syndication beyond RSS** (open-ended): post packs first (cheap, honest), ActivityPub second.

Each step ships on its own and is useful on its own. If step 1 does not get used by a real artist, stop there.

### 4.5 Open questions for the owner

1. Is the first artist you, or someone you know? The answer sets whether the admin UI is a form or a product.
2. Hosted one-click, or template only? (4.3, first point.)
3. Subscription (Patreon), purchase (Bandcamp), or both in v1? Both doubles the entitlement logic and the explaining.
4. Does the app bridge (2.6) belong in step 3 or step 1? It is the most distinctive thing here and also the one that touches the shipping app.
5. How much of the Mac app's publishing side should be AppleScript-first so a script can publish a release without the UI? (The parity rule says both, but one can lead.)
