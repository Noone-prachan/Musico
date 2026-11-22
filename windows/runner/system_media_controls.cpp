#include "system_media_controls.h"

#include <SystemMediaTransportControlsInterop.h>
#include <windows.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <stdexcept>

namespace {

using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Storage::StorageFile;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

SystemMediaTransportControls& ControlsForWindow(HWND window) {
  static SystemMediaTransportControls controls{nullptr};
  if (controls == nullptr) {
    auto interop = winrt::get_activation_factory<
        SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(
        window, winrt::guid_of<SystemMediaTransportControls>(),
        winrt::put_abi(controls)));
    controls.IsEnabled(true);
    controls.IsPlayEnabled(false);
    controls.IsPauseEnabled(false);
    controls.IsStopEnabled(false);
    controls.IsNextEnabled(false);
    controls.IsPreviousEnabled(false);
  }
  return controls;
}

void UpdateDisplay(HWND window, const std::string& title,
                   const std::string& artist,
                   const std::string& artwork_path, bool is_playing) {
  auto& controls = ControlsForWindow(window);
  auto updater = controls.DisplayUpdater();
  updater.ClearAll();
  updater.Type(MediaPlaybackType::Music);

  auto properties = updater.MusicProperties();
  properties.Title(winrt::to_hstring(title));
  properties.Artist(winrt::to_hstring(artist));

  if (!artwork_path.empty()) {
    auto file = StorageFile::GetFileFromPathAsync(
                    winrt::to_hstring(artwork_path))
                    .get();
    updater.Thumbnail(RandomAccessStreamReference::CreateFromFile(file));
  }

  updater.Update();
  controls.PlaybackStatus(is_playing ? MediaPlaybackStatus::Playing
                                     : MediaPlaybackStatus::Paused);
}

}  // namespace

void UpdateSystemMediaControls(HWND window, const std::string& title,
                               const std::string& artist,
                               const std::string& artwork_path,
                               bool is_playing) {
  if (window == nullptr) {
    throw std::invalid_argument("The Musico window is not available.");
  }
  UpdateDisplay(window, title, artist, artwork_path, is_playing);
}

void ClearSystemMediaControls(HWND window) {
  if (window == nullptr) {
    throw std::invalid_argument("The Musico window is not available.");
  }
  auto& controls = ControlsForWindow(window);
  controls.DisplayUpdater().ClearAll();
  controls.DisplayUpdater().Update();
  controls.PlaybackStatus(MediaPlaybackStatus::Stopped);
}
