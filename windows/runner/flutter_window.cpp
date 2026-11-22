#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include "system_media_controls.h"

namespace {

const flutter::EncodableValue* FindArgument(
    const flutter::EncodableMap& arguments, const char* key) {
  const auto found = arguments.find(flutter::EncodableValue(key));
  return found == arguments.end() ? nullptr : &found->second;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  media_controls_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "musico/windows_media_controls",
          &flutter::StandardMethodCodec::GetInstance());
  media_controls_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "clear") {
          try {
            ClearSystemMediaControls(GetHandle());
            result->Success();
          } catch (const winrt::hresult_error& error) {
            result->Error("media_controls_error",
                          winrt::to_string(error.message()));
          } catch (const std::exception& error) {
            result->Error("media_controls_error", error.what());
          }
          return;
        }

        if (call.method_name() != "update") {
          result->NotImplemented();
          return;
        }

        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("invalid_arguments", "Media details are missing.");
          return;
        }

        const auto* title_value = FindArgument(*arguments, "title");
        const auto* artist_value = FindArgument(*arguments, "artist");
        const auto* artwork_value = FindArgument(*arguments, "artworkPath");
        const auto* playing_value = FindArgument(*arguments, "isPlaying");
        const auto* title = title_value == nullptr
                                ? nullptr
                                : std::get_if<std::string>(title_value);
        const auto* artist = artist_value == nullptr
                                 ? nullptr
                                 : std::get_if<std::string>(artist_value);
        const auto* artwork_path =
            artwork_value == nullptr
                ? nullptr
                : std::get_if<std::string>(artwork_value);
        const auto* is_playing = playing_value == nullptr
                                     ? nullptr
                                     : std::get_if<bool>(playing_value);
        if (title == nullptr || artist == nullptr || artwork_path == nullptr ||
            is_playing == nullptr) {
          result->Error("invalid_arguments",
                        "Media title, artist, artwork, or playback state is invalid.");
          return;
        }

        try {
          UpdateSystemMediaControls(GetHandle(), *title, *artist,
                                    *artwork_path, *is_playing);
          result->Success();
        } catch (const winrt::hresult_error& error) {
          result->Error("media_controls_error",
                        winrt::to_string(error.message()));
        } catch (const std::exception& error) {
          result->Error("media_controls_error", error.what());
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (media_controls_channel_) {
    media_controls_channel_->SetMethodCallHandler(nullptr);
    media_controls_channel_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
