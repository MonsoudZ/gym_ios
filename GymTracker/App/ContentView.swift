import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var tab: AppTab = .today
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [UserSettings]
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    private var needsOnboarding: Binding<Bool> {
        Binding(get: { settingsList.first.map { !$0.hasCompletedOnboarding } ?? false }, set: { _ in })
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max", value: .today) { TodayView() }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: .progress) { ProgressTabView() }
            Tab("Nutrition", systemImage: "fork.knife", value: .nutrition) { NutritionView() }
            Tab("Settings", systemImage: "gearshape", value: .settings) { SettingsView() }
        }
        .environment(\.switchTab) { tab = $0 }
        // Re-plans the morning reminders each time the app opens, so today's drops out once logged.
        .task(id: scenePhase) {
            if scenePhase == .active { LogReminders.refresh(context: context) }
        }
        .sheet(isPresented: needsOnboarding) {
            if let settings = settingsList.first {
                OnboardingView(settings: settings, programs: programs, exercises: exercises)
            }
        }
    }
}
