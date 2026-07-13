import UIKit
import UserNotifications
import UserNotificationsUI

/// Renders the expanded (long-press) view for notifications tagged with
/// category identifier "EVENT_WITH_PHOTO". Unlike the OS default attachment
/// preview (which sizes the image modestly), this gives full control: the
/// image fills the width of the notification at whatever height its aspect
/// ratio calls for.
///
/// NOTE: title/body are intentionally NOT rendered here. The extension's
/// Info.plist sets UNNotificationExtensionDefaultContentHidden = false,
/// which keeps the OS's own header (app icon + title + body) visible above
/// this view. Hiding that default content (the more common pattern) also
/// hides the app's icon — a longstanding iOS quirk — so showing the default
/// header is the tradeoff we make to keep the icon, and this view only
/// needs to contribute the enlarged image below it.
class NotificationViewController: UIViewController, UNNotificationContentExtension {

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private var imageAspectConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpLayout()
    }

    private func setUpLayout() {
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - UNNotificationContentExtension

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content

        guard let attachment = content.attachments.first else {
            imageView.image = nil
            imageAspectConstraint?.isActive = false
            return
        }

        // Attachments require security-scoped access to their file URL.
        let didStartAccessing = attachment.url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { attachment.url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: attachment.url),
              let image = UIImage(data: data) else { return }

        imageView.image = image

        // Size the notification to the image's real aspect ratio, capped
        // to a reasonable max height so a very tall photo doesn't take over
        // the whole screen.
        let aspectRatio = image.size.height / max(image.size.width, 1)
        let cappedRatio = min(aspectRatio, 1.0) // never taller than it is wide
        imageAspectConstraint?.isActive = false
        imageAspectConstraint = imageView.heightAnchor.constraint(
            equalTo: imageView.widthAnchor, multiplier: cappedRatio
        )
        imageAspectConstraint?.isActive = true

        preferredContentSize = CGSize(
            width: view.bounds.width,
            height: view.bounds.width * cappedRatio
        )
    }
}
