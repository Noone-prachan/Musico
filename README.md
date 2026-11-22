# Musico

Musico is a native Flutter app for Windows and Android. It keeps an offline audio
library and local video files alongside an anime release calendar, watchlist,
and release reminders.

## Requirements

- Flutter 3.50 or newer
- Android SDK and accepted Android licenses for Android builds
- Visual Studio Build Tools with the Desktop development with C++ workload and
  the C++ ATL component for Windows builds
- Windows Developer Mode enabled so Flutter can create plugin symlinks

Check the setup with:

```powershell
flutter doctor -v
```

## Run

From this directory:

```powershell
flutter pub get
flutter run -d windows
```

For the already-built desktop app, open
`build\windows\x64\runner\Release\Musico.exe`. Keep the rest of the `Release`
folder beside it. Do not open `build\windows\x64\Musico.sln` or the
`Musico.vcxproj` file; those are Visual Studio project files, not the app.

For Android, connect a device with USB debugging enabled, then run
`flutter devices` to find its device ID:

```powershell
flutter run -d <device-id>
```

To install Musico on an Android phone without Android Studio:

1. Build the single ARM64 release APK with
   `flutter build apk --release --target-platform android-arm64,android-x64`.
2. Copy `build\app\outputs\flutter-apk\app-release.apk` to the phone.
3. Open the APK on the phone and allow your file manager to install unknown
   apps when Android prompts you.
4. Tap **Install**, then open Musico.

The APK is locally signed for installation/testing; it is not a Play Store
release. This package targets 64-bit ARM Android phones and x86_64 emulators.
To install over USB with Android Platform Tools, run
`adb install -r build\app\outputs\flutter-apk\app-release.apk`.
Android does not request runtime permissions during installation. File imports
use Android's picker, and downloads stay in Musico's private app storage.
Notification access is requested during first-run setup; it is not required for
importing or saving media.

The app's **Settings** destination contains playback preferences, release
reminders, direct-download links, and backup/restore.

## Build

```powershell
flutter build windows
flutter build apk --split-per-abi
```

The Windows app is written to `build\windows\x64\runner\Release`. Android APKs
are written to `build\app\outputs\flutter-apk`.

Build the single-file Windows installer and release bundle with:

```powershell
.\installer\build_musico_release.ps1
```

This creates `%USERPROFILE%\Downloads\Musico-Release\Musico-Setup.exe`,
`Musico-Windows-x64.zip`, and the matching SHA-256 file in the same folder. The
single setup EXE contains the verified app bundle and installs without needing
another download. A tagged GitHub Actions build publishes the setup EXE and
package to a release. Windows YouTube search uses the `yt-dlp` and Deno files
bundled by the installer, so it does not need a manually supplied API key.
Android builds continue to use InnerTube search and need `YOUTUBE_API_KEY`
passed at build time.

