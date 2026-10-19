import SwiftUI

struct ContentView: View {
    @State private var tab: AppTab = .today

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max", value: .today) { TodayView() }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: .progress) { ProgressTabView() }
            Tab("Nutrition", systemImage: "fork.knife", value: .nutrition) { NutritionView() }
            Tab("Settings", systemImage: "gearshape", value: .settings) { SettingsView() }
        }
        .environment(\.switchTab) { tab = $0 }
    }
}
