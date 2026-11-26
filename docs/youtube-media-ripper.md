# Musico YouTube Media Ripper

This guide explains what the feature does, how a search becomes a local audio
or video file, what each platform does differently, and where the result is
stored. It describes the current implementation; YouTube can change its
interfaces and make parts of the flow unavailable.

## Short version

Musico searches YouTube for a song, artist, or video name. When someone selects
a result, the app downloads the available media directly to the device,
converts audio to MP3 or combines video and audio into MP4, then adds the file
to the local Musico library. The app also saves a JSON record of the source and
download details beside the media. Search and processing run on the device;
there is no Musico upload server in this flow.

The feature requires an internet connection. It does not verify whether a user
has permission to save a particular video. Users must follow applicable law,
YouTube's terms, and the rights of the content owner.

## Using the feature

1. Open **Music** and choose **Download from YouTube**.
2. Enter a song, artist, or video name and submit the search.
3. Review the result title, channel, duration, and thumbnail. Live results
   cannot be selected for download.
4. Select a result. Its title fills the **Save as** field; change that name if
   desired.
5. Choose **MP3 audio** or **MP4 video**. For MP4, choose one of the qualities
   Musico reports for that video.
6. Choose **Download MP3** or **Download MP4**. The dialog shows the current
   stage and transfer progress where a percentage is available.
7. After a successful save, the MP3 appears in **Songs** and the MP4 appears in
   the local **Videos** collection.

The save name is sanitized for the device's filesystem. Invalid filename
characters are replaced, trailing periods are removed, Windows reserved names
are made safe, and the name is capped at 120 characters. If a file with that
name already exists, Musico chooses a numbered name rather than overwriting it.

## What happens behind the scenes

```text
Download from YouTube dialog
        |
        +-- Search -> AppState -> YouTubeSearchService
        |                         |
        |                         +-- Windows: bundled yt-dlp process
        |                         +-- Android: Kotlin method channel -> yt-dlp runtime
        |                         +-- Other platforms: YouTube InnerTube request
        |
        +-- Select result and format
                  |
                  v
             AppState -> YouTubeDownloadService
                  |
                  +-- Resolve formats and download to temporary storage
                  +-- Convert audio or combine video/audio when needed
                  +-- Fetch thumbnail and write metadata sidecar
                  +-- Register the finished file in the local library
```

### Search

`YouTubeDownloadDialog` sends the query to `AppState.searchYouTube`. The app
clears old results, marks the search as active, and notifies the UI. The
`YouTubeSearchService` chooses the platform-specific search route:

- **Windows:** Musico starts `yt-dlp.exe` with a `ytsearch10:` query. It reads
  yt-dlp's JSON output and parses up to ten results.
- **Android:** Flutter invokes the `musico/youtube_search` method channel.
  `MainActivity` runs the work on a background executor, initializes the
  bundled yt-dlp Python runtime, and asks it for a flat `ytsearch10:` result.
  The Kotlin side returns sanitized JSON to Flutter. This requires a 64-bit
  ARM or x86_64 device; 32-bit Android is unsupported.
- **Other platforms:** The service sends a request to YouTube's InnerTube search
  endpoint using a compile-time `YOUTUBE_API_KEY` value. Windows and Android do
  not use that key.

Flutter converts the response to `YouTubeSearchResult` objects. Entries without
a valid 11-character video ID or a nonempty title are discarded. The list
contains the title and channel, plus duration and thumbnail when available.
Live or duration-unknown entries are marked and cannot be selected.

Search only retrieves listing information. It does not save a media file or add
a library entry.

### Format selection and download

After selection, `AppState.downloadYouTube` validates the request and creates a
`YouTubeRipRequest` with the video ID and URL, the requested save name, original
YouTube title, channel, chosen format, optional quality, duration, and
thumbnail URL. The download service obtains the media, writes the final file
and metadata, then the app registers it in the appropriate library.

The app uses a stable library ID for each video and format. The same MP3 or MP4
is shown as **Already saved** instead of being added again.

#### MP3 audio

- Musico asks for the best available audio stream.
- FFmpeg converts that stream to a high-quality variable-bitrate MP3 using
  `libmp3lame` quality level 0. The output cannot recover detail missing from
  the YouTube source.
- The requested save name and channel are written as MP3 title and artist tags.
- If a thumbnail can be downloaded, it is embedded as front-cover artwork and
  also kept in Musico's artwork directory.
- The final MP3 is registered as a music track.

#### MP4 video

- Musico loads available video qualities and sorts them from highest resolution
  to lowest. Codec and estimated size are shown when available.
- The requested quality is a maximum-height preference; a source can still
  lack a compatible MP4 stream at that quality.
- On Android and the non-Windows stream path, Musico downloads separate video
  and audio streams and combines them with FFmpeg using stream copy, without
  re-encoding the media.
- On Windows, yt-dlp selects and produces the MP4 output using the selected
  height preference.
- The final MP4 is registered in the local video collection.

FFmpeg stages such as conversion or muxing may show an indeterminate progress
indicator rather than a percentage. Android download progress is sent from
Kotlin to Flutter over the download method channel.

## Platform implementation

### Windows

The Windows release bundle includes `yt-dlp.exe` and Deno under the app's `bin`
folder. Musico explicitly configures yt-dlp to use that bundled Deno runtime for
YouTube extraction. The installer downloads verified upstream assets when it
builds the release bundle. The app resolver checks the bundled executable
first, then a small set of known per-user Python installation paths.

Search and downloads run yt-dlp as a child process. Audio output is downloaded
to an operation-specific temporary folder, converted with FFmpeg, copied to the
final managed music folder, and then the temporary folder is removed. Video
download format selection is delegated to yt-dlp. The Windows app can use its
configured Musico media root; otherwise it tries the user's Music and Downloads
folders, app-local storage, LocalAppData, and finally the system temporary
directory.

