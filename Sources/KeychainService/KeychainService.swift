//
//  File.swift
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
    @DependencyEntry(
        liveValue: JSONDecoder(),
        previewValue: JSONDecoder()
    )
    public var defaultKeychainJSONDecoder: JSONDecoder
    
    @DependencyEntry(
        liveValue: JSONEncoder(),
        previewValue: JSONEncoder()
    )
    public var defaultKeychainJSONEncoder: JSONEncoder
}

@DependencyClient
public struct KeychainStorage: Sendable {
    public var getData: @Sendable (_ key: String) -> Data? = { _ in Data() }
    public var set: @Sendable (_ data: Data, _ forKey: String) -> Void
}

private enum KeychainStorageLocals {
    @TaskLocal static var isSetting: Bool = false
}

extension KeychainStorage: DependencyKey {
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
    public var defaultKeychainStorage: KeychainStorage {
        get { self[KeychainStorage.self] }
        set { self[KeychainStorage.self] = newValue }
    }
}

extension KeychainStorage {
    public func value<Value: Decodable>(for key: String) throws -> Value? {
        @Dependency(\.defaultKeychainStorage) var keychain
        guard let data = keychain.getData(key: key) else { return nil }
        @Dependency(\.defaultKeychainJSONDecoder) var decoder
        return try decoder.decode(Value.self, from: data)
    }
    
    public func setValue<Value: Encodable>(_ value: Value, for key: String) throws {
        @Dependency(\.defaultKeychainJSONEncoder) var encoder
        let data = try encoder.encode(value)
        @Dependency(\.defaultKeychainStorage) var keychain
        keychain.set(data: data, forKey: key)
    }
}
