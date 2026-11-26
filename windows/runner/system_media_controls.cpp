#include "system_media_controls.h"

#include <SystemMediaTransportControlsInterop.h>
#include <windows.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <cstdint>
#include <stdexcept>

namespace {

std::uint64_t artwork_request_id = 0;

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
  const auto current_artwork_request = ++artwork_request_id;
  auto updater = controls.DisplayUpdater();
  updater.ClearAll();
  updater.Type(MediaPlaybackType::Music);

  auto properties = updater.MusicProperties();
  properties.Title(winrt::to_hstring(title));
  properties.Artist(winrt::to_hstring(artist));

  updater.Update();
  controls.PlaybackStatus(is_playing ? MediaPlaybackStatus::Playing
                                     : MediaPlaybackStatus::Paused);

  if (!artwork_path.empty()) {
    try {
      auto file_operation = StorageFile::GetFileFromPathAsync(
          winrt::to_hstring(artwork_path));
      file_operation.Completed(
          [updater, current_artwork_request](const auto& operation,
                                             const auto&) {
            if (current_artwork_request != artwork_request_id) return;
            try {
              auto file = operation.GetResults();
              updater.Thumbnail(
                  RandomAccessStreamReference::CreateFromFile(file));
              updater.Update();
            } catch (const winrt::hresult_error& error) {
              OutputDebugStringW(
                  L"Musico could not load optional now-playing artwork: ");
              OutputDebugStringW(error.message().c_str());
              OutputDebugStringW(L"\n");
            } catch (const std::exception& error) {
              OutputDebugStringA(
                  "Musico could not load optional now-playing artwork: ");
              OutputDebugStringA(error.what());
              OutputDebugStringA("\n");
            }
          });
    } catch (const winrt::hresult_error& error) {
      OutputDebugStringW(
          L"Musico could not load optional now-playing artwork: ");
      OutputDebugStringW(error.message().c_str());
      OutputDebugStringW(L"\n");
    }
  }
}

}

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
  ++artwork_request_id;
  auto& controls = ControlsForWindow(window);
  controls.DisplayUpdater().ClearAll();
  controls.DisplayUpdater().Update();
  controls.PlaybackStatus(MediaPlaybackStatus::Stopped);
}
