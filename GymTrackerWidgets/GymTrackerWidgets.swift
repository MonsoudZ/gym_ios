import SwiftUI
import WidgetKit

@main
struct GymTrackerWidgets: WidgetBundle {
    var body: some Widget {
        TodayLiftWidget()
        CaloriesWidget()
        RestLiveActivity()
    }
}
