//
//  KeychainService.swift
//  swift-keychain-service
//
//  Created by Ratnesh Jain on 14/09/26.
//

import ConcurrencyExtras
import Dependencies
import DependenciesMacros
import Foundation
@preconcurrency import KeychainSwift

private enum DefaultKeychainJSONDecoderKey: DependencyKey {
    static var liveValue: JSONDecoder { JSONDecoder() }
    static var previewValue: JSONDecoder { JSONDecoder() }
    static var testValue: JSONDecoder { JSONDecoder() }
}

private enum DefaultKeychainJSONEncoderKey: DependencyKey {
    static var liveValue: JSONEncoder { JSONEncoder() }
    static var previewValue: JSONEncoder { JSONEncoder() }
    static var testValue: JSONEncoder { JSONEncoder() }
}

extension DependencyValues {
    /// The default JSON decoder used for decoding Keychain values.
    ///
    /// Override this dependency to customize date decoding strategies, key decoding strategies,
    /// or other JSON decoding configurations when reading Codable values from Keychain.
    ///
    /// ```swift
    /// withDependencies {
    ///     let decoder = JSONDecoder()
    ///     decoder.dateDecodingStrategy = .iso8601
    ///     $0.defaultKeychainJSONDecoder = decoder
    /// } operation: {
    ///     // Decodes values with custom configuration
    /// }
    /// ```
    public var defaultKeychainJSONDecoder: JSONDecoder {
        get { self[DefaultKeychainJSONDecoderKey.self] }
        set { self[DefaultKeychainJSONDecoderKey.self] = newValue }
    }
    
    /// The default JSON encoder used for encoding Keychain values.
    ///
    /// Override this dependency to customize date encoding strategies, key encoding strategies,
    /// or other JSON encoding configurations when persisting Codable values to Keychain.
    ///
    /// ```swift
    /// withDependencies {
    ///     let encoder = JSONEncoder()
    ///     encoder.dateEncodingStrategy = .iso8601
    ///     $0.defaultKeychainJSONEncoder = encoder
    /// } operation: {
    ///     // Encodes values with custom configuration
    /// }
    /// ```
    public var defaultKeychainJSONEncoder: JSONEncoder {
        get { self[DefaultKeychainJSONEncoderKey.self] }
        set { self[DefaultKeychainJSONEncoderKey.self] = newValue }
    }
}

/// A client interface for low-level Keychain data storage and retrieval.
///
/// `KeychainStorage` conforms to `DependencyClient` and `DependencyKey`, allowing it to be injected
/// into features via Point-Free's `swift-dependencies` library.
///
/// ### Overview
/// `KeychainStorage` abstracts reading and writing raw `Data` to and from the Keychain. In production (`liveValue`),
/// it delegates to `KeychainSwift`. In previews and tests (`previewValue`), it uses an in-memory thread-safe `LockIsolated` dictionary,
/// avoiding side effects to the actual device Keychain.
///
/// ### Usage
///
/// ```swift
/// @Dependency(\.defaultKeychainStorage) var keychain
///
/// // Storing raw data
/// keychain.set(data, "authToken")
///
/// // Retrieving raw data
/// if let data = keychain.getData("authToken") {
///     // Process data
/// }
///
/// // Deleting raw data
/// keychain.delete("authToken")
///
/// // Storing and retrieving Codable values
/// try keychain.setValue(userSession, for: "session")
/// let session: UserSession? = try keychain.value(for: "session")
///
/// // Deleting Codable values by passing nil
/// try keychain.setValue(nil as UserSession?, for: "session")
/// ```
@DependencyClient
public struct KeychainStorage: Sendable {
    /// Unique identifier distinguishing storage instances.
    public var storageID: UUID = UUID()
    
    /// Retrieves raw data from the Keychain for a given key.
    ///
    /// - Parameter key: The unique identifier key in the Keychain.
    /// - Returns: The stored `Data` if present; otherwise, `nil`.
    public var getData: @Sendable (_ key: String) -> Data? = { _ in nil }
    
    /// Sets raw data into the Keychain for a given key.
    ///
    /// - Parameters:
    ///   - data: The `Data` to persist.
    ///   - forKey: The unique identifier key in the Keychain.
    public var set: @Sendable (_ data: Data, _ forKey: String) -> Void
    
    /// Deletes the data from the Keychain for a given key.
    ///
    /// - Parameter key: The unique identifier key to delete.
    public var delete: @Sendable (_ key: String) -> Void = { _ in }
}

