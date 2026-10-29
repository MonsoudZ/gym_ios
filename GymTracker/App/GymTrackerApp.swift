import SwiftUI
import SwiftData

@main
struct GymTrackerApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([
            Exercise.self, WorkoutSession.self, SetEntry.self,
            BodyweightEntry.self, IntakeEntry.self, UserSettings.self, FoodItem.self,
            Program.self, ProgramDay.self, ReadinessEntry.self, AdjustmentEntry.self, SavedMeal.self,
        ])
        // UI tests launch with a throwaway in-memory store holding the demo history, so every
        // run starts from the same screens and nothing the tests do reaches the real data.
        let uiTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: uiTesting)])
        } catch {
            fatalError("Could not create model container: \(error)")
        }
        Seeder.prepare(context: container.mainContext)
        if uiTesting { Self.loadUITestFixture(context: container.mainContext) }
        WidgetBridge.observe(container)
        // A Live Activity left on the lock screen by a workout the app was killed during ends
        // now, not only once a workout screen is next opened.
        Task { await RestActivityController.end() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }

    /// Onboarding done, pounds, no Health, eight weeks of demo data.
    private static func loadUITestFixture(context: ModelContext) {
        guard let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first else { return }
        settings.hasCompletedOnboarding = true
        settings.usesMetric = false
        settings.remindersEnabled = false
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        DemoData.load(context: context, exercises: exercises, settings: settings)
        context.saveOrLog()
    }
}
