//
//  NotificationName.swift
//  swift-keychain-service
//
//  Created by Ratnesh Jain on 14/09/26.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    /// Platform-abstracted notification for when the application did become active.
    static var didBecomeActiveNotification: Notification.Name {
        #if os(macOS)
        NSApplication.didBecomeActiveNotification
        #elseif os(iOS)
        UIApplication.didBecomeActiveNotification
        #endif
    }
    
    /// Platform-abstracted notification for when the application will resign active.
    static var willResignActiveNotification: Notification.Name {
        #if os(macOS)
        NSApplication.willResignActiveNotification
        #elseif os(iOS)
        UIApplication.willResignActiveNotification
        #endif
    }
    
    /// A notification posted whenever a value is updated in the Keychain via `KeychainKey` or `KeychainStorage`.
    ///
    /// Observers can listen to this notification to react to changes in Keychain data.
    public static var keychainDidChange: Notification.Name {
        Notification.Name("com.swift-keychain-service.notification.keychain-did-changed")
    }
}
