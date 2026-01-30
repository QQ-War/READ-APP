import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == "com.readapp.packagedownload" {
            PackageDownloadManager.shared.setBackgroundCompletionHandler(completionHandler, for: identifier)
        } else {
            BookUploadService.shared.setBackgroundCompletionHandler(completionHandler)
        }
    }
}
