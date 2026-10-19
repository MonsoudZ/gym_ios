import Foundation

nonisolated enum Units {
    static let lbPerKg = 2.20462
    static let cmPerInch = 2.54

    static func kg(fromLb lb: Double) -> Double { lb / lbPerKg }
    static func lb(fromKg kg: Double) -> Double { kg * lbPerKg }

    static func feetAndInches(fromCm cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = Int((cm / cmPerInch).rounded())
        return (totalInches / 12, totalInches % 12)
    }

    static func cm(feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * cmPerInch
    }

    static func height(_ cm: Double, metric: Bool) -> String {
        if metric { return "\(number(cm, maxFraction: 0)) cm" }
        let (ft, inch) = feetAndInches(fromCm: cm)
        return "\(ft)′ \(inch)″"
    }

    /// Display-unit value of a stored kg weight.
    static func display(_ kg: Double, metric: Bool) -> Double { metric ? kg : lb(fromKg: kg) }

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
