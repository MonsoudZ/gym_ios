import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") { TodayView() }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") { ProgressTabView() }
            Tab("Nutrition", systemImage: "fork.knife") { NutritionView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
    }
}
