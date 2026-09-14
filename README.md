# swift-keychain-service

A modern, type-safe Swift wrapper library that makes using [`KeychainSwift`](https://github.com/evgenyneu/keychain-swift) easier with Point-Free's [`swift-dependencies`](https://github.com/pointfreeco/swift-dependencies) and [`swift-sharing`](https://github.com/pointfreeco/swift-sharing) libraries patterns in isolated, testable and reviewable way.

Persist sensitive credentials, authentication tokens, and custom `Codable` models securely in the Apple Keychain with property wrappers or dependency injection—complete with automatic observation, thread-safe testing/previews, and customizable JSON serialization options.

---

## Features
- **Point-Free Sharing Support**: Use `@Shared(.keychain("key"))` to bind and observe Keychain values seamlessly across views, models, and reducers.
- **Point-Free Dependencies Support**: Injectable `@Dependency(\.defaultKeychainStorage)` client client conforming to `@DependencyClient`.
- **Codable & Type-Safe**: Read and write any `Codable & Sendable` value directly to and from Keychain.
- **Preview & Test-Safe**: Automatic in-memory thread-safe fallback (`Mutex`-backed) for SwiftUI previews and unit tests—never pollutes or fails against host Keychain in non-host environments.
- **Lifecycle & Change Observation**: Automatically reloads when the application enters the foreground or when `.keychainDidChange` notifications are broadcast.
- **Customizable Serialization**: Override `defaultKeychainJSONDecoder` and `defaultKeychainJSONEncoder` to handle custom date formats, key formatting strategies, and more.

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

Use `@Shared(.keychain("key"))` to bind state directly to Keychain storage:

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
    
    func logOut() {
        $authToken.withLock { $0 = nil }
        $session.withLock { $0 = nil }
    }
}
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
    
    func saveRawData(_ data: Data) {
        keychain.set(data, "raw_credentials")
    }
    
    func loadRawData() -> Data? {
        keychain.getData("raw_credentials")
    }
}
```

### 3. Storing Custom `Codable` Types

Any type conforming to `Codable & Sendable` can be stored directly:

```swift
public struct UserSession: Codable, Sendable, Equatable {
    public let userId: String
    public let email: String
    public let expiresAt: Date
}

// Persisting via @Shared
@Shared(.keychain("session_info")) var session: UserSession?

// Or via KeychainStorage
try keychain.setValue(session, for: "session_info")
let loadedSession: UserSession? = try keychain.value(for: "session_info")
```

### 4. Customizing JSON Encoders / Decoders

You can configure custom date encoding/decoding strategies by overriding dependencies:

```swift
withDependencies {
    $0.defaultKeychainJSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    $0.defaultKeychainJSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
} operation: {
    // Operations using KeychainService will use the configured encoders/decoders
}
```

### 5. Testing & Xcode Previews

In previews and unit tests, `KeychainStorage.previewValue` is automatically active, backed by an in-memory `Mutex`-guarded dictionary. You can also mock or seed values using `withDependencies`:

```swift
import Dependencies
import KeychainService
import Testing

@Test
func testAuthFlow() async throws {
    try await withDependencies {
        $0.defaultKeychainStorage.getData = { key in
            if key == "auth_token" {
                return try? JSONEncoder().encode("mock_jwt_token")
            }
            return nil
        }
    } operation: {
        let authService = AuthService()
        let token = try authService.loadToken()
        #expect(token == "mock_jwt_token")
    }
}
```

---

## Notifications

`KeychainService` automatically observes and posts:

- `Notification.Name.keychainDidChange`: Posted whenever values are saved via `KeychainKey` or `KeychainStorage`.
- `didBecomeActiveNotification` / `willResignActiveNotification`: Subscriptions in `KeychainKey` reload data when application state changes.

---

## License
This project is available under the MIT License.
