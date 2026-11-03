import Foundation

/// Everyday foods that a branded-product database does badly: oats, milk, eggs, chicken, rice.
/// Values are per 100 g from USDA FoodData Central, rounded, with what a cup or a piece weighs
/// so "½ cup of dry oats" or "2 large eggs" is one line to log. They are typical values, not
/// a label: a specific product's label wins when it is scanned.
nonisolated enum GenericFoods {
    /// name, kcal, protein, carbs, fat, fibre per 100 g; grams per cup; piece grams and name.
    private static func f(_ name: String, _ kcal: Double, _ p: Double, _ c: Double, _ fat: Double, _ fibre: Double,
                          cup: Double? = nil, piece: Double? = nil, _ pieceName: String? = nil) -> FoodDraft {
        FoodDraft(name: name, kcalPer100g: kcal, proteinPer100g: p, carbsPer100g: c, fatPer100g: fat, fibrePer100g: fibre,
                  gramsPerCup: cup, pieceGrams: piece, pieceName: pieceName)
    }

    static let all: [FoodDraft] = [
        // Grains and starches
        f("Oats, rolled, dry", 379, 13.2, 67.7, 6.5, 10.1, cup: 81),
        f("Oatmeal, cooked with water", 71, 2.5, 12, 1.5, 1.7, cup: 234),
        f("Rice, white, cooked", 130, 2.7, 28.2, 0.3, 0.4, cup: 158),
        f("Rice, white, dry", 365, 7.1, 80, 0.7, 1.3, cup: 185),
        f("Rice, brown, cooked", 123, 2.7, 25.6, 1, 1.6, cup: 195),
        f("Pasta, cooked", 158, 5.8, 31, 0.9, 1.8, cup: 140),
        f("Pasta, dry", 371, 13, 75, 1.5, 3.2, cup: 100),
        f("Quinoa, cooked", 120, 4.4, 21.3, 1.9, 2.8, cup: 185),
        f("Bread, whole wheat", 247, 13, 41, 3.4, 6, piece: 32, "slice"),
        f("Bread, white", 266, 9, 49, 3.2, 2.7, piece: 25, "slice"),
        f("Bagel, plain", 250, 10, 49, 1.5, 2.1, piece: 105, "bagel"),
        f("Tortilla, flour", 304, 8, 50, 8, 3, piece: 45, "tortilla"),
        f("English muffin", 227, 8.9, 44, 1.7, 2.2, piece: 57, "muffin"),
        f("Potato, baked, with skin", 93, 2.5, 21, 0.1, 2.2, piece: 173, "medium potato"),
        f("Sweet potato, baked", 90, 2, 20.7, 0.2, 3.3, piece: 114, "medium sweet potato"),
        f("Corn flakes", 357, 7.5, 84, 0.4, 3, cup: 28),
        f("Granola", 471, 10, 64, 20, 7, cup: 122),
        f("Pancake, plain", 227, 6.4, 28, 9.7, 1, piece: 38, "pancake"),
        f("Waffle, plain", 291, 7.9, 33, 14, 1.7, piece: 75, "waffle"),
        // Dairy and eggs
        f("Milk, whole", 61, 3.2, 4.8, 3.3, 0, cup: 244),
        f("Milk, 2%", 50, 3.3, 4.8, 2, 0, cup: 244),
        f("Milk, 1%", 42, 3.4, 5, 1, 0, cup: 244),
        f("Milk, skim", 34, 3.4, 5, 0.1, 0, cup: 245),
        f("Almond milk, unsweetened", 15, 0.5, 0.6, 1.1, 0.4, cup: 240),
        f("Oat milk", 47, 1.2, 7, 1.5, 0.8, cup: 240),
        f("Greek yogurt, plain, nonfat", 59, 10.2, 3.6, 0.4, 0, cup: 245),
        f("Greek yogurt, plain, whole milk", 97, 9, 4, 5, 0, cup: 245),
        f("Yogurt, plain, low fat", 63, 5.3, 7, 1.6, 0, cup: 245),
        f("Cottage cheese, 2%", 84, 11, 4.3, 2.3, 0, cup: 226),
        f("Cheddar cheese", 403, 23, 1.3, 33, 0, cup: 113, piece: 28, "slice"),
        f("Mozzarella, part skim", 254, 24, 2.8, 16, 0, cup: 113),
        f("Parmesan, grated", 431, 38, 4, 29, 0, cup: 100),
        f("Cream cheese", 342, 6, 4, 34, 0, cup: 232),
        f("Butter", 717, 0.9, 0.1, 81, 0, cup: 227, piece: 14, "tablespoon"),
        f("Egg, whole, large", 143, 12.6, 0.7, 9.5, 0, piece: 50, "large egg"),
        f("Egg white", 52, 10.9, 0.7, 0.2, 0, cup: 243, piece: 33, "large egg white"),
        f("Whey protein powder", 400, 80, 8, 6, 2, piece: 30, "scoop"),
        // Meat, poultry, fish
        f("Chicken breast, cooked", 165, 31, 0, 3.6, 0),
        f("Chicken breast, raw", 120, 22.5, 0, 2.6, 0),
        f("Chicken thigh, skinless, cooked", 179, 24.8, 0, 8.2, 0),
        f("Turkey breast, cooked", 135, 30, 0, 0.7, 0),
        f("Ground turkey, 93% lean, cooked", 176, 25, 0, 8, 0),
        f("Ground beef, 90% lean, cooked", 217, 26, 0, 11.7, 0),
        f("Ground beef, 80% lean, cooked", 254, 25.9, 0, 16, 0),
        f("Beef sirloin steak, cooked", 200, 27, 0, 10, 0),
        f("Pork chop, cooked", 231, 28, 0, 12, 0),
        f("Pork tenderloin, cooked", 143, 26, 0, 3.5, 0),
        f("Bacon, cooked", 541, 37, 1.4, 42, 0, piece: 8, "slice"),
        f("Ham, deli", 126, 19, 2, 4.5, 0, piece: 28, "slice"),
        f("Salmon, cooked", 206, 22, 0, 12, 0),
        f("Tuna, canned in water, drained", 116, 25.5, 0, 0.8, 0, piece: 142, "can"),
        f("Cod, cooked", 105, 23, 0, 0.9, 0),
        f("Tilapia, cooked", 128, 26, 0, 2.7, 0),
        f("Shrimp, cooked", 99, 24, 0.2, 0.3, 0),
        // Legumes, nuts, seeds
        f("Black beans, cooked", 132, 8.9, 23.7, 0.5, 8.7, cup: 172),
        f("Chickpeas, cooked", 164, 8.9, 27.4, 2.6, 7.6, cup: 164),
        f("Lentils, cooked", 116, 9, 20, 0.4, 7.9, cup: 198),
        f("Edamame, shelled, cooked", 121, 12, 9, 5, 5, cup: 155),
        f("Tofu, firm", 144, 17, 3, 9, 2),
        f("Hummus", 166, 8, 14, 10, 6, cup: 246),
        f("Peanut butter", 588, 25, 20, 50, 6, cup: 258, piece: 16, "tablespoon"),
        f("Almond butter", 614, 21, 19, 56, 10, cup: 256, piece: 16, "tablespoon"),
        f("Almonds", 579, 21, 22, 50, 12.5, cup: 143),
        f("Peanuts", 567, 26, 16, 49, 8.5, cup: 146),
        f("Walnuts", 654, 15, 14, 65, 6.7, cup: 117),
        f("Cashews", 553, 18, 30, 44, 3.3, cup: 137),
        f("Chia seeds", 486, 17, 42, 31, 34, cup: 170),
        // Fruit
        f("Banana", 89, 1.1, 22.8, 0.3, 2.6, cup: 150, piece: 118, "medium banana"),
        f("Apple", 52, 0.3, 13.8, 0.2, 2.4, cup: 125, piece: 182, "medium apple"),
        f("Orange", 47, 0.9, 11.8, 0.1, 2.4, piece: 131, "medium orange"),
        f("Blueberries", 57, 0.7, 14.5, 0.3, 2.4, cup: 148),
        f("Strawberries", 32, 0.7, 7.7, 0.3, 2, cup: 152),
        f("Raspberries", 52, 1.2, 11.9, 0.7, 6.5, cup: 123),
        f("Grapes", 69, 0.7, 18, 0.2, 0.9, cup: 151),
        f("Avocado", 160, 2, 8.5, 14.7, 6.7, cup: 150, piece: 136, "medium avocado"),
        f("Mango", 60, 0.8, 15, 0.4, 1.6, cup: 165),
        f("Pineapple", 50, 0.5, 13, 0.1, 1.4, cup: 165),
        f("Watermelon", 30, 0.6, 7.6, 0.2, 0.4, cup: 152),
        f("Raisins", 299, 3, 79, 0.5, 3.7, cup: 145),
        f("Dates, Medjool", 277, 1.8, 75, 0.2, 6.7, piece: 24, "date"),
        // Vegetables
        f("Broccoli, cooked", 35, 2.4, 7.2, 0.4, 3.3, cup: 156),
        f("Spinach, raw", 23, 2.9, 3.6, 0.4, 2.2, cup: 30),
        f("Carrots, raw", 41, 0.9, 9.6, 0.2, 2.8, cup: 128, piece: 61, "medium carrot"),
        f("Mixed vegetables, frozen, cooked", 65, 2.6, 13.5, 0.2, 4, cup: 182),
        f("Green beans, cooked", 35, 1.9, 7.9, 0.3, 3.2, cup: 125),
        f("Peas, cooked", 84, 5.4, 15.6, 0.2, 5.5, cup: 160),
        f("Corn, sweet, cooked", 96, 3.4, 21, 1.5, 2.4, cup: 164),
        f("Tomato", 18, 0.9, 3.9, 0.2, 1.2, cup: 180, piece: 123, "medium tomato"),
        f("Cucumber", 15, 0.7, 3.6, 0.1, 0.5, cup: 104),
        f("Lettuce, romaine", 17, 1.2, 3.3, 0.3, 2.1, cup: 47),
        f("Onion, raw", 40, 1.1, 9.3, 0.1, 1.7, cup: 160, piece: 110, "medium onion"),
        f("Bell pepper", 31, 1, 6, 0.3, 2.1, cup: 149, piece: 119, "medium pepper"),
        f("Mushrooms, raw", 22, 3.1, 3.3, 0.3, 1, cup: 70),
        f("Asparagus, cooked", 22, 2.4, 4.1, 0.2, 2, cup: 180),
        // Oils, condiments, sweeteners
        f("Olive oil", 884, 0, 0, 100, 0, cup: 216, piece: 13.5, "tablespoon"),
        f("Coconut oil", 892, 0, 0, 100, 0, cup: 218, piece: 13.6, "tablespoon"),
        f("Mayonnaise", 680, 1, 0.6, 75, 0, cup: 220, piece: 13.8, "tablespoon"),
        f("Ketchup", 101, 1, 27, 0.1, 0.3, cup: 272, piece: 17, "tablespoon"),
        f("Honey", 304, 0.3, 82, 0, 0.2, cup: 339, piece: 21, "tablespoon"),
        f("Maple syrup", 260, 0, 67, 0.1, 0, cup: 322, piece: 20, "tablespoon"),
        f("Sugar, white", 387, 0, 100, 0, 0, cup: 200, piece: 12.5, "tablespoon"),
        f("Jam", 278, 0.4, 69, 0.1, 1, cup: 320, piece: 20, "tablespoon"),
        f("Soy sauce", 53, 8, 5, 0.6, 0.8, cup: 255, piece: 16, "tablespoon"),
        f("Salsa", 29, 1.5, 7, 0.2, 1.9, cup: 259),
        f("Sour cream", 198, 2.4, 4.6, 19, 0, cup: 230, piece: 12, "tablespoon"),
        f("Ranch dressing", 430, 1, 6, 45, 0, cup: 240, piece: 15, "tablespoon"),
        // Drinks and treats
        f("Orange juice", 45, 0.7, 10.4, 0.2, 0.2, cup: 248),
        f("Coffee, black", 1, 0.1, 0, 0, 0, cup: 237),
        f("Beer, regular", 43, 0.5, 3.6, 0, 0, cup: 237, piece: 355, "12 oz can"),
        f("Wine, red", 85, 0.1, 2.6, 0, 0, cup: 237, piece: 147, "5 oz glass"),
        f("Cola", 42, 0, 10.6, 0, 0, cup: 247, piece: 368, "12 oz can"),
        f("Ice cream, vanilla", 207, 3.5, 24, 11, 0.7, cup: 132),
        f("Dark chocolate, 70%", 598, 7.8, 46, 43, 11, piece: 10, "square"),
        f("Pizza, cheese", 266, 11, 33, 10, 2.3, piece: 107, "slice"),
    ]

    /// Foods whose name holds every word of `query`, best matches first (a word at the start of
    /// the name beats one later). Empty query, empty result.
    static func search(_ query: String, limit: Int = 12) -> [FoodDraft] {
        let words = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        return all
            .compactMap { food -> (FoodDraft, Int)? in
                let name = food.name.lowercased()
                guard words.allSatisfy({ name.contains($0) }) else { return nil }
                let rank = name.hasPrefix(words[0]) ? 0 : 1
                return (food, rank)
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.name < $1.0.name }
            .prefix(limit)
            .map(\.0)
    }
}
