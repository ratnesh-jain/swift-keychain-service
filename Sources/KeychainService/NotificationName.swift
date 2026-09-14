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
    static var didBecomeActiveNotification: Notification.Name {
        #if os(macOS)
        NSApplication.didBecomeActiveNotification
        #elseif os(iOS)
        UIApplication.didBecomeActiveNotification
        #endif
    }
    
    static var willResignActiveNotification: Notification.Name {
        #if os(macOS)
        NSApplication.willResignActiveNotification
        #elseif os(iOS)
        UIApplication.willResignActiveNotification
        #endif
    }
    
    public static var keychainDidChange: Notification.Name {
        Notification.Name("com.swift-keychain-service.notification.keychain-did-changed")
    }
}
