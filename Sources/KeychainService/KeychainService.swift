//
//  KeychainService.swift
//  swift-keychain-service
//
//  Created by Ratnesh Jain on 14/09/26.
//

import Dependencies
import DependenciesMacros
import Foundation
@preconcurrency import KeychainSwift
import Synchronization

extension DependencyValues {
    /// The default JSON decoder used for decoding Keychain values.
    ///
    /// Override this dependency to customize date decoding strategies, key decoding strategies,
    /// or other JSON decoding configurations when reading Codable values from Keychain.
    ///
    /// ```swift
    /// withDependencies {
    ///     $0.defaultKeychainJSONDecoder = {
    ///         let decoder = JSONDecoder()
    ///         decoder.dateDecodingStrategy = .iso8601
    ///         return decoder
    ///     }()
    /// } operation: {
    ///     // Decodes values with custom configuration
    /// }
    /// ```
    @DependencyEntry(
        liveValue: JSONDecoder(),
        previewValue: JSONDecoder()
    )
    public var defaultKeychainJSONDecoder: JSONDecoder
    
    /// The default JSON encoder used for encoding Keychain values.
    ///
    /// Override this dependency to customize date encoding strategies, key encoding strategies,
    /// or other JSON encoding configurations when persisting Codable values to Keychain.
    ///
    /// ```swift
    /// withDepCanendencies {
    ///     $0.defaultKeychainJSONEncoder = {
    ///         let encoder = JSONEncoder()
    ///         encoder.dateEncodingStrategy = .iso8601
    ///         return encoder
    ///     }()
    /// } operation: {
    ///     // Encodes values with custom configuration
    /// }
    /// ```
    @DependencyEntry(
        liveValue: JSONEncoder(),
        previewValue: JSONEncoder()
    )
    public var defaultKeychainJSONEncoder: JSONEncoder
}

/// A client interface for low-level Keychain data storage and retrieval.
///
/// `KeychainStorage` conforms to `DependencyClient` and `DependencyKey`, allowing it to be injected
/// into features via Point-Free's `swift-dependencies` library.
///
/// ### Overview
/// `KeychainStorage` abstracts reading and writing raw `Data` to and from the Keychain. In production (`liveValue`),
/// it delegates to `KeychainSwift`. In previews and tests (`previewValue`), it uses an in-memory thread-safe `Mutex` dictionary,
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
/// // Storing and retrieving Codable values
/// try keychain.setValue(userSession, for: "session")
/// let session: UserSession? = try keychain.value(for: "session")
/// ```
@DependencyClient
public struct KeychainStorage: Sendable {
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
}

private enum KeychainStorageLocals {
    @TaskLocal static var isSetting: Bool = false
}

extension KeychainStorage: DependencyKey {
    /// The live implementation of `KeychainStorage` backed by `KeychainSwift`.
    public static var liveValue: KeychainStorage {
        let keychain = KeychainSwift()
        return .init { key in
            return keychain.getData(key)
        } set: { data, key in
            guard !KeychainStorageLocals.isSetting else { return }
            KeychainStorageLocals.$isSetting.withValue(true) {
                keychain.set(data, forKey: key)
            }
        }
    }
    
    /// The preview implementation of `KeychainStorage` backed by an in-memory dictionary.
    ///
    /// Useful for Xcode Previews and unit tests, avoiding touching the system Keychain.
    public static var previewValue: KeychainStorage {
        let storage = Mutex<Dictionary<String, Data>>([:])
        return .init { key in
            storage.withLock { $0[key] }
        } set: { data, key in
            storage.withLock { $0[key] = data }
        }
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
    ///   - value: The value to persist in the Keychain.
    ///   - key: The key under which the value should be stored.
    /// - Throws: An error if encoding fails.
    public func setValue<Value: Encodable>(_ value: Value, for key: String) throws {
        @Dependency(\.defaultKeychainJSONEncoder) var encoder
        let data = try encoder.encode(value)
        @Dependency(\.defaultKeychainStorage) var keychain
        keychain.set(data: data, forKey: key)
    }
}