### Android

Android uses the `dev.ffmpegkit-maintained:yt-dlp-android` dependency and its
bundled Python runtime. Flutter communicates with native code using:

- `musico/youtube_search` for search requests and JSON results.
- `musico/youtube_download` for video-quality inspection, media downloads, and
  progress callbacks.

Native yt-dlp work runs on executor threads rather than blocking the UI thread.
For stream downloads, the native code configures yt-dlp's YouTube
`player_client` as `android`, runs the requested format selector, and returns
the downloaded file path to Flutter. FFmpeg then handles MP3 encoding and
MP4 stream muxing in the Flutter download service.

Downloaded media is stored in Musico's app-private application-support
directory, separated into `music`, `videos`, and `artwork` folders. Android
does not write these files to the public Downloads folder by default. Android
release support is 64-bit ARM and x86_64; 32-bit-only devices are not supported
by the bundled yt-dlp runtime.

### Other platforms

The remaining code path uses `youtube_explode_dart` to inspect and retrieve
streams, with FFmpeg for MP3 conversion and MP4 muxing. Search uses the
InnerTube request described above. Musico's release targets documented here
are Windows and Android; behavior on other Flutter platforms is not the main
shipping path.

## Files and metadata

For a successful download, the managed folders look like this:

```text
Musico media root/
  music/
    Requested name.mp3
    Requested name.metadata.json
  videos/
    Requested name.mp4
    Requested name.metadata.json
  artwork/
    VIDEO_ID.jpg
```

The artwork file is optional: if YouTube's thumbnail endpoints cannot be
reached, the media download can still succeed without downloaded artwork. The
sidecar is JSON with schema version 1. It records:

- The requested save name and original YouTube title.
- Channel, video ID, and source URL.
- Format and selected quality, when applicable.
- Duration, thumbnail URL, and local artwork path, when available.
- Final media filename, byte size, and save timestamp.

For MP3, title and artist tags are written into the file. MP4 metadata tags are
added on the FFmpeg mux path; Windows delegates the output to yt-dlp. The
sidecar preserves the requested and original names regardless of platform.

The media file is registered in Musico's local track or video list and those
library records are persisted by the app. A successful download is playable
offline as long as the local file remains available.

## Errors and recovery

- Blank searches are ignored. Empty results show **No videos matched that
  search**.
- Network, timeout, malformed response, unsupported runtime, and yt-dlp errors
  are surfaced in the search or download dialog.
- Windows search has a 45-second process timeout; yt-dlp is configured with a
  20-second socket timeout and one retry for search.
- The Android bridge reports ordinary yt-dlp exceptions and unsupported native
  runtime errors back to Flutter.
- A failed download is not shown as a successful library entry. If saving the
  library record fails after processing completes, the app rolls back that
  record and attempts to remove the final media file, sidecar, and artwork.
  Windows and Android use operation-specific staging directories with cleanup
  paths; a disk or process failure can still leave an unindexed partial file.
- A video may have no compatible audio/video format, or YouTube may throttle,
  restrict, or change its response. Retry later or update the bundled
  yt-dlp/runtime dependency in a new app build.

## Privacy, rights, and limits

- Search terms and requested YouTube media are sent directly from the device
  to YouTube-related endpoints and media hosts. Musico does not proxy them
  through a Musico server in this flow.
- The app does not ask users to sign in to YouTube and does not use browser
  cookies for these searches or downloads. Content requiring an account or
  unavailable to the active extractor may fail.
- Search results and files are not uploaded to Musico. Downloaded files remain
  in the local library described above.
- The app cannot determine copyright ownership or permission. Users must only
  save content they are legally and contractually allowed to download, and must
  respect the applicable YouTube terms and content-owner rights.
- The extractor depends on YouTube's changing interfaces. A YouTube-side change
  can temporarily break search or downloads until the dependency is updated and
  a new build is released.

## Build and maintenance

The Windows release installer bundles yt-dlp and Deno. Android packages the
yt-dlp Python runtime through the Gradle dependency and uses the FFmpegKit
Flutter plugin for conversion and muxing. No YouTube API key is required for
the Windows or Android release paths.

Build the documented targets from the repository root:

```powershell
flutter build windows --release
flutter build apk --release --target-platform android-arm64,android-x64 --split-per-abi
```

Update the relevant upstream dependency, rebuild, and test search, MP3, MP4,
library registration, and cleanup when changing the extraction or media
processing path.

## Main implementation files

- `lib/widgets/youtube_download_dialog.dart` — search, result selection,
  format/quality controls, progress, and user feedback.
- `lib/state/app_state.dart` — search/download state, validation, storage,
  library registration, persistence, and rollback.
- `lib/services/youtube_search_service.dart` — platform-specific search and
  result parsing.
- `lib/services/youtube_download_service.dart` — quality selection, downloads,
  thumbnail retrieval, FFmpeg processing, metadata creation, and cleanup.
- `lib/models/youtube_media.dart` — search result and video-quality models.
- `lib/models/youtube_download.dart` — safe filenames, rip request, and JSON
  sidecar schema.
- `android/app/src/main/kotlin/app/sideb/side_b/MainActivity.kt` — Android
  method-channel handlers and yt-dlp runtime integration.
- `installer/build_musico_release.ps1` — Windows release dependency bundling.

## A short explanation to share

“Musico lets you search YouTube from inside the music app and save a selected
result locally as MP3 or MP4. The app fetches the media on the device, converts
or combines streams when needed, and adds the result plus source metadata to
the local library. It does not send downloads through a Musico server or verify
content rights, so users must have permission to save what they download.”
