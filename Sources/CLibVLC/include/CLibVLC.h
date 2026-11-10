// CLibVLC.h — Umbrella header for the libVLC C API
// Exposes the raw libVLC 4.0 C functions to Swift via the CLibVLC module.

#ifndef CLibVLC_h
#define CLibVLC_h

#include "vlc/vlc.h"

// MARK: - Swift interop shims

/// Simplified log callback that receives pre-formatted messages.
/// Swift can't handle C va_list arguments, so the shim formats in C.
typedef void (*swiftvlc_log_cb)(void *data, int level,
                                 const char *module,
                                 const char *message);

/// Sets up a simplified log callback. Returns a context pointer
/// that must be freed with swiftvlc_log_unset().
void *swiftvlc_log_set(libvlc_instance_t *instance,
                        swiftvlc_log_cb callback,
                        void *data);

/// Unsets the log callback and frees the bridge context.
void swiftvlc_log_unset(libvlc_instance_t *instance, void *context);

// MARK: - Network proxy (engine patch 0007)

/// Sets the proxy every http/https connection of libVLC goes to, for the whole
/// process ("http://127.0.0.1:port"), or NULL for none. Defined in libVLC's
/// src/darwin/netconf.m by scripts/patches/0007-darwin-app-proxy.patch.
/// While one is set, a connection that can't reach it fails; it never goes direct.
void vlc_darwin_SetProxyUrl(const char *proxy_url);

#endif /* CLibVLC_h */
