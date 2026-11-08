#pragma once

#include <cstddef>
#include <cstdint>

extern "C" {

struct RdpAppHandle;

using RdpUiEventCallback = void (*)(
    const char *json_ptr,
    const unsigned char *bin_ptr,
    std::size_t bin_len,
    void *user_data
);

RdpAppHandle *rdp_app_create(RdpUiEventCallback callback, void *user_data);
int rdp_app_dispatch(RdpAppHandle *handle, const char *action_json);
int rdp_app_framebuffer_size(
    RdpAppHandle *handle,
    std::uint16_t *out_width,
    std::uint16_t *out_height,
    std::uint64_t *out_seq
);
int rdp_app_copy_framebuffer_rgba(
    RdpAppHandle *handle,
    unsigned char *dst_rgba,
    std::size_t dst_capacity
);
void rdp_app_destroy(RdpAppHandle *handle);
void rdp_report_ui_error(const char *code, const char *file, std::uint32_t line, int fatal);

}
