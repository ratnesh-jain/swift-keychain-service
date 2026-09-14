//
//  KeychainKey.swift
//  swift-keychain-service
//
//  Created by Ratnesh Jain on 14/09/26.
//

import Dependencies
import Foundation
import Sharing

/// A `SharedKey` strategy that persists `Codable` and `Sendable` values in the system Keychain.
///
/// `KeychainKey` connects Point-Free's `swift-sharing` framework with Keychain storage, allowing you
/// to use `@Shared(.keychain("key"))` to seamlessly persist sensitive values (e.g., authentication tokens,
/// credentials, and session state) with automatic observation and persistence.
///
/// ### Overview
/// When initialized, `KeychainKey` reads and writes data via the `defaultKeychainStorage` and
/// `defaultKeychainJSONDecoder` / `defaultKeychainJSONEncoder` dependencies. It also sets up subscriptions
/// on app lifecycle notifications (`didBecomeActiveNotification`, `willResignActiveNotification`) and
/// internal change notifications (`keychainDidChange`) to synchronize external modifications across processes
/// and app sessions.
///
/// ### Example
/// ```swift
/// import Sharing
/// import KeychainService
///
/// final class AuthModel {
///     @Shared(.keychain("auth_token")) var authToken: String?
///     @Shared(.keychain("user_session")) var session: UserSession?
/// }
/// ```
public struct KeychainKey<Value: Codable & Sendable>: SharedKey {
    /// The unique Keychain key used to store and retrieve the value.
    let key: String
    
    /// Initializes a `KeychainKey` with a specific Keychain identifier.
    ///
    /// - Parameter key: The unique key associated with the stored value in Keychain.
    public init(key: String) {
        self.key = key
    }
    
    /// The unique identifier for this shared key.
    public var id: some Hashable { self.key }
    
    /// Loads the value from Keychain asynchronously.
    ///
    /// - Parameters:
    ///   - context: The load context containing any default initial value.
    ///   - continuation: Continuation used to deliver the loaded value or report errors.
    public func load(context: LoadContext<Value>, continuation: LoadContinuation<Value>) {
        @Dependency(\.defaultKeychainStorage) var keychain
        @Dependency(\.defaultKeychainJSONDecoder) var decoder
        
        do {
            if let value = try value(in: context) {
                continuation.resume(returning: value)
            } else {
                continuation.resumeReturningInitialValue()
            }
        } catch {
            continuation.resume(throwing: error)
        }
    }
    
    /// Subscribes to external notifications to reload values when changes occur.
    ///
    /// Observes application active notifications as well as `Notification.Name.keychainDidChange`.
    ///
    /// - Parameters:
    ///   - context: The load context for resolving initial values.
    ///   - subscriber: The subscriber receiving updated values or errors.
    /// - Returns: A `SharedSubscription` managing the observation lifecycle.
    public func subscribe(
      context: LoadContext<Value>, subscriber: SharedSubscriber<Value>
    ) -> SharedSubscription {
        let task = Task {
            await withDiscardingTaskGroup { group in
                group.addTask {
                    for await _ in NotificationCenter.default.notifications(named: .didBecomeActiveNotification) {
                        do {
                            if let value = try value(in: context) {
                                subscriber.yield(value)
                            } else {
                                subscriber.yieldReturningInitialValue()
                            }
                        } catch {
                            subscriber.yield(throwing: error)
                        }
                    }
                }
                group.addTask {
                    for await _ in NotificationCenter.default.notifications(named: .willResignActiveNotification) {
                        do {
                            if let value = try value(in: context) {
                                subscriber.yield(value)
                            } else {
                                subscriber.yieldReturningInitialValue()
                            }
                        } catch {
                            subscriber.yield(throwing: error)
                        }
                    }
                }
                
                group.addTask {
                    for await _ in NotificationCenter.default.notifications(named: .keychainDidChange) {
                        do {
                            if let value = try value(in: context) {
                                subscriber.yield(value)
                            } else {
                                subscriber.yieldReturningInitialValue()
                            }
                        } catch {
                            subscriber.yield(throwing: error)
                        }
                    }
                }
            }
        }
        
        return .init {
            task.cancel()
        }
    }
    
    /// Persists a value to Keychain and broadcasts a change notification.
    ///
    /// - Parameters:
    ///   - value: The value to persist in Keychain.
    ///   - context: The save context.
    ///   - continuation: Continuation used to signal completion of the save operation.
    public func save(_ value: Value, context: SaveContext, continuation: SaveContinuation) {
        continuation.resume(with: Result {
            @Dependency(\.defaultKeychainStorage) var keychain
            try keychain.setValue(value, for: key)
            NotificationCenter.default.post(name: .keychainDidChange, object: nil)
        })
    }
    
    private func value(in context: LoadContext<Value>) throws -> Value? {
        @Dependency(\.defaultKeychainStorage) var keychain
        @Dependency(\.defaultKeychainJSONDecoder) var decoder
        if let existingValue: Value? = try keychain.value(for: key) {
            if let existingValue {
                return existingValue
            } else if let initialValue = context.initialValue {
                try keychain.setValue(initialValue, for: key)
                return initialValue
            }
        }
        return nil
    }
}

extension SharedReaderKey {
    /// Creates a shared key for reading and writing values in the system Keychain.
    ///
    /// Use this function with `@Shared` or `@SharedReader` to seamlessly bind a property to a Keychain value.
    ///
    /// ```swift
    /// struct State {
    ///     @Shared(.keychain("access_token")) var accessToken: String?
    ///     @Shared(.keychain("user_profile")) var userProfile: UserProfile?
    /// }
    /// ```
    ///
    /// - Parameter key: The Keychain key used to store and retrieve data.
    /// - Returns: A `KeychainKey` instance configured with the specified key.
    public static func keychain<Value: Codable & Sendable>(_ key: String) -> Self
    where Self == KeychainKey<Value> {
        KeychainKey(key: key)
    }
}
