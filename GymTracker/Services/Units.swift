import Foundation

nonisolated enum Units {
    static let lbPerKg = 2.20462

    static func weight(_ kg: Double, metric: Bool) -> String {
        metric ? "\(number(kg)) kg" : "\(number(kg * lbPerKg)) lb"
    }

    static func number(_ value: Double, maxFraction: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFraction)))
    }

    static func percent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(number(value, maxFraction: 2))%"
    }

    static func rpeLabel(_ rpe: Double) -> String {
        let left = max(0, 10 - rpe)
        let leftText = left == left.rounded() ? "\(Int(left))" : number(left)
        return "RPE \(number(rpe)) · \(leftText) left"
    }
}
