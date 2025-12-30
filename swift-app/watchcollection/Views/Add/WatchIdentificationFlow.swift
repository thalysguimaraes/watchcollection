import SwiftUI
import PhotosUI

struct WatchIdentificationFlow: View {
    @Environment(NavigationRouter.self) private var router
    @State private var viewModel = WatchIdentificationViewModel()
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                switch viewModel.state {
                case .selectSource, .capturing:
                    SourcePickerContent(
                        onTakePhoto: {
                            Haptics.medium()
                            showCamera = true
                        },
                        onPhotoLibrary: {
                            Haptics.medium()
                            showPhotoPicker = true
                        }
                    )
                    .transition(.opacity)

                case .analyzing:
                    AnalyzingView(image: viewModel.selectedImage)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))

                case .results(let matches, let identification):
                    IdentificationResultsView(
                        matches: matches,
                        identification: identification,
                        onSelectMatch: { match in
                            router.dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                router.presentQuickAddToCollection(match.watchModel, brand: match.brand)
                            }
                        },
                        onSearchManually: {
                            router.dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                router.presentAddWatch()
                            }
                        },
                        onRetry: {
                            withAnimation(Theme.Animation.smooth) {
                                viewModel.retry()
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))

                case .noMatch(let identification):
                    IdentificationResultsView(
                        matches: [],
                        identification: identification,
                        onSelectMatch: { _ in },
                        onSearchManually: {
                            router.dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                router.presentAddWatch()
                            }
                        },
                        onRetry: {
                            withAnimation(Theme.Animation.smooth) {
                                viewModel.retry()
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))

                case .error(let message):
                    ErrorView(
                        message: message,
                        onRetry: {
                            withAnimation(Theme.Animation.smooth) {
                                viewModel.retry()
                            }
                        },
                        onCancel: {
                            router.dismiss()
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(Theme.Animation.smooth, value: viewModel.stateKey)
            .navigationTitle("Identify Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        router.dismiss()
                    }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(
                    onImageCaptured: { image in
                        showCamera = false
                        Haptics.success()
                        withAnimation(Theme.Animation.smooth) {
                            viewModel.selectImage(image)
                        }
                    },
                    onCancel: {
                        showCamera = false
                    }
                )
            }
            .onChange(of: selectedItem) { _, item in
                Task {
                    if let item, let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        Haptics.success()
                        withAnimation(Theme.Animation.smooth) {
                            viewModel.selectImage(image)
                        }
                    }
                }
            }
        }
    }
}

private struct SourcePickerContent: View {
    let onTakePhoto: () -> Void
    let onPhotoLibrary: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.Colors.accent)

                Text("Choose a photo")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Take a photo of a watch or select from your library")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                Button(action: onTakePhoto) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Photo")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(action: onPhotoLibrary) {
                    HStack {
                        Image(systemName: "photo.fill")
                        Text("Photo Library")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
    }
}

private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    @State private var iconScale: CGFloat = 0.5
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.warning)
                    .scaleEffect(iconScale)

                Text("Something Went Wrong")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .opacity(contentOpacity)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .opacity(contentOpacity)
            }

            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                Button {
                    Haptics.medium()
                    onRetry()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    Haptics.light()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
            .opacity(contentOpacity)
        }
        .background(Theme.Colors.background)
        .onAppear {
            withAnimation(Theme.Animation.bouncy.delay(0.1)) {
                iconScale = 1.0
            }
            withAnimation(Theme.Animation.smooth.delay(0.2)) {
                contentOpacity = 1.0
            }
        }
    }
}

#Preview {
    WatchIdentificationFlow()
        .environment(NavigationRouter())
}
