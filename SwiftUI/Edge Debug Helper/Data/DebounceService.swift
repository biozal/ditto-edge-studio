//
//  DebounceService.swift
//  Edge Studio
//
//  Provides debouncing functionality to reduce frequent updates
//  and improve performance on slower computers.
//

import Foundation

/// A service that debounces function calls to reduce frequency of execution
@MainActor
class DebounceService {
    private var workItem: Task<Void, Never>?
    private let delay: TimeInterval

    /// Initialize a debounce service with a specific delay
    /// - Parameter delay: Time interval in seconds to wait before executing the action
    init(delay: TimeInterval = 0.2) {
        self.delay = delay
    }

    /// Debounces the provided action
    /// - Parameter action: The action to execute after the debounce delay
    /// - Note: If called again before the delay expires, the previous action is cancelled
    func debounce(_ action: @escaping () -> Void) {
        // Cancel any pending work
        workItem?.cancel()

        // Create new work item with delay
        workItem = Task {
            // Wait for the delay period
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            // Check if task was cancelled during sleep
            if !Task.isCancelled {
                action()
            }
        }
    }

    /// Cancels any pending debounced action
    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
