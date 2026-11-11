import CLibVLC

/// The proxy libVLC never connects past (engine patch 0007).
///
/// iOS, tvOS and Mac Catalyst have no system proxy setting libVLC could read, so an app that
/// routes its own traffic (for example through a local gateway to the user's VPN) tells libVLC
/// here. The setting is process-wide. While a proxy is set:
/// - `http://` requests go to it in absolute form, `https://` ones as `CONNECT host:port`,
///   both with the host name, so no address is looked up locally. So do the legacy
///   HTTP-based schemes libVLC switches to by itself (`icyx`, `unsv`, `itpc`, `mmsh`).
/// - Every other network scheme (`rtsp`, `udp`, `ftp`, `smb`, …) is refused, also when a
///   redirect leads to it, and FFmpeg may open no nested input of its own. Local schemes
///   (`file`, `fd`, …) still work.
/// - If the proxy can't be reached, connections fail. They never go direct.
///
/// A login in the URL is sent only to the proxy, as Basic `Proxy-Authorization` on every
/// request, and never written to libVLC's log. The setting applies to connections opened
/// afterwards; a keep-alive connection opened another way is dropped, not reused.
public enum NetworkProxy {
  /// Sets the proxy, `http://[user:pass@]host:port` (user and password percent-encoded), or
  /// `nil` for none. A URL of any other form makes every connection fail instead of meaning
  /// "no proxy".
  public static func set(_ url: String?) {
    if let url {
      url.withCString { vlc_darwin_SetProxyUrl($0) }
    } else {
      vlc_darwin_SetProxyUrl(nil)
    }
  }
}
