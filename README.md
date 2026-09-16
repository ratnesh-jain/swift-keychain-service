# swift-keychain-service

A modern, type-safe Swift library that integrates [`KeychainSwift`](https://github.com/evgenyneu/keychain-swift) with Point-Free's [`swift-dependencies`](https://github.com/pointfreeco/swift-dependencies) and [`swift-sharing`](https://github.com/pointfreeco/swift-sharing) frameworks.

Persist sensitive credentials, authentication tokens, and `Codable` models securely in the Apple Keychain with property wrappers or dependency injection—complete with automatic observation, thread-safe testing/previews, and customizable JSON serialization.

---

## Features

- **Point-Free Sharing Support**: Use `@Shared(.keychain("key"))` to bind and observe Keychain values seamlessly across views, models, and reducers.
- **Optional & Non-Optional Support**: Persist optional values (`UserSession?`) or non-optional values with default values (`Bool = false`, `Int = 0`).
- **Point-Free Dependencies Support**: Injectable `@Dependency(\.defaultKeychainStorage)` client conforming to `@DependencyClient`.
- **Codable & Type-Safe**: Read, write, and delete any `Codable & Sendable` value directly to and from Keychain.
- **Deletion & Nil-Handling**: Setting optional values to `nil` or calling `keychain.delete(...)` automatically removes entries from Keychain and notifies observers.
- **Preview & Test-Safe**: Automatic in-memory thread-safe fallback (`LockIsolated`-backed) for SwiftUI previews and unit tests—never pollutes or fails against the host Keychain in non-host environments.
- **Customizable Serialization**: Override `defaultKeychainJSONDecoder` and `defaultKeychainJSONEncoder` (powered by `@DependencyEntry`) to handle custom date formats, key formatting strategies, and more.
- **Per-Key Customization**: Pass custom `KeychainStorage`, `JSONDecoder`, or `JSONEncoder` directly to `.keychain(...)` or override global defaults via dependencies.
- **Lifecycle & Targeted Change Observation**: Automatically synchronizes when the application enters the foreground or when `.keychainDidChange` notifications are broadcast (targeted by storage ID and key).

---

## Requirements

- **Swift**: 6.0+
- **iOS**: 18.0+
- **macOS**: 15.0+

---

## Installation

Add `swift-keychain-service` to your `Package.swift` manifest:

```swift
dependencies: [
    .package(url: "https://github.com/ratnesh-jain/swift-keychain-service", from: "0.0.1")
]
```

Then add the product to your target:

```swift
.target(
    name: "MyFeature",
    dependencies: [
        .product(name: "KeychainService", package: "swift-keychain-service")
    ]
)
```

---

## Usage

### 1. Using `@Shared` with Point-Free Sharing

Use `@Shared(.keychain("key"))` to bind state directly to Keychain storage. Both optional and non-optional values with defaults are supported:

```swift
import KeychainService
import Sharing
import SwiftUI

@Observable
final class AuthenticationModel {
    @ObservationIgnored
    @Shared(.keychain("user_auth_token")) var authToken: String?

    @ObservationIgnored
    @Shared(.keychain("user_session")) var session: UserSession?

    @ObservationIgnored
    @Shared(.keychain("is_logged_in")) var isLoggedIn: Bool = false

    func logOut() {
        $authToken.withLock { $0 = nil }
        $session.withLock { $0 = nil }
        $isLoggedIn.withLock { $0 = false }
    }
}
```

#### Custom Storage or Encoders per Key

You can optionally pass custom storage instances, decoders, or encoders directly to `.keychain`:

```swift
@Shared(
    .keychain(
        "custom_token",
        storage: customKeychainStorage,
        decoder: customJSONDecoder,
        encoder: customJSONEncoder
    )
)
var customToken: String?
```

### 2. Using `@Dependency` with Point-Free Dependencies

Access the Keychain directly in your services or domain logic using `@Dependency(\.defaultKeychainStorage)`:

```swift
import Dependencies
import KeychainService

struct AuthService {
    @Dependency(\.defaultKeychainStorage) var keychain

    func saveToken(_ token: String) throws {
        try keychain.setValue(token, for: "auth_token")
    }

    func loadToken() throws -> String? {
        try keychain.value(for: "auth_token")
    }

    func deleteToken() {
        keychain.delete("auth_token")
    }

    // Working with raw Data
    func saveRawData(_ data: Data) {
        keychain.set(data, "raw_credentials")
    }

    func loadRawData() -> Data? {
        keychain.getData("raw_credentials")
    }
}
```

### 3. Storing Custom `Codable` Types

Any type conforming to `Codable & Sendable` can be stored and retrieved directly:

```swift
public struct UserSession: Codable, Sendable, Equatable {
    public let userId: String
    public let email: String
    public let roles: [String]
    public let expiresAt: Date
}

// Persisting via @Shared
@Shared(.keychain("session_info")) var session: UserSession?

// Persisting / Retrieving via KeychainStorage
try keychain.setValue(session, for: "session_info")
let loadedSession: UserSession? = try keychain.value(for: "session_info")

// Setting to nil removes the entry from the Keychain
try keychain.setValue(nil as UserSession?, for: "session_info")
```

### 4. Customizing JSON Encoders / Decoders

`defaultKeychainJSONDecoder` and `defaultKeychainJSONEncoder` use the `@DependencyEntry` macro from `swift-dependencies` to provide default `JSONDecoder` and `JSONEncoder` instances. You can configure custom date encoding/decoding strategies and formatting by overriding them:

```swift
withDependencies {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    $0.defaultKeychainJSONDecoder = decoder

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    $0.defaultKeychainJSONEncoder = encoder
} operation: {
    // Operations using KeychainService will use the configured encoders/decoders
}
```

### 5. Testing & Xcode Previews

In previews and unit tests, `KeychainStorage.previewValue` and `KeychainStorage.testValue` are automatically active, backed by an isolated, in-memory thread-safe storage (`LockIsolated`).

You can easily configure isolated in-memory test states using Swift Testing:

```swift
import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import KeychainService
import Sharing
import Testing

@Suite struct AuthenticationTests {
    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(
            LockIsolated([
                "user_auth_token": try! JSONEncoder().encode("mock_jwt_token")
            ])
        )
    })
    func testAuthLoading() throws {
        @Dependency(\.defaultKeychainStorage) var keychain
        let token: String? = try keychain.value(for: "user_auth_token")
        #expect(token == "mock_jwt_token")
    }

    @Test(.dependencies {
        $0.defaultKeychainStorage = .inMemory(LockIsolated([:]))
    })
    func testSharedKeychainMutation() {
        @Shared(.keychain("is_logged_in")) var isLoggedIn = false
        #expect(!isLoggedIn)

        $isLoggedIn.withLock { $0 = true }
        #expect(isLoggedIn)

        @Dependency(\.defaultKeychainStorage) var keychain
        let stored: Bool? = try? keychain.value(for: "is_logged_in")
        #expect(stored == true)
    }
}
```

---

## Notifications

`KeychainService` automatically observes and broadcasts change events:

- `Notification.Name.keychainDidChange`: Posted whenever values are saved or deleted via `KeychainKey` or `KeychainStorage`. The notification carries the `storageID` as its `object` and `["key": key]` in `userInfo` for targeted filtering.
- `didBecomeActiveNotification` / `willResignActiveNotification`: Subscriptions in `KeychainKey` reload data when application active state transitions.

---

## License

This project is available under the MIT License.
