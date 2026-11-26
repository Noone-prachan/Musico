# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

People who want one native place on Windows and Android to listen to music offline and keep track of upcoming anime releases.

## Product Purpose

Musico combines an offline personal music library and player with an anime release calendar, watchlist, and episode or premiere reminders. Success means users can keep and play music on their device, find openly licensed tracks to download, and follow releases they care about.

## Capabilities and Constraints

- The built-in music catalogue downloads only Wikimedia Commons audio with supported public-domain, CC0, CC BY, or CC BY-SA terms and preserves attribution. There is no user-configured direct file-link download flow.
- Users can import local audio and video. Video playback uses files selected from the device.
- Users can import Spotify playlist metadata exports. Spotify audio itself is not downloaded or added to the Musico library.
- Users can search YouTube in-app by song, artist, or video name and download results as MP3 (audio, re-encoded with FFmpeg) or MP4 (video, quality selectable, muxed without re-encoding) for personal offline playback. Metadata and thumbnails are saved with the media.
- Users can create local playlists and automatically retrieve exact-title, exact-artist artwork matches from Openverse when the library loads or audio is imported, limited to public-domain, CC0, CC BY, or CC BY-SA images. Track titles and artists are sent for artwork search; media files stay local.
- Users can save per-track playback trim points; trimming never rewrites the original audio file. Autoplay, shuffle, repeat, sorting, and volume are adjustable in Music.
- Android supports background music playback with media controls and video Picture-in-Picture.
- Settings provides playback preferences, release reminders, and ZIP backup and restore for settings, saved lists, caches, playlist metadata, and local media.
- Lyrics are looked up from LRCLIB when internet is available, using track metadata rather than uploading media.
- Anime release and schedule data comes from AniList and is cached locally for reference.
- Release reminders are available on Android. On Windows, optional schedule refresh runs only while Musico is open.
- Downloads are for personal offline use; users are responsible for the rights to the content they save. Do not bypass DRM or extract protected streams.

## Brand Commitments

- Preserve the product name, Musico.
- Keep the experience native on Windows and Android.

## Evidence on Hand

- The existing Flutter source code contains the music player, local video library, licensed music catalogue, online lyrics lookup, anime calendar, watchlist, and reminder workflows.
- The user provided the Musico logo. Use its full lockup on launch and its symbol-only mark for compact app surfaces and platform icons.
- Give the compact symbol a circular black background.

## Product Principles

- Make offline playback and on-device ownership clear.
- Keep music licensing and attribution visible and honest.
- Treat media files as local; do not upload them for lyrics or playback.
- Make release schedules, saved titles, and reminders easy to understand.
- Preserve responsive behavior across Windows and Android.
