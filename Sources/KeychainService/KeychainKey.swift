//
//  KeychainKey.swift
//  swift-keychain-service
//
//  Created by Ratnesh Jain on 14/09/26.
//

import ConcurrencyExtras
import Dependencies
import Foundation
import Sharing

private enum SharedKeychainLocals {
    @TaskLocal static var isSetting = false
}

/// A `SharedKey` strategy that persists `Codable` and `Sendable` values in the system Keychain.
///
/// `KeychainKey` connects Point-Free's `swift-sharing` framework with Keychain storage, allowing you
/// to use `@Shared(.keychain("key"))` to seamlessly persist sensitive values (e.g., authentication tokens,
/// credentials, and session state) with automatic observation and persistence.
///
/// ### Overview
/// When initialized, `KeychainKey` captures the active `defaultKeychainStorage` and
/// `defaultKeychainJSONDecoder` / `defaultKeychainJSONEncoder` dependencies from the environment.
/// It also sets up subscriptions on app lifecycle notifications (`didBecomeActiveNotification`,
/// `willResignActiveNotification`) and internal change notifications (`keychainDidChange`)
/// to synchronize modifications across components and app sessions.
///
/// ### Example
/// ```swift
/// import Sharing
/// import KeychainService
///
/// final class AuthModel {
///     @Shared(.keychain("auth_token")) var authToken: String?
///     @Shared(.keychain("user_session")) var session: UserSession?
///     @Shared(.keychain("is_logged_in")) var isLoggedIn: Bool = false
/// }
/// ```
public struct KeychainKey<Value: Codable & Sendable>: SharedKey {
    /// The unique Keychain key used to store and retrieve the value.
    let key: String
    private let storage: KeychainStorage
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    /// Initializes a `KeychainKey` with a specific Keychain identifier and optional explicit dependencies.
    ///
    /// - Parameters:
    ///   - key: The unique key associated with the stored value in Keychain.
    ///   - storage: Optional explicit `KeychainStorage`. If `nil`, resolves `\.defaultKeychainStorage`.
    ///   - decoder: Optional explicit `JSONDecoder`. If `nil`, resolves `\.defaultKeychainJSONDecoder`.
    ///   - encoder: Optional explicit `JSONEncoder`. If `nil`, resolves `\.defaultKeychainJSONEncoder`.
    public init(
        key: String,
        storage: KeychainStorage? = nil,
        decoder: JSONDecoder? = nil,
        encoder: JSONEncoder? = nil
    ) {
        @Dependency(\.defaultKeychainStorage) var defaultStorage
        @Dependency(\.defaultKeychainJSONDecoder) var defaultDecoder
        @Dependency(\.defaultKeychainJSONEncoder) var defaultEncoder
        self.key = key
        self.storage = storage ?? defaultStorage
        self.decoder = decoder ?? defaultDecoder
        self.encoder = encoder ?? defaultEncoder
    }
    
    /// The unique identifier for this shared key.
    public var id: some Hashable { self.key }
    