private enum KeychainStorageLocals {
    @TaskLocal static var isSetting: Bool = false
}

extension KeychainStorage: DependencyKey {
    /// The live implementation of `KeychainStorage` backed by `KeychainSwift`.
    public static var liveValue: KeychainStorage {
        let keychain = KeychainSwift()
        let id = UUID()
        return .init(
            storageID: id,
            getData: { key in
                keychain.getData(key)
            }, set: { data, key in
                guard !KeychainStorageLocals.isSetting else { return }
                KeychainStorageLocals.$isSetting.withValue(true) {
                    keychain.set(data, forKey: key)
                    NotificationCenter.default.post(
                        name: .keychainDidChange,
                        object: id,
                        userInfo: ["key": key]
                    )
                }
            }, delete: { key in
                guard !KeychainStorageLocals.isSetting else { return }
                KeychainStorageLocals.$isSetting.withValue(true) {
                    keychain.delete(key)
                    NotificationCenter.default.post(
                        name: .keychainDidChange,
                        object: id,
                        userInfo: ["key": key]
                    )
                }
            }
        )
    }
    
    /// The preview implementation of `KeychainStorage` backed by an in-memory dictionary.
    ///
    /// Useful for Xcode Previews and unit tests, avoiding touching the system Keychain.
    public static var previewValue: KeychainStorage {
        .inMemory()
    }
    
    /// The test implementation of `KeychainStorage` backed by an in-memory dictionary.
    public static var testValue: KeychainStorage {
        .previewValue
    }
    
    /// Creates an in-memory `KeychainStorage` backed by a thread-safe isolated dictionary.
    public static func inMemory(
        _ storage: LockIsolated<[String: Data]> = LockIsolated([:]),
        id: UUID = UUID()
    ) -> KeychainStorage {
        .init(
            storageID: id,
            getData: { key in
                storage.value[key]
            }, set: { data, key in
                storage.withValue { $0[key] = data }
                NotificationCenter.default.post(
                    name: .keychainDidChange,
                    object: id,
                    userInfo: ["key": key]
                )
            }, delete: { key in
                storage.withValue { _ = $0.removeValue(forKey: key) }
                NotificationCenter.default.post(
                    name: .keychainDidChange,
                    object: id,
                    userInfo: ["key": key]
                )
            }
        )
    }
}

extension DependencyValues {
    /// Accesses the `KeychainStorage` dependency.
    ///
    /// Use this property to inject the Keychain client into features.
    ///
    /// ```swift
    /// struct AuthenticationClient {
    ///     @Dependency(\.defaultKeychainStorage) var keychain
    /// }
    /// ```
    public var defaultKeychainStorage: KeychainStorage {
        get { self[KeychainStorage.self] }
        set { self[KeychainStorage.self] = newValue }
    }
}

extension KeychainStorage {
    /// Decodes and returns a `Decodable` value from the Keychain for the specified key.
    ///
    /// This method uses the `defaultKeychainJSONDecoder` dependency to decode the stored data.
    ///
    /// - Parameter key: The key associated with the stored value.
    /// - Returns: The decoded value if present in the Keychain, or `nil` if no data was found.
    /// - Throws: An error if decoding fails.
    public func value<Value: Decodable>(for key: String) throws -> Value? {
        @Dependency(\.defaultKeychainStorage) var keychain
        guard let data = keychain.getData(key: key) else { return nil }
        @Dependency(\.defaultKeychainJSONDecoder) var decoder
        return try decoder.decode(Value.self, from: data)
    }
    
    /// Encodes and persists an `Encodable` value to the Keychain for the specified key.
    ///
    /// This method uses the `defaultKeychainJSONEncoder` dependency to encode the value before storing.
    ///
    /// - Parameters:
    ///   - value: The value to persist in Keychain.
    ///   - key: The key under which the value should be stored.
    /// - Throws: An error if encoding fails.
    public func setValue<Value: Encodable>(_ value: Value?, for key: String) throws {
        @Dependency(\.defaultKeychainStorage) var keychain
        if let value {
            @Dependency(\.defaultKeychainJSONEncoder) var encoder
            let data = try encoder.encode(value)
            keychain.set(data: data, forKey: key)
            NotificationCenter.default.post(
                name: .keychainDidChange,
                object: keychain.storageID,
                userInfo: ["key": key]
            )
        } else {
            keychain.delete(key: key)
            NotificationCenter.default.post(
                name: .keychainDidChange,
                object: keychain.storageID,
                userInfo: ["key": key]
            )
        }
    }
}
