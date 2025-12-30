import SwiftUI

struct SmartWatchImage: View {
    let localImageData: Data?
    let remoteURL: String?
    let height: CGFloat
    let cacheKey: String
    var showDebug: Bool = false
    var onDialColorDetected: ((Color) -> Void)?

    @State private var saliencyOffset: CGPoint
    @State private var initialDialColor: Color?
    @State private var isAnalyzing = false
    @State private var hasCachedResult: Bool

    init(
        localImageData: Data? = nil,
        remoteURL: String? = nil,
        height: CGFloat,
        cacheKey: String,
        showDebug: Bool = false,
        onDialColorDetected: ((Color) -> Void)? = nil
    ) {
        self.localImageData = localImageData
        self.remoteURL = remoteURL
        self.height = height
        self.cacheKey = cacheKey
        self.showDebug = showDebug
        self.onDialColorDetected = onDialColorDetected

        if let cached = SaliencyAnalyzer.cachedResult(for: cacheKey) {
            _saliencyOffset = State(initialValue: CGPoint(x: cached.offsetX, y: cached.offsetY))
            _hasCachedResult = State(initialValue: true)
            if let r = cached.dialColorR, let g = cached.dialColorG, let b = cached.dialColorB {
                _initialDialColor = State(initialValue: Color(r: r, g: g, b: b))
            } else {
                _initialDialColor = State(initialValue: nil)
            }
        } else {
            _saliencyOffset = State(initialValue: .zero)
            _hasCachedResult = State(initialValue: false)
            _initialDialColor = State(initialValue: nil)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let data = localImageData,
                   let uiImage = UIImage(data: data) {
                    localImage(uiImage, in: geometry)
                } else if let urlString = remoteURL,
                          let url = URL(string: urlString) {
                    remoteImage(url, in: geometry)
                } else {
                    placeholderView
                }

                if showDebug {
                    debugOverlay(geometry)
                }
            }
        }
        .frame(height: height)
        .clipped()
        .onAppear {
            if let color = initialDialColor {
                onDialColorDetected?(color)
            }
        }
    }

    @ViewBuilder
    private func debugOverlay(_ geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Offset: (\(String(format: "%.2f", saliencyOffset.x)), \(String(format: "%.2f", saliencyOffset.y)))")
                Text("Pixel: (\(String(format: "%.0f", pixelOffset(geometry).x)), \(String(format: "%.0f", pixelOffset(geometry).y)))")
                Text("Size: \(Int(geometry.size.width))x\(Int(geometry.size.height))")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.7))
            .cornerRadius(4)
            .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func localImage(_ uiImage: UIImage, in geometry: GeometryProxy) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .offset(x: pixelOffset(geometry).x, y: pixelOffset(geometry).y)
            .task {
                await analyzeLocal(uiImage)
            }
    }

    @ViewBuilder
    private func remoteImage(_ url: URL, in geometry: GeometryProxy) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .offset(x: pixelOffset(geometry).x, y: pixelOffset(geometry).y)
                    .onAppear {
                        Task { await analyzeRemote(url) }
                    }
            case .failure:
                placeholderView
            case .empty:
                ZStack {
                    Theme.Colors.surface
                    ProgressView()
                }
            @unknown default:
                placeholderView
            }
        }
    }

    private var placeholderView: some View {
        ZStack {
            Theme.Colors.surface
            Image(systemName: "watch.analog")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.3))
        }
    }

    private func pixelOffset(_ geometry: GeometryProxy) -> CGPoint {
        let maxX = geometry.size.width * 0.5
        let maxY = geometry.size.height * 0.35
        let x = saliencyOffset.x * maxX * -1
        let y = saliencyOffset.y * maxY * -1
        return CGPoint(x: x, y: y)
    }

    private func analyzeLocal(_ image: UIImage) async {
        guard !isAnalyzing, !hasCachedResult else { return }
        isAnalyzing = true

        let result = await SaliencyAnalyzer.shared.analyze(image, cacheKey: cacheKey)

        await MainActor.run {
            withAnimation(Theme.Animation.standard) {
                saliencyOffset = CGPoint(x: result.offsetX, y: result.offsetY)
            }
            notifyDialColor(from: result)
            isAnalyzing = false
        }
    }

    private func analyzeRemote(_ url: URL) async {
        guard !isAnalyzing, !hasCachedResult else { return }
        isAnalyzing = true

        let result = await SaliencyAnalyzer.shared.analyzeFromURL(url, cacheKey: cacheKey)

        await MainActor.run {
            withAnimation(Theme.Animation.standard) {
                saliencyOffset = CGPoint(x: result.offsetX, y: result.offsetY)
            }
            notifyDialColor(from: result)
            isAnalyzing = false
        }
    }

    private func notifyDialColor(from result: SaliencyResult) {
        if let r = result.dialColorR,
           let g = result.dialColorG,
           let b = result.dialColorB {
            let color = Color(r: r, g: g, b: b)
            onDialColorDetected?(color)
        }
    }
}
