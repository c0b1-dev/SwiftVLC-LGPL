import CLibVLC

/// The proxy libVLC sends its network traffic to (engine patch 0007).
///
/// iOS, tvOS and Mac Catalyst have no system proxy setting libVLC could read, so an app that
/// routes its own traffic (for example through a local gateway to the user's VPN) tells libVLC
/// here. The setting is process-wide and applies to the next connection libVLC opens: every
/// `http://` request goes to the proxy in absolute form, every `https://` one as `CONNECT
/// host:port` with the host name, so no address is looked up locally. Other schemes (`rtsp`,
/// `udp`, …) are not covered; the app has to refuse them while a proxy is required.
///
/// While a proxy is set and can't be reached, libVLC's connections fail. They never go direct.
public enum NetworkProxy {
  /// Sets the proxy (`http://127.0.0.1:8080`), or `nil` for none.
  public static func set(_ url: String?) {
    if let url {
      url.withCString { vlc_darwin_SetProxyUrl($0) }
    } else {
      vlc_darwin_SetProxyUrl(nil)
    }
  }
}
