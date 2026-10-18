#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

// One Marquee window. A second `marquee.exe <file>` (Explorer "Open with", a double-click)
// finds the running window, hands it the file over WM_COPYDATA and exits; the window passes
// it to Dart on the `marquee/instance` channel.

#include <windows.h>

#include <string>

// Session-local: one Marquee per signed-in user.
inline constexpr wchar_t kMarqueeMutexName[] = L"Local\\Marquee.SingleInstance.3b7d2f";

// Window property that marks THE Marquee window (the class name is shared by every Flutter
// app, so it cannot identify us on its own).
inline constexpr wchar_t kMarqueeWindowProp[] = L"Marquee.MainWindow";

// COPYDATASTRUCT::dwData of a forwarded file (UTF-8 path, not NUL-terminated).
inline constexpr ULONG_PTR kMarqueeOpenFile = 0x4D51A001;

inline BOOL CALLBACK FindMarqueeWindowProc(HWND hwnd, LPARAM lparam) {
  if (::GetPropW(hwnd, kMarqueeWindowProp) != nullptr) {
    *reinterpret_cast<HWND*>(lparam) = hwnd;
    return FALSE;  // stop enumerating
  }
  return TRUE;
}

inline HWND FindMarqueeWindow() {
  HWND found = nullptr;
  ::EnumWindows(FindMarqueeWindowProc, reinterpret_cast<LPARAM>(&found));
  return found;
}

// A relative path typed in a terminal means nothing to the OTHER process: make it absolute
// here, in the second instance's working directory. URLs pass through untouched.
inline std::string AbsolutePathUtf8(const std::string& utf8) {
  if (utf8.empty() || utf8.find("://") != std::string::npos) return utf8;
  const int wide_len = ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (wide_len <= 0) return utf8;
  std::wstring wide(static_cast<size_t>(wide_len), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &wide[0], wide_len);
  constexpr DWORD kMax = 4096;
  std::wstring full(kMax, L'\0');
  const DWORD n = ::GetFullPathNameW(wide.c_str(), kMax, &full[0], nullptr);
  if (n == 0 || n >= kMax) return utf8;
  const int out_len = ::WideCharToMultiByte(CP_UTF8, 0, full.c_str(), static_cast<int>(n),
                                            nullptr, 0, nullptr, nullptr);
  if (out_len <= 0) return utf8;
  std::string out(static_cast<size_t>(out_len), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, full.c_str(), static_cast<int>(n), &out[0], out_len,
                        nullptr, nullptr);
  return out;
}

// Sends |utf8_path| (may be empty: just bring the window forward) to the running instance.
// Waits up to ~3 s for its window to appear (the first instance may still be starting).
inline void ForwardToRunningInstance(const std::string& utf8_path) {
  HWND target = nullptr;
  for (int i = 0; i < 30 && target == nullptr; ++i) {
    target = FindMarqueeWindow();
    if (target == nullptr) ::Sleep(100);
  }
  if (target == nullptr) return;
  if (!utf8_path.empty()) {
    COPYDATASTRUCT cds{};
    cds.dwData = kMarqueeOpenFile;
    cds.cbData = static_cast<DWORD>(utf8_path.size());
    cds.lpData = const_cast<char*>(utf8_path.data());
    DWORD_PTR ignored = 0;
    ::SendMessageTimeoutW(target, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds),
                          SMTO_ABORTIFHUNG, 3000, &ignored);
  }
  // This process was just launched by the user, so it may hand the foreground over.
  if (::IsIconic(target)) ::ShowWindow(target, SW_RESTORE);
  ::SetForegroundWindow(target);
}

#endif  // RUNNER_SINGLE_INSTANCE_H_
