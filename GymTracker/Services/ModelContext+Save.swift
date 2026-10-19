import Foundation
import SwiftData
import os

nonisolated extension ModelContext {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GymTracker", category: "persistence")

    /// Saves, and logs instead of throwing when the save fails. Use where a failed save
    /// has no user-facing recovery; the caller's name is included so the log says where.
    func saveOrLog(caller: String = #function) {
        do {
            try save()
        } catch {
            Self.logger.error("Save failed in \(caller, privacy: .public): \(error, privacy: .public)")
        }
    }
}
