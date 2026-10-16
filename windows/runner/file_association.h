#ifndef RUNNER_FILE_ASSOCIATION_H_
#define RUNNER_FILE_ASSOCIATION_H_

#include <windows.h>
#include <shlobj.h>
#include <string>
#include <vector>

// Register an available PDF handler for this user. Never change their default.
inline void RegisterPdfAssociation() {
  std::vector<wchar_t> path(32768);
  const DWORD length = GetModuleFileNameW(nullptr, path.data(),
                                         static_cast<DWORD>(path.size()));
  if (length == 0 || length >= path.size()) return;
  const std::wstring executable(path.data(), length);
  const std::wstring filename = executable.substr(executable.find_last_of(L"\\/") + 1);
  const std::wstring command = L"\"" + executable + L"\" \"%1\"";
  bool changed = false;
  const auto write = [&changed](const std::wstring& key,
                                const wchar_t* name,
                                const std::wstring& value) {
    HKEY handle;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, key.c_str(), 0, nullptr, 0,
                        KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr, &handle,
                        nullptr) != ERROR_SUCCESS) return;
    DWORD type = 0, bytes = 0;
    std::vector<wchar_t> existing(value.size() + 1);
    bytes = static_cast<DWORD>(existing.size() * sizeof(wchar_t));
    const auto result = RegQueryValueExW(handle, name, nullptr, &type,
        reinterpret_cast<BYTE*>(existing.data()), &bytes);
    if (result != ERROR_SUCCESS || type != REG_SZ ||
        bytes != (value.size() + 1) * sizeof(wchar_t) ||
        std::wstring(existing.data(), value.size()) != value) {
      changed |= RegSetValueExW(handle, name, 0, REG_SZ,
          reinterpret_cast<const BYTE*>(value.c_str()),
          static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS;
    }
    RegCloseKey(handle);
  };
  const std::wstring base = L"Software\\Classes\\";
  const std::wstring application = base + L"Applications\\" + filename;
  write(application, L"FriendlyAppName", L"OSI");
  write(application + L"\\SupportedTypes", L".pdf", L"");
  write(application + L"\\shell\\open\\command", nullptr, command);
  write(base + L"OSI.PDF", nullptr, L"Documento PDF OSI");
  write(base + L"OSI.PDF\\Application", L"ApplicationName", L"OSI");
  write(base + L"OSI.PDF\\DefaultIcon", nullptr, L"\"" + executable + L"\",0");
  write(base + L"OSI.PDF\\shell\\open\\command", nullptr, command);
  write(base + L".pdf\\OpenWithProgids", L"OSI.PDF", L"");
  if (changed) SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

#endif  // RUNNER_FILE_ASSOCIATION_H_
