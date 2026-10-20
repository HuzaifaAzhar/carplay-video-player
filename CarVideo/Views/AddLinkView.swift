import SwiftUI

/// Adds a video from a link: download it to the iPhone, or save the link and stream it. YouTube links open
/// on the car screen (or the YouTube tab) instead.
struct AddLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var name = ""
    @State private var stream = false

    private var url: URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else {
            return nil
        }
        return url
    }

    private var youTubePage: URL? {
        YouTube.pageURL(for: link, site: AppSettings.shared.youTubeSite)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/video.mp4", text: $link, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { strings in
                        let first = strings.first ?? ""
                        Task { @MainActor in link = first }
                    }
                } header: {
                    Text("Link")
                } footer: {
                    Text("A direct link to a video file (MP4, MOV, M4V) or an HLS stream (.m3u8).")
                }

                if let youTubePage {
                    Section {
                        Button {
                            if CarConnection.shared.isConnected {
                                CarUIState.shared.openYouTube(url: youTubePage)
                            } else {
                                WebModel.phone.load(youTubePage)
                            }
                            dismiss()
                        } label: {
                            Label(CarConnection.shared.isConnected ? "Open on CarPlay" : "Open in the YouTube Tab", systemImage: "play.rectangle.fill")
                        }
                    } footer: {
                        Text("YouTube videos play through YouTube's website. They can't be downloaded.")
                    }
                } else {
                    Section {
                        TextField("Name (optional)", text: $name)
                        Picker("Save as", selection: $stream) {
                            Text("Download to iPhone").tag(false)
                            Text("Stream (keep the link)").tag(true)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } footer: {
                        Text(stream
                             ? "The video plays from the link each time, so it needs a connection."
                             : "The file is saved in the app and plays offline. Keep the app open until the download finishes.")
                    }
                }
            }
            .navigationTitle("Add from Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if youTubePage == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(stream ? "Add" : "Download") {
                            guard let url else { return }
                            if stream {
                                VideoLibrary.shared.addStream(title: name, url: url)
                            } else {
                                URLDownloader.shared.download(url, name: name)
                            }
                            dismiss()
                        }
                        .disabled(url == nil)
                    }
                }
            }
        }
    }
}
