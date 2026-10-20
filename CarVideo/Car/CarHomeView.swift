import SwiftUI

/// The car screen's video grid: one page of tiles that fits the screen exactly, page buttons, a sort
/// button and the YouTube button.
struct CarHomeView: View {
    let metrics: CarMetrics

    var body: some View {
        let ui = CarUIState.shared
        let settings = AppSettings.shared
        let items = VideoLibrary.shared.carList(settings.carSort)
        let layout = CarGridLayout(metrics: metrics)
        let pageCount = max(1, Int((Double(items.count) / Double(max(1, layout.perPage))).rounded(.up)))
        let page = min(ui.page, pageCount - 1)

        VStack(alignment: .leading, spacing: metrics.gap) {
            topBar(count: items.count, page: page, pageCount: pageCount)
            if items.isEmpty {
                emptyState
            } else {
                grid(Array(items.dropFirst(page * layout.perPage).prefix(layout.perPage)), all: items, layout: layout)
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        if value.translation.width < -40 { turnPage(to: page + 1, count: pageCount) }
                        if value.translation.width > 40 { turnPage(to: page - 1, count: pageCount) }
                    })
            }
        }
        .padding(metrics.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func topBar(count: Int, page: Int, pageCount: Int) -> some View {
        let settings = AppSettings.shared
        return HStack(spacing: metrics.gap) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Videos")
                    .font(.system(size: metrics.titleFont, weight: .bold))
                Text(count == 1 ? "1 video" : "\(count) videos")
                    .font(.system(size: metrics.captionFont))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .layoutPriority(1)
            Spacer(minLength: 0)
            if count > 1 {
                CarPillButton(title: settings.carSort.title, systemName: settings.carSort.symbol, metrics: metrics) {
                    settings.carSort = settings.carSort.next
                    CarUIState.shared.page = 0
                }
            }
            if pageCount > 1 {
                CarIconButton(systemName: "chevron.left", size: metrics.button) { turnPage(to: page - 1, count: pageCount) }
                    .opacity(page > 0 ? 1 : 0.35)
                Text("\(page + 1)/\(pageCount)")
                    .font(.system(size: metrics.captionFont, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
                CarIconButton(systemName: "chevron.right", size: metrics.button) { turnPage(to: page + 1, count: pageCount) }
                    .opacity(page + 1 < pageCount ? 1 : 0.35)
            }
            youTubeButton
        }
        .frame(height: metrics.barHeight)
    }

    private var youTubeButton: some View {
        CarPillButton(title: "YouTube", systemName: "play.rectangle.fill", metrics: metrics, background: Color(red: 0.86, green: 0.08, blue: 0.1)) {
            Diagnostics.log("Car", "YouTube button tapped")
            CarUIState.shared.openYouTube()
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { CarUIState.shared.youTubeButtonFrame = geo.frame(in: .global) }
                .onChange(of: geo.frame(in: .global)) { _, frame in CarUIState.shared.youTubeButtonFrame = frame }
        })
    }

    private func grid(_ pageItems: [VideoItem], all: [VideoItem], layout: CarGridLayout) -> some View {
        let rows = stride(from: 0, to: pageItems.count, by: layout.columns).map { Array(pageItems[$0..<min($0 + layout.columns, pageItems.count)]) }
        return VStack(alignment: .leading, spacing: layout.gap) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(alignment: .top, spacing: layout.gap) {
                    ForEach(rows[rowIndex]) { item in
                        CarVideoTile(item: item, layout: layout, metrics: metrics) {
                            CarUIState.shared.play(item, list: all)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: metrics.gap) {
            Image(systemName: "film.stack")
                .font(.system(size: metrics.bigButton * 0.55))
                .foregroundStyle(.white.opacity(0.7))
            Text("No videos yet")
                .font(.system(size: metrics.titleFont, weight: .bold))
            Text("Add videos in Car Video on your iPhone: from Files, Photos or a link. Or watch YouTube.")
                .font(.system(size: metrics.captionFont))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func turnPage(to page: Int, count: Int) {
        CarUIState.shared.page = clamp(page, 0, max(0, count - 1))
    }
}

/// A video on the car screen: thumbnail, length, progress, title.
struct CarVideoTile: View {
    let item: VideoItem
    let layout: CarGridLayout
    let metrics: CarMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                ZStack(alignment: .bottomLeading) {
                    ThumbnailView(item: item)
                        .frame(width: layout.tileWidth, height: layout.thumbHeight)
                        .clipped()
                    if let duration = item.duration, duration > 0 {
                        Text(duration.clockText)
                            .font(.system(size: metrics.captionFont, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.7)))
                            .padding(5)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if item.isInProgress, let progress = item.progress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.white.opacity(0.3))
                                Rectangle().fill(Color.accentColor).frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .frame(width: layout.tileWidth, height: layout.thumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: metrics.corner))
                Text(item.title)
                    .font(.system(size: metrics.bodyFont, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: metrics.captionFont))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(width: layout.tileWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CarPressStyle())
    }

    private var detail: String {
        if item.watched { return "Watched" }
        if item.isInProgress, let duration = item.duration { return "\((duration - item.position).clockText) left" }
        if item.isStream { return "Link" }
        return item.resolutionText ?? item.fileSize?.byteText ?? ""
    }
}