    /// Loads the value from Keychain asynchronously.
    ///
    /// - Parameters:
    ///   - context: The load context containing any default initial value.
    ///   - continuation: Continuation used to deliver the loaded value or report errors.\
    public func load(context: LoadContext<Value>, continuation: LoadContinuation<Value>) {
        print(#function)
        do {
            if let data = storage.getData(key) {
                let decoded = try decoder.decode(Value.self, from: data)
                continuation.resume(returning: decoded)
            } else if let initialValue = context.initialValue {
                guard !SharedKeychainLocals.isSetting else {
                    continuation.resumeReturningInitialValue()
                    return
                }
                SharedKeychainLocals.$isSetting.withValue(true) {
                    if !isNil(initialValue) {
                        if let data = try? encoder.encode(initialValue) {
                            storage.set(data, key)
                        }
                    }
                }
                continuation.resume(returning: initialValue)
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
        let previousValue = LockIsolated<Value?>(context.initialValue ?? nil)
        
        let observer1 = UncheckedSendable(
            NotificationCenter.default.addObserver(
                forName: .didBecomeActiveNotification,
                object: nil,
                queue: nil
            ) { _ in
                guard !SharedKeychainLocals.isSetting else { return }
                yieldCurrentValue(in: context, to: subscriber, previousValue: previousValue)
            }
        )
        
        let observer2 = UncheckedSendable(
            NotificationCenter.default.addObserver(
                forName: .willResignActiveNotification,
                object: nil,
                queue: nil
            ) { _ in
                guard !SharedKeychainLocals.isSetting else { return }
                yieldCurrentValue(in: context, to: subscriber, previousValue: previousValue)
            }
        )
        
        let observer3 = UncheckedSendable(
            NotificationCenter.default.addObserver(
                forName: .keychainDidChange,
                object: nil,
                queue: nil
            ) { notification in
                print("didChange Observer notification called: \(notification)")
                if let targetStorageID = notification.object as? UUID, targetStorageID != storage.storageID {
                    return
                }
                if let targetKey = notification.userInfo?["key"] as? String, targetKey != key {
                    return
                }
                guard !SharedKeychainLocals.isSetting else { return }
                yieldCurrentValue(in: context, to: subscriber, previousValue: previousValue)
            }
        )
        
        return .init {
            NotificationCenter.default.removeObserver(observer1.wrappedValue)
            NotificationCenter.default.removeObserver(observer2.wrappedValue)
            NotificationCenter.default.removeObserver(observer3.wrappedValue)
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
            try SharedKeychainLocals.$isSetting.withValue(true) {
                if isNil(value) {
                    storage.delete(key)
                } else {
                    let data = try encoder.encode(value)
                    storage.set(data, key)
                }
            }
        })
    }
    
    private func yieldCurrentValue(
        in context: LoadContext<Value>,
        to subscriber: SharedSubscriber<Value>,
        previousValue: LockIsolated<Value?>
    ) {
        do {
            if let data = storage.getData(key) {
                let decoded = try decoder.decode(Value.self, from: data)
                let shouldYield = previousValue.withValue { prev -> Bool in
                    defer { prev = decoded }
                    guard let prev else { return true }
                    guard let equal = isEqual(prev, decoded) else { return true }
                    return !equal
                }
                if shouldYield {
                    subscriber.yield(decoded)
                }
            } else if let nilValue = (Value.self as? ExpressibleByNilLiteral.Type)?.init(nilLiteral: ()) as? Value {
                let shouldYield = previousValue.withValue { prev -> Bool in
                    defer { prev = nilValue }
                    guard let prev else { return true }
                    guard let equal = isEqual(prev, nilValue) else { return true }
                    return !equal
                }
                if shouldYield {
                    subscriber.yield(nilValue)
                }
            } else {
                if let initialValue = context.initialValue {
                    subscriber.yield(initialValue)
                }
            }
        } catch {
            subscriber.yield(throwing: error)
        }
    }
    
    private func isNil(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            return mirror.children.isEmpty
        }
        return false
    }
    
    private func isEqual(_ lhs: Value, _ rhs: Value) -> Bool? {
        guard let lhs = lhs as? any Equatable else { return nil }
        func open<T: Equatable>(_ lhs: T) -> Bool? {
            (rhs as? T).map { lhs == $0 }
        }
        return open(lhs)
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
    ///     @Shared(.keychain("is_logged_in")) var isLoggedIn: Bool = false
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - key: The Keychain key used to store and retrieve data.
    ///   - storage: Optional explicit `KeychainStorage`. If `nil`, uses `\.defaultKeychainStorage`.
    ///   - decoder: Optional explicit `JSONDecoder`. If `nil`, uses `\.defaultKeychainJSONDecoder`.
    ///   - encoder: Optional explicit `JSONEncoder`. If `nil`, uses `\.defaultKeychainJSONEncoder`.
    /// - Returns: A `KeychainKey` instance configured with the specified parameters.
    public static func keychain<Value: Codable & Sendable>(
        _ key: String,
        storage: KeychainStorage? = nil,
        decoder: JSONDecoder? = nil,
        encoder: JSONEncoder? = nil
    ) -> Self where Self == KeychainKey<Value> {
        KeychainKey(key: key, storage: storage, decoder: decoder, encoder: encoder)
    }
}
