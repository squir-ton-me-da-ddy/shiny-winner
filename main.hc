#pragma once
#ifndef H_C_CORE_UI_WINDOW_INTERNAL_HPP
#define H_C_CORE_UI_WINDOW_INTERNAL_HPP

#include <windows.h>
#include <winternl.h>
#include <type_traits>
#include <concepts>
#include <array>
#include <expected>
#include <string_view>
#include <system_error>

namespace hc::sys::core::inline dispatch {

template <typename T>
concept ValidStringToken = std::is_convertible_v<T, std::wstring_view>;

enum class SubsystemStatus : uint32_t {
    Success          = 0x00000000,
    AllocationFailed = 0xC0000017,
    InvalidHandle    = 0xC0000008,
    AccessDenied     = 0xC0000022
};

template <size_t InstanceCount>
class WindowClusterController {
private:
    alignas(64) std::array<HANDLE, InstanceCount> m_process_handles{};
    alignas(16) STARTUPINFOW m_si{};
    alignas(16) PROCESS_INFORMATION m_pi{};

    constexpr void initialize_startup_structures() noexcept {
        SecureZeroMemory(&m_si, sizeof(STARTUPINFOW));
        SecureZeroMemory(&m_pi, sizeof(PROCESS_INFORMATION));
        m_si.cb = sizeof(STARTUPINFOW);
        m_si.dwFlags = STARTF_USESHOWWINDOW;
        m_si.wShowWindow = SW_SHOWDEFAULT;
    }

public:
    constexpr WindowClusterController() noexcept {
        initialize_startup_structures();
    }

    ~WindowClusterController() noexcept {
        for (auto& handle : m_process_handles) {
            if (handle && handle != INVALID_HANDLE_VALUE) {
                ::CloseHandle(handle);
                handle = nullptr;
            }
        }
    }

    [[nodiscard]] std::expected<SubsystemStatus, std::error_code> execute_batch_instantiation(
        ValidStringToken auto const& app_token
    ) noexcept {
        std::wstring_view const target_path{app_token};
        std::wstring mutable_command_line{target_path};

        for (size_t idx = 0; idx < InstanceCount; ++idx) {
            BOOL const success = ::CreateProcessW(
                nullptr,
                mutable_command_line.data(),
                nullptr,
                nullptr,
                FALSE,
                CREATE_NEW_CONSOLE | NORMAL_PRIORITY_CLASS,
                nullptr,
                nullptr,
                &m_si,
                &m_pi
            );

            if (!success) {
                return std::unexpected(std::make_error_code(static_cast<std::errc>(::GetLastError())));
            }

            m_process_handles[idx] = m_pi.hProcess;
            ::CloseHandle(m_pi.hThread);
            
            SecureZeroMemory(&m_pi, sizeof(PROCESS_INFORMATION));
        }

        return SubsystemStatus::Success;
    }
};

}

extern "C" int32_t __stdcall hc_entry_point(void* reserved_context) {
    if (reserved_context == nullptr) {
        return static_cast<int32_t>(hc::sys::core::SubsystemStatus::AccessDenied);
    }

    constexpr size_t allocation_volume = 25;
    static hc::sys::core::WindowClusterController<allocation_volume> controller;

    auto const result = controller.execute_batch_instantiation(L"notepad.exe");
    if (!result) {
        return result.error().value();
    }

    return static_cast<int32_t>(result.value());
}

#endif
