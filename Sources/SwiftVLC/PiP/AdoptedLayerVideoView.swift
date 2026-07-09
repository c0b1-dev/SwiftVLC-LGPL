#if canImport(UIKit) && !os(tvOS) && !os(watchOS)
import AVFoundation
import SwiftUI
import UIKit

/// Internal UIView that hosts a ``PiPController``'s persistent
/// `AVSampleBufferDisplayLayer` **and** serves as the libVLC drawable.
///
/// With libVLC patch 0004 (`VLCSampleBufferLayerProviding`), the
/// samplebufferdisplay vout asks the drawable for a provided layer during
/// Open and adopts it instead of creating its own display view. Because
/// the layer is app-owned it survives vout close/reopen cycles (live-TS
/// format changes), which keeps an active Picture-in-Picture session
/// alive — the historical grey-PiP failure mode of the built-in path.
///
/// Sizing follows the LayerHostView semantics proven in the vmem path:
/// frame the hosted layer synchronously (no implicit CoreAnimation) on
/// every layout pass, but only while it is actually our sublayer — during
/// active PiP, AVKit reparents the layer into the PiP window and we must
/// not fight it there.
@MainActor
final class AdoptedLayerDrawableView: UIView {
  /// Immutable after init — safe to hand out from the vout thread.
  nonisolated(unsafe) private let provided: AVSampleBufferDisplayLayer
  private weak var attachedPlayer: Player?

  init(layer provided: AVSampleBufferDisplayLayer) {
    self.provided = provided
    super.init(frame: .zero)
    backgroundColor = .black
    isUserInteractionEnabled = false
    layer.addSublayer(provided)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Called by libVLC's samplebufferdisplay vout (patch 0004) synchronously
  /// on the vout thread during Open. Must stay thread-safe: it only returns
  /// immutable state.
  @objc(vlc_providedSampleBufferLayer)
  nonisolated func vlcProvidedSampleBufferLayer() -> AVSampleBufferDisplayLayer {
    provided
  }

  func attach(to player: Player) {
    if attachedPlayer !== player {
      attachedPlayer?.releaseDrawableOwnership(self)
      attachedPlayer = player
    }
    player.claimDrawableOwnership(self)
    publishDrawableIfReady()
  }

  func detach() {
    guard let player = attachedPlayer else { return }
    player.releaseDrawableOwnership(self)
    attachedPlayer = nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    publishDrawableIfReady()
    frameHostedLayer()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      publishDrawableIfReady()
      setNeedsLayout()
    }
  }

  /// If PiP ended and AVKit handed the layer back without a superlayer,
  /// re-host it; then size it to our bounds — synchronously, so the video
  /// never lags SwiftUI animations (rotation/fullscreen/mini player).
  private func frameHostedLayer() {
    if provided.superlayer == nil {
      layer.addSublayer(provided)
    }
    guard provided.superlayer === layer else { return }   // AVKit owns it during PiP
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    provided.frame = bounds
    CATransaction.commit()
  }

  private func publishDrawableIfReady() {
    guard let player = attachedPlayer, player.isDrawableOwner(self) else { return }
    if !player.isCurrentDrawable(self) {
      player.setDrawable(self, owner: self)
    }
  }
}

/// A SwiftUI view that renders hardware-decoded video into a
/// ``PiPController``'s persistent layer via libVLC's native
/// samplebufferdisplay vout (adopted-layer mode, patch 0004).
///
/// Create the controller with ``PiPController/RenderingMode/adoptedLayer``
/// **before** starting playback, then keep both alive for the lifetime of
/// the player:
///
/// ```swift
/// let controller = PiPController(player: player, mode: .adoptedLayer)
/// AdoptedVideoView(player, controller: controller)
/// ```
public struct AdoptedVideoView: UIViewRepresentable {
  private let player: Player
  private let controller: PiPController

  /// Creates the video view.
  /// - Parameters:
  ///   - player: The player whose video output to display.
  ///   - controller: The PiP controller owning the persistent display layer
  ///     (must be created with `mode: .adoptedLayer`).
  public init(_ player: Player, controller: PiPController) {
    self.player = player
    self.controller = controller
  }

  public func makeUIView(context _: Context) -> UIView {
    let view = AdoptedLayerDrawableView(layer: controller.layer)
    view.attach(to: player)
    return view
  }

  public func updateUIView(_ uiView: UIView, context _: Context) {
    (uiView as? AdoptedLayerDrawableView)?.attach(to: player)
  }

  public static func dismantleUIView(_ uiView: UIView, coordinator _: ()) {
    (uiView as? AdoptedLayerDrawableView)?.detach()
  }
}
#endif
