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
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("Could not create model container: \(error)")
        }
        Seeder.prepare(context: container.mainContext)
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
}
