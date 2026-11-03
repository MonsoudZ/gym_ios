import XCTest
@testable import GymTracker

/// Household measures: fractions as people type them, and cups, pieces and servings turned
/// into the grams the macros are computed from.
final class PortionTests: XCTestCase {
    private let oats = GenericFoods.all.first { $0.name == "Oats, rolled, dry" }!
    private let milk = GenericFoods.all.first { $0.name == "Milk, 2%" }!
    private let egg = GenericFoods.all.first { $0.name == "Egg, whole, large" }!
    private let chicken = GenericFoods.all.first { $0.name == "Chicken breast, cooked" }!

    func testQuantitiesParseAsTyped() {
        XCTAssertEqual(Portion.parse("1/2"), 0.5)
        XCTAssertEqual(Portion.parse("3/4"), 0.75)
        XCTAssertEqual(Portion.parse("1 1/2"), 1.5)
        XCTAssertEqual(Portion.parse("1½"), 1.5)
        XCTAssertEqual(Portion.parse("½"), 0.5)
        XCTAssertEqual(Portion.parse("0.75"), 0.75)
        XCTAssertEqual(Portion.parse("1,5"), 1.5)
        XCTAssertEqual(Portion.parse(" 2 "), 2)
        XCTAssertNil(Portion.parse(""))
        XCTAssertNil(Portion.parse("abc"))
        XCTAssertNil(Portion.parse("1/0"))
    }

    func testQuantitiesFormatAsFractions() {
        XCTAssertEqual(Portion.format(0.5), "½")
        XCTAssertEqual(Portion.format(0.75), "¾")
        XCTAssertEqual(Portion.format(1.5), "1½")
        XCTAssertEqual(Portion.format(2), "2")
        XCTAssertEqual(Portion.format(1.0 / 3), "⅓")
        XCTAssertEqual(Portion.format(0.6), "0.6")
    }

    func testHouseholdMeasuresBecomeGrams() {
        XCTAssertEqual(Portion(quantity: 0.5, unit: .cup).grams(for: oats)!, 40.5, accuracy: 0.01, "half a cup of dry oats")
        XCTAssertEqual(Portion(quantity: 0.75, unit: .cup).grams(for: milk)!, 183, accuracy: 0.01, "three quarters of a cup of milk")
        XCTAssertEqual(Portion(quantity: 2, unit: .piece).grams(for: egg)!, 100, "two large eggs")
        XCTAssertEqual(Portion(quantity: 1, unit: .tablespoon).grams(for: oats)!, 81 * 15 / 240, accuracy: 0.01)
        XCTAssertEqual(Portion(quantity: 8, unit: .fluidOunce).grams(for: milk)!, 244 * 8 * 29.5735 / 240, accuracy: 0.01)
        XCTAssertEqual(Portion(quantity: 6, unit: .ounce).grams(for: chicken)!, 170.1, accuracy: 0.01)
        XCTAssertEqual(Portion(quantity: 150, unit: .gram).grams(for: chicken), 150)
        XCTAssertNil(Portion(quantity: 1, unit: .cup).grams(for: chicken), "no cup weight: no cups")
        XCTAssertNil(Portion(quantity: 1, unit: .piece).grams(for: oats))
        XCTAssertNil(Portion(quantity: 1, unit: .serving).grams(for: oats), "generic foods carry no label serving")
    }

    func testMacrosFollowTheGrams() {
        let halfCup = Portion(quantity: 0.5, unit: .cup).grams(for: oats)!
        let m = oats.macros(forGrams: halfCup)
        XCTAssertEqual(m.kcal, 153.5, accuracy: 0.1)
        XCTAssertEqual(m.protein, 5.35, accuracy: 0.01)
    }

    func testUnitsOfferedMatchWhatTheFoodCarries() {
        XCTAssertEqual(Portion.units(for: chicken), [.gram, .ounce])
        XCTAssertEqual(Portion.units(for: oats).first, .cup)
        XCTAssertEqual(Portion.units(for: egg).first, .piece)
        var labelled = chicken
        labelled.servingGrams = 112
        XCTAssertEqual(Portion.units(for: labelled).first, .serving)
    }

    func testLabelsReadAsPeopleSayThem() {
        XCTAssertEqual(Portion(quantity: 0.5, unit: .cup).label(for: oats), "½ cup")
        XCTAssertEqual(Portion(quantity: 2, unit: .piece).label(for: egg), "2 large eggs")
        XCTAssertEqual(Portion(quantity: 1, unit: .piece).label(for: egg), "1 large egg")
        XCTAssertEqual(Portion(quantity: 1, unit: .serving).label(for: oats), "1 serving")
        XCTAssertEqual(Portion(quantity: 150, unit: .gram).label(for: chicken), "150 g")
    }
}
