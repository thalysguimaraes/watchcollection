import SwiftUI

import SwiftUI

struct PhotoGalleryView: View {
    let photos: [WatchPhoto]
    let catalogImageURL: String?
    @State private var currentIndex = 0
    @State private var showFullscreen = false

    private var hasContent: Bool {
        !photos.isEmpty || catalogImageURL != nil
    }

    var body: some View {
        if hasContent {
            ZStack(alignment: .bottom) {
                TabView(selection: $currentIndex) {
                    if let urlString = catalogImageURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                placeholderView
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            @unknown default:
                                placeholderView
                            }
                        }
                        .tag(0)
                        .onTapGesture {
                            Haptics.light()
                            showFullscreen = true
                        }
                    }

                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        if let data = photo.imageData,
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .tag(catalogImageURL != nil ? index + 1 : index)
                                .onTapGesture {
                                    Haptics.light()
                                    showFullscreen = true
                                }
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if totalCount > 1 {
                    pageIndicator
                }
            }
            .fullScreenCover(isPresented: $showFullscreen) {
                FullscreenPhotoView(
                    photos: photos,
                    catalogImageURL: catalogImageURL,
                    initialIndex: currentIndex
                )
            }
        } else {
            placeholderView
        }
    }

    private var totalCount: Int {
        photos.count + (catalogImageURL != nil ? 1 : 0)
    }

    private var pageIndicator: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(0..<totalCount, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Theme.Colors.accent : .white.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == currentIndex ? 1.2 : 1.0)
                    .animation(Theme.Animation.quick, value: currentIndex)
            }
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, Theme.Spacing.md)
    }

    private var placeholderView: some View {
        ZStack {
            Theme.Colors.surface
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.4))
                Text("No Photos")
                    .font(Theme.Typography.sans(.caption))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}

struct FullscreenPhotoView: View {
    let photos: [WatchPhoto]
    let catalogImageURL: String?
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                if let urlString = catalogImageURL, let url = URL(string: urlString) {
                    ZoomableImageView {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFit()
                            }
                        }
                    }
                    .tag(0)
                }

                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    if let data = photo.imageData,
                       let uiImage = UIImage(data: data) {
                        ZoomableImageView {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                        }
                        .tag(catalogImageURL != nil ? index + 1 : index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset.height)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        if abs(value.translation.height) > abs(value.translation.width) {
                            state = value.translation
                        }
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > 100 {
                            dismiss()
                        }
                    }
            )

            VStack {
                HStack {
                    Spacer()
                    Button {
                        Haptics.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding()
                }
                Spacer()

                if totalCount > 1 {
                    pageCounter
                }
            }
        }
        .onAppear {
            currentIndex = initialIndex
        }
        .statusBarHidden()
    }

    private var totalCount: Int {
        photos.count + (catalogImageURL != nil ? 1 : 0)
    }

    private var pageCounter: some View {
        Text("\(currentIndex + 1) / \(totalCount)")
            .font(Theme.Typography.sans(.caption, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.bottom, Theme.Spacing.xl)
    }
}

struct ZoomableImageView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        content()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale = min(max(scale * delta, 1), 4)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        if scale < 1.2 {
                            withAnimation(Theme.Animation.smooth) {
                                scale = 1.0
                                offset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                scale > 1 ?
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
                : nil
            )
            .onTapGesture(count: 2) {
                Haptics.light()
                withAnimation(Theme.Animation.smooth) {
                    if scale > 1 {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2.5
                    }
                }
            }
    }
}

#Preview {
    PhotoGalleryView(
        photos: [],
        catalogImageURL: "https://example.com/watch.jpg"
    )
    .frame(height: 300)
}
