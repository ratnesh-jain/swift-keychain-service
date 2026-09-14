//
//  KeychainKey.swift
//  swift-keychain-service
//
//  Created by Ratnesh Jain on 14/09/26.
//

import Dependencies
import Foundation
import Sharing

public struct KeychainKey<Value: Codable & Sendable>: SharedKey {
    let key: String
    
    public init(key: String) {
        self.key = key
    }
    
    public var id: some Hashable { self.key }
    
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
