#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <winrt/Windows.Foundation.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

void EnsureWritableTempDirectory() {
  wchar_t system_temp[MAX_PATH] = {};
  wchar_t local_app_data[MAX_PATH] = {};
  wchar_t exe_path[MAX_PATH] = {};

  const DWORD temp_length = ::GetTempPathW(MAX_PATH, system_temp);
  if (temp_length == 0) {
    system_temp[0] = L'\0';
  }
  if (::GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data, MAX_PATH) == 0) {
    local_app_data[0] = L'\0';
  }
  if (::GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) {
    exe_path[0] = L'\0';
  }

  std::wstring exe_dir(exe_path);
  const size_t slash = exe_dir.find_last_of(L"\\/");
  if (slash != std::wstring::npos) {
    exe_dir.resize(slash);
  }

  std::vector<std::wstring> candidates;
  if (system_temp[0] != L'\0') {
    candidates.emplace_back(system_temp);
  }
  if (local_app_data[0] != L'\0') {
    const std::wstring musico_dir =
        std::wstring(local_app_data) + L"\\Musico";
    ::CreateDirectoryW(musico_dir.c_str(), nullptr);
    candidates.emplace_back(musico_dir + L"\\temp");
  }
  if (!exe_dir.empty()) {
    candidates.emplace_back(exe_dir + L"\\temp");
    candidates.emplace_back(exe_dir);
  }

  for (const auto &dir : candidates) {
    ::CreateDirectoryW(dir.c_str(), nullptr);
    const std::wstring probe = dir + L"\\musico-temp-probe.tmp";
    HANDLE file =
        ::CreateFileW(probe.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                      FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE,
                      nullptr);
    if (file == INVALID_HANDLE_VALUE) {
      continue;
    }
    ::CloseHandle(file);
    ::SetEnvironmentVariableW(L"TMP", dir.c_str());
    ::SetEnvironmentVariableW(L"TEMP", dir.c_str());
    return;
  }
}

}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  EnsureWritableTempDirectory();

  winrt::init_apartment(winrt::apartment_type::single_threaded);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Musico", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  winrt::uninit_apartment();
  return EXIT_SUCCESS;
}
