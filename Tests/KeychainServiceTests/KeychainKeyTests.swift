//
//  KeychainKeyTests.swift
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
import Sharing
import Testing

private func waitUntil(
    _ condition: () -> Bool,
    timeout: Duration = .seconds(1),
    interval: Duration = .milliseconds(10)
) async {
    let start = ContinuousClock.now
    while !condition() {
        guard start.duration(to: .now) < timeout else { return }
        try? await Task.sleep(for: interval)
    }
}

struct TestSession: Codable, Equatable, Sendable {
    var id: UUID
    var user: String
    var roles: [String]
    var isActive: Bool
}

@Suite struct KeychainKeyTests {
    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([
                "token": try! JSONEncoder().encode("initial_secret")
            ])
        )
    })
    func initialLoadWithExistingData() {
        @Shared(.keychain("token")) var token: String? = nil
        expectNoDifference(token, "initial_secret")
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([
                "token": try! JSONEncoder().encode("initial_secret")
            ])
        )
    })
    func nonOptionalInitialLoadWithExistingData() {
        @Shared(.keychain("token")) var token: String = "fallback"
        expectNoDifference(token, "initial_secret")
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func initialLoadWithDefaultValue() {
        @Shared(.keychain("token")) var token: String? = "default_token"
        expectNoDifference(token, "default_token")
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func nonOptionalInitialLoadWithDefaultValue() {
        @Shared(.keychain("token")) var token: String = "default_token"
        expectNoDifference(token, "default_token")
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func sharedMutationPersistsToStorage() throws {
        @Shared(.keychain("auth_key")) var authKey: String? = "initial"
        expectNoDifference(authKey, "initial")

        expectDifference(authKey) {
            $authKey.withLock { $0 = "updated_auth_key" }
        } changes: {
            $0 = "updated_auth_key"
        }

        @Dependency(\.defaultKeychainStorage) var keychain
        let savedValue: String? = try keychain.value(for: "auth_key")
        expectNoDifference(savedValue, "updated_auth_key")
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func nonOptionalMutationPersistsToStorage() throws {
        @Shared(.keychain("counter")) var counter: Int = 0
        expectNoDifference(counter, 0)

        expectDifference(counter) {
            $counter.withLock { $0 = 42 }
        } changes: {
            $0 = 42
        }

        @Dependency(\.defaultKeychainStorage) var keychain
        let savedValue: Int? = try keychain.value(for: "counter")
        expectNoDifference(savedValue, 42)
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func twoSharedsSynchronization() async {
        @Shared(.keychain("sync_token")) var token1: String? = "token_v1"
        @Shared(.keychain("sync_token")) var token2: String? = "token_v1"

        expectNoDifference(token1, "token_v1")
        expectNoDifference(token2, "token_v1")

        $token1.withLock { $0 = "token_v2" }
        await waitUntil { token2 == "token_v2" }
        expectNoDifference(token2, "token_v2")

        $token2.withLock { $0 = "token_v3" }
        await waitUntil { token1 == "token_v3" }
        expectNoDifference(token1, "token_v3")
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func nonOptionalTwoSharedsSynchronization() async {
        @Shared(.keychain("sync_counter")) var count1: Int = 1
        @Shared(.keychain("sync_counter")) var count2: Int = 1

        expectNoDifference(count1, 1)
        expectNoDifference(count2, 1)

        $count1.withLock { $0 = 2 }
        await waitUntil { count2 == 2 }
        expectNoDifference(count2, 2)

        $count2.withLock { $0 = 3 }
        await waitUntil { count1 == 3 }
        expectNoDifference(count1, 3)
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func optionalPropertyPersistenceAndClearing() throws {
        @Shared(.keychain("optional_key")) var optionalValue: String? = "exists"
        expectNoDifference(optionalValue, "exists")

        @Dependency(\.defaultKeychainStorage) var keychain
        let saved: String? = try keychain.value(for: "optional_key")
        expectNoDifference(saved, "exists")

        expectDifference(optionalValue) {
            $optionalValue.withLock { $0 = nil }
        } changes: {
            $0 = nil
        }
        #expect(optionalValue == nil)

        let cleared: String? = try keychain.value(for: "optional_key")
        #expect(cleared == nil)

        expectDifference(optionalValue) {
            $optionalValue.withLock { $0 = "recreated" }
        } changes: {
            $0 = "recreated"
        }
        expectNoDifference(optionalValue, "recreated")

        let recreated: String? = try keychain.value(for: "optional_key")
        expectNoDifference(recreated, "recreated")
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func complexModelPersistence() throws {
        let initialSession = TestSession(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            user: "johnappleseed",
            roles: ["admin", "developer"],
            isActive: true
        )
        @Shared(.keychain("user_session")) var session: TestSession? = initialSession
        expectNoDifference(session, initialSession)

        let updatedSession = TestSession(
            id: initialSession.id,
            user: "johnappleseed",
            roles: ["admin", "developer", "tester"],
            isActive: false
        )

        expectDifference(session) {
            $session.withLock { $0 = updatedSession }
        } changes: {
            $0?.roles = ["admin", "developer", "tester"]
            $0?.isActive = false
        }
        expectNoDifference(session, updatedSession)

        @Dependency(\.defaultKeychainStorage) var keychain
        let storedSession: TestSession? = try keychain.value(for: "user_session")
        expectNoDifference(storedSession, updatedSession)
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func nonOptionalComplexModelPersistence() throws {
        let initialSession = TestSession(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            user: "johnappleseed",
            roles: ["admin", "developer"],
            isActive: true
        )
        @Shared(.keychain("user_session_non_opt")) var session: TestSession = initialSession
        expectNoDifference(session, initialSession)

        let updatedSession = TestSession(
            id: initialSession.id,
            user: "johnappleseed",
            roles: ["admin", "developer", "tester"],
            isActive: false
        )

        expectDifference(session) {
            $session.withLock { $0 = updatedSession }
        } changes: {
            $0.roles = ["admin", "developer", "tester"]
            $0.isActive = false
        }
        expectNoDifference(session, updatedSession)

        @Dependency(\.defaultKeychainStorage) var keychain
        let storedSession: TestSession? = try keychain.value(for: "user_session_non_opt")
        expectNoDifference(storedSession, updatedSession)
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([
                "bad_key": Data("corrupted data".utf8)
            ])
        )
    })
    func decodingFailureYieldsLoadError() {
        @Shared(.keychain("bad_key")) var value: [String]? = []
        #expect($value.loadError != nil)
        #expect($value.loadError is DecodingError)
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated<[String: Data]>([:])
        )
    })
    func subscriptionYieldsOnExternalNotification() async throws {
        let key: KeychainKey<String> = .keychain("external_key")
        let receivedValues = LockIsolated<[String]>([])

        let subscription = key.subscribe(
            context: .userInitiated,
            subscriber: SharedSubscriber { result in
                if let value = try? result.get() {
                    receivedValues.withValue { $0.append(value) }
                }
            }
        )
        defer { subscription.cancel() }

        @Dependency(\.defaultKeychainStorage) var keychain
        try keychain.setValue("external_value_1", for: "external_key")
        NotificationCenter.default.post(
            name: .keychainDidChange,
            object: keychain.storageID,
            userInfo: ["key": "external_key"]
        )

        await waitUntil { receivedValues.value.contains("external_value_1") }
        expectNoDifference(receivedValues.value, ["external_value_1"])
    }
}
