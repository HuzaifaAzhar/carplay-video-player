import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// All videos on the iPhone, with search, sorting, filters and folders. Tapping a video plays it on the car
/// screen when CarPlay is connected, otherwise on the iPhone.
struct LibraryView: View {
    @State private var search = ""
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showAddLink = false
    @State private var importingPhotos = 0

    var body: some View {
        let library = VideoLibrary.shared
        let settings = AppSettings.shared
        let items = library.filtered(search: search, sort: settings.librarySort, filter: settings.libraryFilter, folder: settings.libraryFolder)
        let car = CarConnection.shared

        NavigationStack {
            List {
                Section {
                    CarStatusRow()
                }
                if !URLDownloader.shared.jobs.isEmpty || library.isImporting || importingPhotos > 0 {
                    Section("Adding") {
                        if library.isImporting || importingPhotos > 0 {
                            HStack {
                                ProgressView()
                                Text(importingPhotos > 0 ? "Copying \(importingPhotos) from Photos…" : "Copying videos…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(URLDownloader.shared.jobs) { job in
                            DownloadRow(job: job)
                        }
                    }
                }
                Section {
                    if items.isEmpty {
                        emptyState(hasVideos: !library.videos.isEmpty)
                    }
                    ForEach(items) { item in
                        VideoRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture { play(item, in: items) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { library.delete(item) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button { library.setWatched(id: item.id, !item.watched) } label: {
                                    Label(item.watched ? "Unwatched" : "Watched", systemImage: item.watched ? "eye.slash" : "eye")
                                }
                                .tint(.blue)
                            }
                            .contextMenu { menu(for: item, in: items, carConnected: car.isConnected) }
                    }
                } footer: {
                    footer
                }
            }
            .navigationTitle("Videos")
            .searchable(text: $search, prompt: "Search videos")
            .refreshable { library.reload() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    sortMenu(settings: settings)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showFileImporter = true } label: { Label("From Files", systemImage: "folder") }
                        Button { showPhotoPicker = true } label: { Label("From Photos", systemImage: "photo.on.rectangle") }
                        Button { showAddLink = true } label: { Label("From a Link", systemImage: "link") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    library.importFiles(urls)
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection, maxSelectionCount: 50, matching: .videos)
            .onChange(of: photoSelection) { _, selection in
                importPhotos(selection)
            }
            .sheet(isPresented: $showAddLink) {
                AddLinkView()
            }
            .alert("Videos", isPresented: Binding(
                get: { library.lastImportMessage != nil },
                set: { if !$0 { library.lastImportMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.lastImportMessage ?? "")
            }
        }
    }

    private func play(_ item: VideoItem, in list: [VideoItem]) {
        if CarConnection.shared.isConnected {
            CarUIState.shared.play(item, list: list)
        } else {
            PlaybackController.shared.play(item, in: list, on: .phone)
        }
    }

    @ViewBuilder
    private func menu(for item: VideoItem, in list: [VideoItem], carConnected: Bool) -> some View {
        if carConnected {
            Button { CarUIState.shared.play(item, list: list) } label: { Label("Play on CarPlay", systemImage: "car.fill") }
        }
        Button { PlaybackController.shared.play(item, in: list, on: .phone) } label: { Label("Play on iPhone", systemImage: "iphone") }
        Divider()
        Button { VideoLibrary.shared.setWatched(id: item.id, !item.watched) } label: {
            Label(item.watched ? "Mark as Unwatched" : "Mark as Watched", systemImage: item.watched ? "eye.slash" : "eye")
        }
        if item.position > 0 {
            Button { VideoLibrary.shared.setWatched(id: item.id, false) } label: { Label("Start Over Next Time", systemImage: "backward.end") }
        }
        if !item.isStream {
            ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        Divider()
        Button(role: .destructive) { VideoLibrary.shared.delete(item) } label: { Label("Delete", systemImage: "trash") }
    }

    private func sortMenu(settings: AppSettings) -> some View {
        Menu {
            Picker("Sort", selection: Binding(get: { settings.librarySort }, set: { settings.librarySort = $0 })) {
                ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
            }
            Picker("Show", selection: Binding(get: { settings.libraryFilter }, set: { settings.libraryFilter = $0 })) {
                ForEach(LibraryFilter.allCases) { Text($0.title).tag($0) }
            }
            if !VideoLibrary.shared.folders.isEmpty {
                Picker("Folder", selection: Binding(get: { settings.libraryFolder }, set: { settings.libraryFolder = $0 })) {
                    Text("All Folders").tag(String?.none)
                    ForEach(VideoLibrary.shared.folders, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
        } label: {
            let filtered = settings.libraryFilter != .all || settings.libraryFolder != nil
            Image(systemName: filtered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    @ViewBuilder
    private func emptyState(hasVideos: Bool) -> some View {
        if hasVideos {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView {
                Label("No Videos Yet", systemImage: "film.stack")
            } description: {
                Text("Tap + to add videos from Files, Photos or a link. You can also copy videos into the \"Car Video\" folder in the Files app (On My iPhone).")
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        let library = VideoLibrary.shared
        VStack(alignment: .leading, spacing: 6) {
            if !library.videos.isEmpty {
                Text("\(library.videos.count) videos · \(library.totalFileSize.byteText) on this iPhone")
            }
            if !library.unsupportedFiles.isEmpty {
                Text("\(library.unsupportedFiles.count) file(s) can't be played because iOS doesn't support their format (MKV, WebM, AVI and similar). Convert them to MP4 to watch them here: \(library.unsupportedFiles.prefix(5).joined(separator: ", "))\(library.unsupportedFiles.count > 5 ? "…" : "")")
            }
        }
    }

    /// Copies the picked Photos videos into the app's folder.
    private func importPhotos(_ selection: [PhotosPickerItem]) {
        guard !selection.isEmpty else { return }
        photoSelection = []
        importingPhotos = selection.count
        Task {
            var added = 0
            for item in selection {
                if (try? await item.loadTransferable(type: PickedMovie.self)) != nil {
                    added += 1
                }
                importingPhotos -= 1
            }
            VideoLibrary.shared.reload()
            VideoLibrary.shared.lastImportMessage = added == selection.count
                ? (added == 1 ? "Added 1 video from Photos." : "Added \(added) videos from Photos.")
                : "Added \(added) of \(selection.count) videos from Photos."
        }
    }
}

/// A video from the Photos library, copied into the app's folder as it arrives.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = VideoLibrary.uniqueDestination(for: received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

struct VideoRow: View {
    let item: VideoItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                ThumbnailView(item: item)
                    .frame(width: 112, height: 63)
                    .clipped()
                if item.isInProgress, let progress = item.progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.35))
                            Rectangle().fill(Color.accentColor).frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .frame(width: 112, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let folder = item.folder {
                    Label(folder, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.watched {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        var parts: [String] = []
        if let duration = item.duration, duration > 0 {
            parts.append(item.isInProgress ? "\((duration - item.position).clockText) left" : duration.clockText)
        }
        if item.isStream {
            parts.append("Link")
        } else if let size = item.fileSize {
            parts.append(size.byteText)
        }
        if let resolution = item.resolutionText { parts.append(resolution) }
        parts.append(item.dateAdded.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }
}

struct DownloadRow: View {
    let job: URLDownloader.Job

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    if job.error == nil {
                        URLDownloader.shared.cancel(job.id)
                    } else {
                        URLDownloader.shared.dismiss(job.id)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if let error = job.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let fraction = job.fraction {
                ProgressView(value: fraction)
                Text("\(job.received.byteText) of \(job.expected.byteText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text(job.received.byteText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Whether the car screen is connected, with its size.
struct CarStatusRow: View {
    var body: some View {
        let car = CarConnection.shared
        if car.isConnected, let info = car.info {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected to CarPlay")
                        .font(.subheadline.weight(.semibold))
                    Text("\(info.pixelText) screen · tap a video to play it in the car")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("YouTube") { CarUIState.shared.openYouTube() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "car")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CarPlay not connected")
                        .font(.subheadline.weight(.semibold))
                    Text("Connect to your car and open Car Video on the car screen. Videos play here meanwhile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
