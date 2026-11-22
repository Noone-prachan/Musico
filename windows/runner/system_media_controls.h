#ifndef RUNNER_SYSTEM_MEDIA_CONTROLS_H_
#define RUNNER_SYSTEM_MEDIA_CONTROLS_H_

#include <windows.h>

#include <string>

void UpdateSystemMediaControls(HWND window, const std::string& title,
                               const std::string& artist,
                               const std::string& artwork_path,
                               bool is_playing);
void ClearSystemMediaControls(HWND window);

#endif  // RUNNER_SYSTEM_MEDIA_CONTROLS_H_
