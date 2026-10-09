import SwiftUI
import WebKit

/// The whole app is the launcher web page plus a thin native frame: a toolbar for reload and
/// share, and a banner when the page could not be loaded at all.
struct ContentView: View {
    @EnvironmentObject var bridge: WebBridge
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            if let error = bridge.lastError {
                ErrorBanner(message: error) { bridge.reload() }
            }

            ZStack {
                WebView()
                    .ignoresSafeArea(edges: .horizontal)

                if bridge.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.pink)
                }
            }
        }
        .tint(.pink)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    bridge.reload()
                } label: {
                    Label("重新载入", systemImage: "arrow.clockwise")
                }

                Button {
                    bridge.presentShareSheet()
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                Text("DaysEngine")
                    .font(.headline)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { phase in
            // iOS deactivates our audio session when the app is backgrounded or interrupted;
            // re-activating on return keeps the theme music and the sound-effect taps working.
            if phase == .active {
                AudioSessionController.reactivate()
            }
        }
    }
}

/// Shown when the launcher page itself could not load, so the screen is never silently blank.
private struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("启动器页面载入失败")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            Button("重试", action: retry)
                .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(Color.orange.opacity(0.14))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.orange.opacity(0.4)),
            alignment: .bottom
        )
    }
}