To publish an update, attach both `Musico-Windows-x64.zip` and
`Musico-Windows-x64.zip.sha256` to a GitHub Release in
[`Noone-prachan/Musico`](https://github.com/Noone-prachan/Musico). The ZIP
contains the complete Windows app, `yt-dlp.exe`, and Deno under one top-level
`Musico` folder. The setup defaults to `%LOCALAPPDATA%\Programs\Musico` for the app and
`%USERPROFILE%\Downloads\Musico` for media storage.

To make Windows Start search recognize the app, build it and install the
per-user Start Menu shortcut:

```powershell
flutter build windows --profile
.\windows\install_musico.ps1 -Configuration Profile
```

The script copies the complete Windows bundle to
`%LOCALAPPDATA%\Programs\Musico` and creates a `Musico` shortcut in your Start
Menu. The supplied Musico mark is embedded in the app icon used by the title bar,
taskbar, and shortcut. Close the installed app before running the script again to
update it.

Run the analyzer and focused model tests with:

```powershell
flutter analyze
flutter test
```

## Music, video, and lyrics

- Musico copies imported audio into its managed `music` folder and plays it
  offline; the original file is left untouched. On Windows, this folder is
  `%APPDATA%\Musico\Musico\music`.
- The built-in music catalogue downloads Wikimedia Commons files only after
  checking for supported public-domain, CC0, CC BY, or CC BY-SA terms.
- Configured downloads accept direct HTTPS audio/video file URLs. The user must
  declare the rights basis; Musico checks the URL and returned media type, not
  copyright ownership. Attribution and rights details are saved with the media.
- Video playback is for files selected from the device. Videos remain local and
  can play offline.
- Lyrics are looked up automatically when connected to the internet. Musico sends
  the track title and artist to LRCLIB; it does not upload the audio or video.
  When LRCLIB provides timestamps, the current line follows playback in the
  lyrics preview and full lyrics view. Plain lyrics remain available when
  timestamps are not provided.
- Configured links do not scrape web pages, extract streaming-service media, or
  bypass DRM. YouTube and known streaming-service URLs are rejected by the
  *configured links* feature.
- In Music, choose **Download from YouTube** to search YouTube by song, artist,
  or video name and save results directly in-app. Results show title, channel,
  duration, and thumbnail. Download as **MP3** (best-available audio,
  re-encoded with FFmpeg/libmp3lame, thumbnail embedded) or **MP4** (video-only
  + audio streams muxed with `-c copy`, quality selectable). Pick the video,
  then use **Save as** to choose the name of the downloaded file; that name is
  written into the embedded tags and into a `.metadata.json` sidecar next to
  the media (along with the original YouTube title, channel, URL, duration,
  quality, thumbnail and file size). Downloads are for personal offline
  listening; you are responsible for the rights to what you save. This feature
  bundles FFmpeg (the `ffmpeg_kit_flutter_new_audio` LGPL build) on Windows and
  Android.
- YouTube video URLs can still be looked up in-app for public title/channel
  metadata without downloading.
- Spotify playlist JSON exports can be imported as metadata. Matching songs can
  be downloaded in-app only when an authorized direct file URL is configured;
  Spotify audio and protected streams are never extracted.
- Missing artwork is automatically searched through Openverse when the library
  loads or audio is imported, using exact title-and-artist matches and images
  licensed public domain, CC0, CC BY, or CC BY-SA. The search sends only the
  title and artist; audio files are never uploaded. Artwork attribution and
  license details are kept with the track.
- Android music playback continues in the background with a media notification
  showing track details and playback controls. Videos can continue in
  Picture-in-Picture when you leave the app.
- Musico bundles Space Grotesk and IBM Plex Mono under the SIL Open Font
  License; notices are in `assets\fonts\LICENSE.txt`.

## Direct download links and backups

Settings > **Direct download links** provides the editable
`media_downloads.json` location on Windows. The starter template is
[`config/media_downloads.json`](./config/media_downloads.json). Add entries
under `music`, `video`, or `anime`; each needs a unique `id`, title, direct file
URL, and rights declaration. CC BY and CC BY-SA entries also need attribution.
Anime entries must be direct video-file links. Web pages, playlists, and stream
manifests are not download links. On Android, export the JSON, edit it, then
import the edited copy. The app downloads selected files into its local audio
or video library without opening a browser.

Example music entry:

```json
{
  "id": "my-track",
  "title": "My Track",
  "artist": "Artist",
  "url": "https://files.example.org/my-track.mp3",
  "rights": "cc_by",
  "attribution": "Artist",
  "licenseUrl": "https://creativecommons.org/licenses/by/4.0/"
}
```

Supported `rights` values are `public_domain`, `cc0`, `cc_by`, `cc_by_sa`,
`user_owned`, and `permission`. Rights values are user declarations, not
automatic license verification.

## Spotify playlist metadata

In Music, choose **Import playlist** and select a Spotify playlist JSON export
(for example, `Playlist1.json` from an account data export). Musico saves track,
artist, album, and Spotify URI metadata locally; it does not fetch audio from
Spotify. Exact title-and-artist matches in `media_downloads.json` get an
in-app **Download** action. Other tracks can search the configured music links
from the playlist view. Only authorized direct media URLs are downloaded.

In Music, create local playlists from your library. Renaming, deletion, track
removal, and playlist membership changes ask for confirmation. Deleting a
playlist never deletes its tracks.

Use each track's options menu to set playback trim points. The trim editor has a
time ruler, millisecond in/out markers, a movable playhead, and a preview of the
selected section. Trimming is non-destructive: the original audio file is not
changed. Music also exposes autoplay, shuffle, repeat, sorting, and volume
controls directly in the screen.

Settings > **Backup and restore** writes or restores a ZIP containing saved
settings, anime lists and caches, music and Spotify playlists, download links,
local music/video files, and cached licensed artwork.
Restore replaces the saved lists and settings; it does not delete media files
that were already on the device.

## Anime release calendar

The calendar and title search use AniList. Episode and premiere data is cached
locally for offline reference, but new schedule data requires internet access.
Android release notifications require the notification permission. Optional
desktop refresh checks for schedule changes every ten minutes while Musico is
open; it cannot track releases after the app exits.
