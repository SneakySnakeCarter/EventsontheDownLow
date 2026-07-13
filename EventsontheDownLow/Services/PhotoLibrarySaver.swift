import UIKit
import Photos

/// Saves a copy of an event photo to the user's system Photos library, on
/// explicit request only. Uses "add-only" authorization — a narrower,
/// write-only permission separate from full library read access, so this
/// never grants the app the ability to browse or read the user's existing
/// photos (that's what NSPhotoLibraryAddUsageDescription communicates to
/// the user in the system permission prompt).
enum PhotoLibrarySaver {

    enum SaveResult {
        case success
        case denied
        case failed(Error)
    }

    static func save(_ image: UIImage, completion: @escaping (SaveResult) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }, completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            completion(.success)
                        } else if let error {
                            completion(.failed(error))
                        } else {
                            completion(.denied)
                        }
                    }
                })
            case .denied, .restricted, .notDetermined:
                DispatchQueue.main.async { completion(.denied) }
            @unknown default:
                DispatchQueue.main.async { completion(.denied) }
            }
        }
    }
}
