import XCTest
@testable import GymTracker

/// The bundled foods are typed by hand: these catch a slipped digit.
final class GenericFoodsTests: XCTestCase {
    func testNamesAreUniqueAndEveryFoodHasEnergy() {
        let names = GenericFoods.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "duplicate name")
        XCTAssertGreaterThan(names.count, 240)
        for food in GenericFoods.all {
            XCTAssertGreaterThan(food.kcalPer100g, 0, food.name)
            XCTAssertTrue(food.brand.isEmpty, food.name)
            if let cup = food.gramsPerCup { XCTAssertTrue((8...350).contains(cup), "\(food.name): \(cup) g per cup") }
            if let piece = food.pieceGrams {
                XCTAssertGreaterThan(piece, 0, food.name)
                XCTAssertNotNil(food.pieceName, "\(food.name) has a piece weight but no name")
            }
        }
    }

    func testMacroEnergyAgreesWithCalories() {
        // 4/4/9 kcal per gram should land within 25% of the listed energy. Alcohol and fibre
        // make drinks and very fibrous foods the exceptions.
        let exceptions: Set<String> = ["Beer, regular", "Wine, red", "Coffee, black", "Light beer", "Wine, white", "Vodka, whisky, rum"]
        for food in GenericFoods.all where !exceptions.contains(food.name) {
            let fromMacros = 4 * food.proteinPer100g + 4 * food.carbsPer100g + 9 * food.fatPer100g
            let tolerance = max(25, food.kcalPer100g * 0.25)
            XCTAssertEqual(fromMacros, food.kcalPer100g, accuracy: tolerance, food.name)
        }
    }

    func testSearchMatchesEveryWordAndRanksNameStartsFirst() {
        let oats = GenericFoods.search("oats")
        XCTAssertEqual(oats.first?.name, "Oats, rolled, dry")
        XCTAssertTrue(GenericFoods.search("milk 2").contains { $0.name == "Milk, 2%" })
        XCTAssertTrue(GenericFoods.search("cooked chicken").contains { $0.name == "Chicken breast, cooked" })
        XCTAssertTrue(GenericFoods.search("").isEmpty)
        XCTAssertTrue(GenericFoods.search("zzz").isEmpty)
        XCTAssertLessThanOrEqual(GenericFoods.search("e").count, 12)
    }
}
