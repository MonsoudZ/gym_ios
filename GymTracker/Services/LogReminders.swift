import Foundation
import SwiftData
import UserNotifications

nonisolated struct PlannedReminder: Equatable, Sendable {
    var date: Date
    var body: String
}

/// A morning nudge to log bodyweight and food, since the expenditure estimate and its
/// confidence depend on both being recorded every day (DESIGN.md §3.2).
///
/// A local notification cannot check at fire time whether something was logged, so the next
/// two weeks of reminders are scheduled up front and re-planned whenever the app opens or
/// something is logged. Today's reminder disappears once both are in. If the app is not opened
/// for the whole horizon the reminders simply run out.
enum LogReminders {
    nonisolated static let identifierPrefix = "log-reminder-"
    nonisolated static let horizonDays = 14
    nonisolated static let defaultMinutes = 10 * 60

    // MARK: Planning (pure)

    nonisolated static func plan(now: Date, minutesAfterMidnight: Int, hasWeightToday: Bool, hasIntakeToday: Bool,
                                 calendar: Calendar = .current) -> [PlannedReminder] {
        let today = calendar.startOfDay(for: now)
        var planned: [PlannedReminder] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(byAdding: .minute, value: minutesAfterMidnight, to: day),
                  fire > now else { continue }
            // Only today's can know what is already logged; later days get the general nudge.
            guard let text = offset == 0 ? message(hasWeight: hasWeightToday, hasIntake: hasIntakeToday)
                                         : message(hasWeight: false, hasIntake: false) else { continue }
            planned.append(PlannedReminder(date: fire, body: text))
        }
        return planned
    }

    /// What is still missing, or nil when both are logged.
    nonisolated private static func message(hasWeight: Bool, hasIntake: Bool) -> String? {
        switch (hasWeight, hasIntake) {
        case (true, true): nil
        case (false, false): "Log this morning's weight and what you eat. Daily entries sharpen your calorie target."
        case (false, true): "Log this morning's weight. Daily weigh-ins sharpen your calorie target."
        case (true, false): "Nothing eaten is logged yet today. Daily intake sharpens your calorie target."
        }
    }

    nonisolated static func identifier(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return identifierPrefix + String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Scheduling

    private struct Inputs: Sendable {
        var enabled: Bool
        var minutes: Int
        var hasWeight: Bool
        var hasIntake: Bool
    }

    /// Re-plans the reminders from what is logged right now. Call after anything is logged or
    /// deleted, when the app becomes active, and when the setting changes.
    static func refresh(context: ModelContext, now: Date = .now) {
        let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let weights = (try? context.fetchCount(FetchDescriptor<BodyweightEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? 0
        let intake = (try? context.fetchCount(FetchDescriptor<IntakeEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? 0
        let inputs = Inputs(enabled: settings?.remindersEnabled ?? false,
                            minutes: settings?.reminderMinutes ?? defaultMinutes,
                            hasWeight: weights > 0, hasIntake: intake > 0)
        Task { await apply(inputs, now: now) }
    }

    private static func apply(_ inputs: Inputs, now: Date) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard inputs.enabled else {
            await removeDelivered(center)
            return
        }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let planned = plan(now: now, minutesAfterMidnight: inputs.minutes,
                           hasWeightToday: inputs.hasWeight, hasIntakeToday: inputs.hasIntake)
        if inputs.hasWeight && inputs.hasIntake { await removeDelivered(center) }
        let calendar = Calendar.current
        for reminder in planned {
            let content = UNMutableNotificationContent()
            content.title = "Log your day"
            content.body = reminder.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier(for: reminder.date), content: content, trigger: trigger))
        }
    }

    private static func removeDelivered(_ center: UNUserNotificationCenter) async {
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    // MARK: Permission

    /// Asks the first time; true when reminders can be delivered.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        return await isAuthorized()
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
}
