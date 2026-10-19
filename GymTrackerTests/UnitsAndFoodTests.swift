import XCTest
@testable import GymTracker

final class UnitsAndFoodTests: XCTestCase {
    func testFeetAndInchesRoundTrip() {
        let cm = Units.cm(feet: 5, inches: 10)
        XCTAssertEqual(cm, 177.8, accuracy: 0.001)
        let back = Units.feetAndInches(fromCm: cm)
        XCTAssertEqual(back.feet, 5)
        XCTAssertEqual(back.inches, 10)
    }

    func testPoundIncrementsMapToPlateSteps() {
        XCTAssertEqual(Units.lb(fromKg: ExerciseLibrary.increment(forKg: 2.5, metric: false)), 5, accuracy: 0.0001)
        XCTAssertEqual(Units.lb(fromKg: ExerciseLibrary.increment(forKg: 5, metric: false)), 10, accuracy: 0.0001)
        XCTAssertEqual(Units.lb(fromKg: ExerciseLibrary.increment(forKg: 1.25, metric: false)), 2.5, accuracy: 0.0001)
        XCTAssertEqual(Units.lb(fromKg: ExerciseLibrary.increment(forKg: 10, metric: false)), 20, accuracy: 0.0001)
        XCTAssertEqual(ExerciseLibrary.increment(forKg: 2.5, metric: true), 2.5)
    }

    func testPrescriptionsRoundToWholePoundsWithPoundIncrements() {
        let inc = ExerciseLibrary.increment(forKg: 2.5, metric: false)   // 5 lb
        let config = ExerciseConfig(repRangeLow: 6, repRangeHigh: 8, increment: inc, setCount: 3)
        let last = SessionResult(date: .now, sets: [LoggedSet(weight: Units.kg(fromLb: 155), reps: 8, rpe: 8)])
        let p = ProgressionEngine.prescription(history: [last], config: config, formatWeight: { Units.weight($0, metric: false) })
        XCTAssertEqual(Units.lb(fromKg: p.weight), 160, accuracy: 0.0001)
        XCTAssertTrue(p.reason.contains("Add 5 lb"), p.reason)
    }

    func testDeloadRoundsToPoundPlates() {
        let inc = ExerciseLibrary.increment(forKg: 2.5, metric: false)
        let config = ExerciseConfig(repRangeLow: 6, repRangeHigh: 8, increment: inc, setCount: 3)
        let held = (1...3).map { i in
            SessionResult(date: Date().addingTimeInterval(Double(-i) * 86400), sets: [LoggedSet(weight: Units.kg(fromLb: 185), reps: 7, rpe: 9)])
        }.reversed()
        let p = ProgressionEngine.prescription(history: Array(held), config: config)
        XCTAssertEqual(p.stallAction, .deload)
        XCTAssertEqual(Units.lb(fromKg: p.weight), 165, accuracy: 0.0001)   // 185 × 0.9 = 166.5 → 165
    }

    func testFoodDraftScalesPer100g() {
        let oats = FoodDraft(name: "Oats", kcalPer100g: 389, proteinPer100g: 16.9, carbsPer100g: 66.3, fatPer100g: 6.9, fibrePer100g: 10.6)
        let m = oats.macros(forGrams: 40)
        XCTAssertEqual(m.kcal, 155.6, accuracy: 0.001)
        XCTAssertEqual(m.protein, 6.76, accuracy: 0.001)
    }

    func testOpenFoodFactsProductParsing() throws {
        let json = """
        {"status":1,"product":{"code":"0012345678905","product_name":"Rolled Oats","brands":"Quaker, PepsiCo",
          "serving_quantity":"40","serving_size":"40 g",
          "nutriments":{"energy-kcal_100g":389,"proteins_100g":"16.9","carbohydrates_100g":66.3,"fat_100g":6.9,"fiber_100g":10.6}}}
        """
        let response = try JSONDecoder().decode(OpenFoodFactsClient.ProductResponse.self, from: Data(json.utf8))
        let draft = try XCTUnwrap(response.product?.draft)
        XCTAssertEqual(draft.name, "Rolled Oats")
        XCTAssertEqual(draft.brand, "Quaker")
        XCTAssertEqual(draft.barcode, "0012345678905")
        XCTAssertEqual(draft.kcalPer100g, 389)
        XCTAssertEqual(draft.proteinPer100g, 16.9)
        XCTAssertEqual(draft.servingGrams, 40)
    }

    func testProductWithoutEnergyIsDropped() throws {
        let json = """
        {"hits":[{"code":"1","product_name":"Mystery","nutriments":{}},{"code":"2","product_name":"","nutriments":{"energy-kcal_100g":10}}]}
        """
        let response = try JSONDecoder().decode(OpenFoodFactsClient.SearchResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.hits.compactMap(\.draft).isEmpty)
    }

    func testSearchHitWithBrandArray() throws {
        let json = """
        {"hits":[{"code":"3","product_name":"Nonfat Greek Yogurt","brands":["Chobani"],"nutriments":{"energy-kcal_100g":52.9,"proteins_100g":10}}]}
        """
        let response = try JSONDecoder().decode(OpenFoodFactsClient.SearchResponse.self, from: Data(json.utf8))
        let draft = try XCTUnwrap(response.hits.first?.draft)
        XCTAssertEqual(draft.brand, "Chobani")
        XCTAssertEqual(draft.proteinPer100g, 10)
    }

    func testKilojoulesFallback() throws {
        let json = """
        {"status":1,"product":{"product_name":"Bread","nutriments":{"energy_100g":1046}}}
        """
        let response = try JSONDecoder().decode(OpenFoodFactsClient.ProductResponse.self, from: Data(json.utf8))
        XCTAssertEqual(try XCTUnwrap(response.product?.draft).kcalPer100g, 250, accuracy: 0.1)
    }
}
