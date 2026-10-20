import SwiftUI
import UIKit
import WebKit

struct SettingsView: View {
    @State private var confirmClearYouTube = false

    var body: some View {
        @Bindable var settings = AppSettings.shared
        let car = CarConnection.shared

        NavigationStack {
            Form {
                Section {
                    Picker("Video", selection: $settings.videoFit) {
                        ForEach(VideoFit.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Use the Whole Screen", isOn: $settings.fullScreenBehindDock)
                } header: {
                    Text("Car Screen")
                } footer: {
                    Text("Fit shows the whole picture with bars where the shapes differ; Fill crops the edges instead. You can switch while watching with the arrows button. \"Use the Whole Screen\" lets video go behind the CarPlay dock.")
                }

                if let info = car.info {
                    Section("This Car") {
                        LabeledContent("Screen", value: "\(info.pixelText) @\(String(format: "%g", info.scale))x")
                        LabeledContent("Area for the app", value: info.usableText)
                        LabeledContent("CarPlay dock and bars", value: info.insetsText)
                    }
                }

                Section("Playback") {
                    Toggle("Play Next Video Automatically", isOn: $settings.autoplayNext)
                    Toggle("Resume Where You Left Off", isOn: $settings.resumePlayback)
                    Picker("Skip Buttons", selection: $settings.skipSeconds) {
                        ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                }

                Section {
                    Picker("Site", selection: $settings.youTubeSite) {
                        ForEach(YouTubeSite.allCases) { Text($0.title).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("Page Size on the Car", value: "\(Int((settings.youTubeZoom * 100).rounded()))%")
                        Slider(value: $settings.youTubeZoom, in: 0.75...2, step: 0.05)
                    }
                    Toggle("Skip Ads", isOn: $settings.skipYouTubeAds)
                    Button("Sign Out and Clear YouTube Data", role: .destructive) { confirmClearYouTube = true }
                } header: {
                    Text("YouTube")
                } footer: {
                    Text("Page size 100% lays YouTube out at the car screen's own resolution; larger makes text and buttons bigger. Sign in on the YouTube tab; the car screen uses the same account.")
                }

                Section {
                    Toggle("Hide Video While Driving", isOn: $settings.hideVideoWhileDriving)
                } header: {
                    Text("Safety")
                } footer: {
                    Text("Uses the iPhone's location speed while CarPlay is connected. Video on the car screen is hidden when the car moves and comes back when it stops; sound keeps playing. Without location access, video is never hidden.")
                }

                Section {
                    Toggle("Keep iPhone Awake", isOn: $settings.keepPhoneAwake)
                    Toggle("Dim iPhone Screen", isOn: $settings.dimPhone)
                } header: {
                    Text("While Connected to CarPlay")
                } footer: {
                    Text("These apply while Car Video is open on the iPhone. Keeping it awake stops the iPhone locking during long videos.")
                }

                Section("Storage") {
                    let library = VideoLibrary.shared
                    LabeledContent("Videos", value: "\(library.videos.count)")
                    LabeledContent("Space Used", value: library.totalFileSize.byteText)
                    Button("Clear Thumbnail Cache") {
                        ThumbnailStore.shared.clearAll()
                    }
                }

                Section("Help") {
                    NavigationLink("Diagnostics Log") { DiagnosticsLogView() }
                    LabeledContent("Version", value: Bundle.main.shortVersion)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign out of YouTube and clear its cookies and cache?", isPresented: $confirmClearYouTube, titleVisibility: .visible) {
                Button("Clear YouTube Data", role: .destructive) { clearYouTubeData() }
            }
        }
    }

    private func clearYouTubeData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            Task { @MainActor in
                WebModel.resetAll()
                Diagnostics.log("Web", "Cleared YouTube data")
            }
        }
    }
}

struct DiagnosticsLogView: View {
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "No entries yet." : text)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Diagnostics Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                Menu {
                    Button { UIPasteboard.general.string = text } label: { Label("Copy", systemImage: "doc.on.doc") }
                    Button { text = Diagnostics.read() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) {
                        Diagnostics.clear()
                        text = ""
                    } label: { Label("Clear", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear { text = Diagnostics.read() }
    }
}
