import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

/// Holds only a readable, user-confirmed image; picker handles are never upload state.
struct DriverDocumentPhotoPicker: View {
    let title: String
    let identifier: String
    @Binding var data: Data?
    @State private var item: PhotosPickerItem?
    @State private var photoLibrary = false
    @State private var pendingLibraryPhoto: Data?
    @State private var camera = false
    @State private var candidate: Data?
    private struct ReviewPhoto: Identifiable { let id = UUID(); let data: Data }
    @State private var reviewPhoto: ReviewPhoto?
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 10) {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(height: 115)
                    .accessibilityLabel("\(title) confirmed preview").accessibilityIdentifier(identifier + "Preview")
            } else {
                Image(systemName: "doc.viewfinder").font(.largeTitle).foregroundStyle(Styles.rydrGradient)
            }
            Text(title).font(.headline)
            Menu {
                Button("Take Photo", systemImage: "camera") { openCamera() }
                    .accessibilityIdentifier(identifier + "Camera")
                // Present from the stable parent view, not a disappearing Menu row.
                Button("Choose from Photo Library", systemImage: "photo") { photoLibrary = true }
                    .accessibilityIdentifier(identifier + "Library")
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-DriverDocumentUITest") {
                    Button("Use sample document") {
                        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 240)).image { context in
                            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 240))
                            ("SAMPLE — \(title)" as NSString).draw(at: CGPoint(x: 20, y: 80), withAttributes: [.foregroundColor: UIColor.black])
                        }
                        prepare(image.jpegData(compressionQuality: 0.9))
                    }
                }
                #endif
            } label: {
                Label(loading ? "Loading…" : data == nil ? "Add Photo" : "Replace Photo", systemImage: "camera.fill")
                    .font(.subheadline.bold()).foregroundStyle(Styles.rydrGradient)
            }
            .accessibilityIdentifier(identifier + "Source")
            .disabled(loading)
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity).padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .photosPicker(isPresented: $photoLibrary, selection: $item, matching: .images)
        .onChange(of: photoLibrary) { _, presented in
            if !presented, let pendingLibraryPhoto {
                self.pendingLibraryPhoto = nil
                prepare(pendingLibraryPhoto)
            }
        }
        .onChange(of: item) { _, value in
            guard let value else { return }
            loading = true; message = nil
            Task { @MainActor in
                do {
                    guard let bytes = try await value.loadTransferable(type: Data.self) else {
                        message = "Unable to read this photo. Please select it again."
                        loading = false
                        item = nil
                        return
                    }
                    if photoLibrary { pendingLibraryPhoto = bytes }
                    else { prepare(bytes) }
                }
                catch { message = "Unable to read this photo. Please select it again." }
                loading = false
                item = nil
            }
        }
        .sheet(isPresented: $camera, onDismiss: { if let candidate { prepare(candidate); self.candidate = nil } }) {
            DriverDocumentCamera { image in
                candidate = image?.jpegData(compressionQuality: 0.9)
                camera = false
            }.ignoresSafeArea()
        }
        .sheet(item: $reviewPhoto) { photo in
            NavigationStack {
                VStack(spacing: 20) {
                    Text("Confirm \(title)").font(.title2.bold())
                    Text("Make sure the whole document is visible and the text is clear.").foregroundStyle(.secondary)
                    if let image = UIImage(data: photo.data) {
                        Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Selected document preview").accessibilityIdentifier("documentReviewPreview")
                    }
                    Button("Use Photo") { data = photo.data; reviewPhoto = nil }
                        .buttonStyle(.borderedProminent).tint(.red).accessibilityIdentifier("documentUsePhoto")
                    Button("Choose Another Photo") { reviewPhoto = nil }
                }.padding().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { reviewPhoto = nil } } }
            }
        }
    }

    private func prepare(_ value: Data?) {
        guard let value, let image = UIImage(data: value), let jpeg = image.jpegData(compressionQuality: 0.9) else {
            message = "This file is not a readable photo. Choose another image."; return
        }
        reviewPhoto = ReviewPhoto(data: jpeg); message = nil
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            message = "A camera is not available on this device. You can choose a photo from your library."; return
        }
        Task { @MainActor in
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            let allowed: Bool
            if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
            else { allowed = status == .authorized }
            if allowed { candidate = nil; message = nil; camera = true }
            else { message = "Allow camera access in Settings to take a document photo." }
        }
    }
}

private struct DriverDocumentCamera: UIViewControllerRepresentable {
    let onComplete: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (UIImage?) -> Void
        init(onComplete: @escaping (UIImage?) -> Void) { self.onComplete = onComplete }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onComplete(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onComplete(nil) }
    }
}

#if DEBUG && targetEnvironment(simulator)
struct DriverDocumentUITestFixture: View {
    @State private var number = "SAMPLE123"
    @State private var state = "GA"
    @State private var front: Data?
    @State private var back: Data?
    @State private var complete = false
    @State private var vin = "1G1ZD5ST0NF000001"
    @State private var decoded: DecodedVehicleInfo? = DecodedVehicleInfo(vin: "1G1ZD5ST0NF000001", make: "Chevrolet", model: "Malibu", year: "2022", fuelType: .gas)
    @State private var color: VehicleColor? = .silver
    @State private var image: VehicleImageInfo?
    @State private var plate = "SAMPLE"
    var body: some View {
        if complete { Text("License step complete").accessibilityIdentifier("licenseStepComplete") }
        else if ProcessInfo.processInfo.arguments.contains("-DocumentVehicle") {
            VehicleInfoView(vin: $vin, decoded: $decoded, selectedColor: $color, imageInfo: $image, plate: $plate, registrationDoc: $front, insuranceCard: $back, onNext: {})
        } else {
            DriverLicenseView(licenseNumber: $number, licenseState: $state, front: $front, back: $back, onNext: { complete = true })
        }
    }
}
#endif
