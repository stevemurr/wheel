import SwiftUI
import Combine

extension View {
    /// Subscribes to a notification and executes a handler when received
    /// - Parameters:
    ///   - name: The notification name to observe
    ///   - handler: The closure to execute when the notification is received
    /// - Returns: A view that observes the notification
    func onNotification(
        _ name: Notification.Name,
        perform handler: @escaping () -> Void
    ) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: name)) { _ in
            handler()
        }
    }

    /// Subscribes to a notification and executes a handler with the notification object
    /// - Parameters:
    ///   - name: The notification name to observe
    ///   - handler: The closure to execute when the notification is received, with the notification object
    /// - Returns: A view that observes the notification
    func onNotification<T>(
        _ name: Notification.Name,
        object: @escaping (T?) -> Void
    ) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: name)) { notification in
            object(notification.object as? T)
        }
    }

    /// Subscribes to a notification and executes a handler with the notification
    /// - Parameters:
    ///   - name: The notification name to observe
    ///   - handler: The closure to execute with the full notification
    /// - Returns: A view that observes the notification
    func onNotification(
        _ name: Notification.Name,
        notification handler: @escaping (Notification) -> Void
    ) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: name)) { notification in
            handler(notification)
        }
    }
}
