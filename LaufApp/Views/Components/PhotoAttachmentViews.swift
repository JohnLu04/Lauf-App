import SwiftUI
import PhotosUI

/// Kamera zum Aufnehmen eines Fotos (nur auf Geräten mit Kamera).
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Mediathek und Kamera zum Anhängen von Fotos; liefert die gewählten Fotos über `onAdd`.
private struct PhotoAttachmentPickers: ViewModifier {
    @Binding var showLibrary: Bool
    @Binding var showCamera: Bool
    @Binding var isLoading: Bool
    let onAdd: ([PendingPhoto]) -> Void
    @State private var items: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showLibrary, selection: $items, maxSelectionCount: 20,
                          matching: .any(of: [.images, .videos]))
            .onChange(of: items) { _, selected in
                guard !selected.isEmpty else { return }
                items = []
                Task {
                    isLoading = true
                    let loaded = await PhotoAttachment.load(selected)
                    isLoading = false
                    onAdd(loaded)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    guard let data = image.jpegData(compressionQuality: 0.95) else { return }
                    Task {
                        let photo = await Task.detached(priority: .userInitiated) {
                            PhotoAttachment.pending(imageData: data)
                        }.value
                        if let photo { onAdd([photo]) }
                    }
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func photoAttachmentPickers(showLibrary: Binding<Bool>, showCamera: Binding<Bool>, isLoading: Binding<Bool>,
                                onAdd: @escaping ([PendingPhoto]) -> Void) -> some View {
        modifier(PhotoAttachmentPickers(showLibrary: showLibrary, showCamera: showCamera, isLoading: isLoading, onAdd: onAdd))
    }
}

/// Knopf zum Hinzufügen: mit Kamera als Menü (Mediathek oder Kamera), sonst direkt die Mediathek.
struct AddPhotoButton<Label: View>: View {
    @Binding var showLibrary: Bool
    @Binding var showCamera: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        if CameraPicker.isAvailable {
            Menu {
                Button("Aus der Mediathek", systemImage: "photo.on.rectangle") { showLibrary = true }
                Button("Foto aufnehmen", systemImage: "camera") { showCamera = true }
            } label: { label() }
        } else {
            Button { showLibrary = true } label: { label() }
        }
    }
}

/// Fotos im Formular nach dem Lauf bzw. beim Eintragen: Vorschau, Entfernen, Hinzufügen.
struct PendingPhotosSection: View {
    @Binding var photos: [PendingPhoto]
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var isLoading = false

    var body: some View {
        Section {
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            LocalPhotoView(url: photo.imageFile, maxPixelSize: 300)
                                .frame(width: 88, height: 88)
                                .overlay { if photo.isVideo { VideoBadge(size: 30) } }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        photo.discard()
                                        withAnimation { photos.removeAll { $0.id == photo.id } }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.borderless)
                                    .padding(3)
                                    .accessibilityLabel(photo.isVideo ? "Video entfernen" : "Foto entfernen")
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            AddPhotoButton(showLibrary: $showLibrary, showCamera: $showCamera) {
                HStack {
                    Label(photos.isEmpty ? "Fotos hinzufügen" : "Weitere Fotos hinzufügen", systemImage: "photo.badge.plus")
                    if isLoading {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isLoading)
            // Am Knopf statt am Abschnitt: An einem Abschnitt im Formular erscheinen die Auswahlfenster nicht
            .photoAttachmentPickers(showLibrary: $showLibrary, showCamera: $showCamera, isLoading: $isLoading) { added in
                withAnimation { photos.append(contentsOf: added) }
            }
        } header: {
            Text("Fotos")
        }
    }
}
