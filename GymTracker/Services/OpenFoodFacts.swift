import Foundation

/// Open Food Facts: free, open, no API key. https://world.openfoodfacts.org
nonisolated struct OpenFoodFactsClient: Sendable {
    static let shared = OpenFoodFactsClient()
    static let userAgent = "GymTracker/0.1 (iOS; personal use)"

    private let session: URLSession
    private let baseURL = URL(string: "https://world.openfoodfacts.org")!
    /// Text search runs on the newer Search-a-licious service; the legacy cgi/search.pl endpoint is being retired.
    private let searchURL = URL(string: "https://search.openfoodfacts.org/search")!
    private static let fields = "code,product_name,brands,nutriments,serving_quantity,serving_size"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ query: String, pageSize: Int = 25) async throws -> [FoodDraft] {
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "fields", value: Self.fields),
        ]
        let data = try await get(components.url!)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.hits.compactMap { $0.draft }
    }

    func product(barcode: String) async throws -> FoodDraft? {
        var components = URLComponents(url: baseURL.appending(path: "api/v2/product/\(barcode).json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        let data = try await get(components.url!)
        let response = try JSONDecoder().decode(ProductResponse.self, from: data)
        guard response.status == 1 else { return nil }
        return response.product?.draft
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: Wire format

    struct SearchResponse: Decodable {
        var hits: [Product]
    }

    struct ProductResponse: Decodable {
        var status: Int
        var product: Product?
    }

    struct Product: Decodable {
        var code: String?
        var productName: String?
        var brands: LenientStringList?
        var nutriments: [String: LenientDouble]?
        var servingQuantity: LenientDouble?
        var servingSize: String?

        enum CodingKeys: String, CodingKey {
            case code, brands, nutriments
            case productName = "product_name"
            case servingQuantity = "serving_quantity"
            case servingSize = "serving_size"
        }

        /// nil when the product has no usable name or no energy value.
        var draft: FoodDraft? {
            guard let name = productName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            let n = nutriments ?? [:]
            func value(_ key: String) -> Double? { n[key]?.value }
            // Energy: prefer kcal; fall back to kJ.
            let kcal = value("energy-kcal_100g") ?? value("energy_100g").map { $0 / 4.184 }
            guard let kcal else { return nil }
            let brand = brands?.values.first ?? ""
            return FoodDraft(name: name, brand: brand, barcode: code,
                             kcalPer100g: kcal,
                             proteinPer100g: value("proteins_100g") ?? 0,
                             carbsPer100g: value("carbohydrates_100g") ?? 0,
                             fatPer100g: value("fat_100g") ?? 0,
                             fibrePer100g: value("fiber_100g") ?? 0,
                             servingGrams: servingQuantity?.value,
                             servingDescription: servingSize)
        }
    }

    /// Brands arrive as "A, B" from the product API and as ["A", "B"] from search.
    struct LenientStringList: Decodable, Sendable {
        var values: [String]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let list = try? container.decode([String].self) {
                values = list
            } else if let joined = try? container.decode(String.self) {
                values = joined.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                values = []
            }
            values = values.filter { !$0.isEmpty }
        }
    }

    /// Open Food Facts sometimes sends numbers as strings.
    struct LenientDouble: Decodable, Sendable {
        var value: Double?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let d = try? container.decode(Double.self) {
                value = d
            } else if let s = try? container.decode(String.self) {
                value = Double(s.replacingOccurrences(of: ",", with: "."))
            } else {
                value = nil
            }
        }
    }
}
