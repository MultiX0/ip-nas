#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <shellapi.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

// Minimum window size in logical pixels.
constexpr int kMinWidth = 480;
constexpr int kMinHeight = 560;

// Returns the clipboard image as PNG bytes ("PNG" format) or as a BMP file built
// from CF_DIB. Empty when the clipboard holds no image.
std::vector<uint8_t> ReadClipboardImage() {
  std::vector<uint8_t> out;
  if (!::OpenClipboard(nullptr)) return out;
  static const UINT png_format = ::RegisterClipboardFormatW(L"PNG");
  HANDLE h = nullptr;
  if (png_format != 0 && ::IsClipboardFormatAvailable(png_format) &&
      (h = ::GetClipboardData(png_format)) != nullptr) {
    const SIZE_T size = ::GlobalSize(h);
    const auto* p = static_cast<const uint8_t*>(::GlobalLock(h));
    if (p != nullptr) {
      if (size > 0) out.assign(p, p + size);
      ::GlobalUnlock(h);
    }
  } else if (::IsClipboardFormatAvailable(CF_DIB) &&
             (h = ::GetClipboardData(CF_DIB)) != nullptr) {
    const SIZE_T size = ::GlobalSize(h);
    const auto* p = static_cast<const uint8_t*>(::GlobalLock(h));
    if (p != nullptr) {
      if (size >= sizeof(BITMAPINFOHEADER)) {
        const auto* bih = reinterpret_cast<const BITMAPINFOHEADER*>(p);
        DWORD offset = bih->biSize;
        if (bih->biCompression == BI_BITFIELDS &&
            bih->biSize == sizeof(BITMAPINFOHEADER)) {
          offset += 12;
        }
        DWORD colors = bih->biClrUsed;
        if (colors == 0 && bih->biBitCount <= 8) colors = 1u << bih->biBitCount;
        offset += colors * 4;
        BITMAPFILEHEADER bfh = {};
        bfh.bfType = 0x4D42;  // "BM"
        bfh.bfSize = static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + size);
        bfh.bfOffBits = static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + offset);
        const auto* hp = reinterpret_cast<const uint8_t*>(&bfh);
        out.assign(hp, hp + sizeof(BITMAPFILEHEADER));
        out.insert(out.end(), p, p + size);
      }
      ::GlobalUnlock(h);
    }
  }
  ::CloseClipboard();
  return out;
}

// Paths of files copied in Explorer (CF_HDROP), UTF-8.
std::vector<std::string> ReadClipboardFiles() {
  std::vector<std::string> out;
  if (!::IsClipboardFormatAvailable(CF_HDROP) || !::OpenClipboard(nullptr)) {
    return out;
  }
  HDROP drop = static_cast<HDROP>(::GetClipboardData(CF_HDROP));
  if (drop != nullptr) {
    const UINT n = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT i = 0; i < n; i++) {
      const UINT len = ::DragQueryFileW(drop, i, nullptr, 0);
      std::wstring path(len + 1, L'\0');
      ::DragQueryFileW(drop, i, path.data(), len + 1);
      path.resize(len);
      out.push_back(Utf8FromUtf16(path.c_str()));
    }
  }
  ::CloseClipboard();
  return out;
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

  desktop_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "nur/desktop",
          &flutter::StandardMethodCodec::GetInstance());
  desktop_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "clipboardImage") {
          std::vector<uint8_t> bytes = ReadClipboardImage();
          if (bytes.empty()) {
            result->Success();
          } else {
            result->Success(flutter::EncodableValue(std::move(bytes)));
          }
        } else if (call.method_name() == "clipboardFiles") {
          flutter::EncodableList list;
          for (auto& path : ReadClipboardFiles()) {
            list.push_back(flutter::EncodableValue(path));
          }
          result->Success(flutter::EncodableValue(std::move(list)));
        } else {
          result->NotImplemented();
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
  desktop_channel_ = nullptr;
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
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = FlutterDesktopGetDpiForMonitor(
          ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST));
      const double scale = dpi > 0 ? dpi / 96.0 : 1.0;
      info->ptMinTrackSize.x = static_cast<LONG>(kMinWidth * scale);
      info->ptMinTrackSize.y = static_cast<LONG>(kMinHeight * scale);
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
