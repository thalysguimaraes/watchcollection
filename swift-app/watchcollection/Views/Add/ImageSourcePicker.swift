import SwiftUI
import PhotosUI

struct ImageSourcePicker: View {
    let onImageSelected: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var showCamera = false
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Spacing.xs) {
                Text("Identify Watch")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)

                Text("Choose a photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.sm) {
                Button {
                    Haptics.medium()
                    showCamera = true
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 28)
                        Text("Take Photo")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 14)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(SheetButtonStyle())

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 28)
                        Text("Photo Library")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 14)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(SheetButtonStyle())
                .onChange(of: selectedItem) { _, item in
                    Task {
                        if let item, let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            Haptics.success()
                            onImageSelected(image)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()

            Button {
                Haptics.light()
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(onImageCaptured: { image in
                showCamera = false
                Haptics.success()
                onImageSelected(image)
            }, onCancel: {
                showCamera = false
            })
        }
    }
}

private struct SheetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(Theme.Animation.quick, value: configuration.isPressed)
    }
}

struct CameraView: View {
    let onImageCaptured: (UIImage) -> Void
    let onCancel: () -> Void

    var body: some View {
        CameraViewRepresentable(onImageCaptured: onImageCaptured, onCancel: onCancel)
            .background(Color.black)
            .ignoresSafeArea(.all)
    }
}

private struct CameraViewRepresentable: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImageCaptured = onImageCaptured
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
