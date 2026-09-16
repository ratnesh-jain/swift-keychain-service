//
//  KeychainStorageTests.swift
//  swift-keychain-service
//
//  Created by Ratnesh Jain on 14/09/26.
//

import ConcurrencyExtras
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import KeychainService
import Testing

@Suite struct KeychainStorageTests {
    @Test func inMemoryStorageReadWrite() {
        let storage = LockIsolated<[String: Data]>([:])
        let keychainStorage = KeychainStorage.inMemory(storage)

        #expect(keychainStorage.getData("token") == nil)

        let tokenData = Data("secret_token".utf8)
        keychainStorage.set(tokenData, "token")

        expectNoDifference(keychainStorage.getData("token"), tokenData)
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func codableValueEncodingAndDecoding() throws {
        struct UserSession: Codable, Equatable {
            let id: UUID
            let username: String
            let role: String
        }

        @Dependency(\.defaultKeychainStorage) var keychain

        let session = UserSession(
            id: UUID(1),
            username: "alice",
            role: "admin"
        )

        #expect(try keychain.value(for: "user_session") as UserSession? == nil)

        try keychain.setValue(session, for: "user_session")

        let loadedSession: UserSession? = try keychain.value(for: "user_session")
        expectNoDifference(loadedSession, session)
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func settingOptionalValueStoresOrClears() throws {
        struct Credential: Codable, Equatable {
            let value: String
        }

        @Dependency(\.defaultKeychainStorage) var keychain

        let credential: Credential? = Credential(value: "token_123")
        try keychain.setValue(credential, for: "credential")
        let stored: Credential? = try keychain.value(for: "credential")
        expectNoDifference(stored, credential)

        let cleared: Credential? = nil
        try keychain.setValue(cleared, for: "credential")
        let afterClear: Credential? = try keychain.value(for: "credential")
        #expect(afterClear == nil)
    }

    @Test(.dependencies {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
        $0.defaultKeychainJSONEncoder = encoder
        $0.defaultKeychainJSONDecoder = decoder
    })
    func customEncoderAndDecoderStrategies() throws {
        struct TimedToken: Codable, Equatable {
            let token: String
            let expiresAt: Date
        }

        let customDate = Date(timeIntervalSince1970: 1_700_000_000)

        @Dependency(\.defaultKeychainStorage) var keychain

        let item = TimedToken(token: "xyz", expiresAt: customDate)
        try keychain.setValue(item, for: "timed_token")

        let retrieved: TimedToken? = try keychain.value(for: "timed_token")
        expectNoDifference(retrieved, item)
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([
                "item": Data("invalid-json".utf8)
            ])
        )
    })
    func decodingFailureOnCorruptData() throws {
        struct Item: Codable, Equatable {
            let value: String
        }

        @Dependency(\.defaultKeychainStorage) var keychain

        #expect(throws: DecodingError.self) {
            let _: Item? = try keychain.value(for: "item")
        }
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func missingKeyReturnsNil() throws {
        @Dependency(\.defaultKeychainStorage) var keychain
        let result: String? = try keychain.value(for: "non_existent")
        #expect(result == nil)
    }
}