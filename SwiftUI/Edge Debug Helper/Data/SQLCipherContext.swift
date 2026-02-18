//
//  SQLCipherContext.swift
//  Edge Debug Helper
//
//  Created by Claude Code on 2026-02-18.
//  Copyright © 2026 Ditto. All rights reserved.
//

import Foundation

/// Routes access to SQLCipherService through a per-Swift-task context.
///
/// Production code always uses `SQLCipherService.shared` (the default value).
///
/// In tests, each concurrent test task injects its own isolated instance:
/// ```swift
/// let testService = SQLCipherService(testPath: "ditto_test_\(UUID().uuidString)")
/// try await testService.initialize()
/// try await SQLCipherContext.$current.withValue(testService) {
///     // All code in this closure — including repositories — uses testService
///     try await body()
/// }
/// ```
///
/// Because `@TaskLocal` propagates to child tasks but NOT to sibling tasks,
/// concurrent test suites each see their own isolated service instance with
/// no shared filesystem state.
enum SQLCipherContext {
    @TaskLocal static var current: SQLCipherService = .shared
}
