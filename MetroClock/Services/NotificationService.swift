import Foundation
import UIKit
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

final class NotificationService: NSObject {
    static let shared = NotificationService()

    private let db = Firestore.firestore()

    private override init() {
        super.init()
    }

    // MARK: - Permission Request

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Save FCM Token to Firestore

    func saveToken(userId: String) {
        Messaging.messaging().token { token, error in
            guard let token = token, error == nil else { return }
            self.db.collection("users").document(userId).updateData(["fcmToken": token])
        }
    }
}

// MARK: - MessagingDelegate

extension NotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Token refresh handled by saveToken(userId:) called after login
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
