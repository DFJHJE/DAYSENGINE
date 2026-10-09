import AVFoundation
import Foundation

/// Configures the process-wide audio session so Web Audio inside WKWebView behaves the way the
/// launcher expects.
///
/// Two things matter and both are easy to get wrong:
///   * `.playback` keeps sound alive when the ring/silent switch is flipped, which is what a
///     media app should do — with the default `.ambient` the theme music is simply muted.
///   * `.mixWithOthers` is deliberately **not** set: exclusive playback gives the game's audio
///     the full session rather than ducking under whatever else is playing.
enum AudioSessionController {
    static func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
        } catch {
            // The app still runs; sound may be affected by the silent switch.
            NSLog("DaysEngine: AVAudioSession.setCategory failed: \(error.localizedDescription)")
        }
        do {
            try session.setActive(true)
        } catch {
            NSLog("DaysEngine: AVAudioSession.setActive failed: \(error.localizedDescription)")
        }
    }

    /// Called when the app returns to the foreground: iOS deactivates the session on
    /// interruption (a call, Siri, another app taking over), and reactivating keeps the
    /// launcher's controls responsive afterwards.
    static func reactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("DaysEngine: AVAudioSession reactivate failed: \(error.localizedDescription)")
        }
    }
}
