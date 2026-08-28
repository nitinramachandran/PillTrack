import SwiftUI
import UIKit

/// Full-screen camera for capturing one still photo of a medicine.
///
/// Wraps UIKit's `UIImagePickerController` camera, which takes plain still images —
/// never Live Photos. The captured image is handed back as JPEG data; the caller
/// decides whether to keep it.
struct CameraPhotoPicker: UIViewControllerRepresentable {
    /// Called with the captured photo data, or not at all when the user cancels.
    let onCapture: (Data) -> Void
    let onClose: () -> Void

    /// Whether this device can take photos (false on simulators and restricted devices).
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onClose: onClose)
    }

    /// Receives the camera's capture/cancel callbacks and forwards them to SwiftUI.
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Data) -> Void
        private let onClose: () -> Void

        init(onCapture: @escaping (Data) -> Void, onClose: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onClose = onClose
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // High initial quality: the image store downsamples and recompresses anyway,
            // so starting sharp keeps label text readable in the stored result.
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                onCapture(data)
            }
            onClose()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onClose()
        }
    }
}
