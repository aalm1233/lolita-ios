import Foundation

final class AppModule: @unchecked Sendable {
    static let shared = AppModule()
    private init() {}

    let preferences = AppPreferences()
    private(set) var db: LolitaDatabase!

    func setupDatabase() throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = docs.appendingPathComponent("lolita.sqlite").path
        db = try LolitaDatabase(path: dbPath)
    }

    func seedIfNeeded() async throws {
        if preferences.isFirstLaunch {
            try await seedPresetData()
            preferences.isFirstLaunch = false
        }
    }

    // MARK: - Lazy repositories

    lazy var itemRepository: ItemRepository = {
        ItemRepository(db: db.dbQueue)
    }()

    lazy var brandRepository: BrandRepository = {
        BrandRepository(db: db.dbQueue)
    }()

    lazy var categoryRepository: CategoryRepository = {
        CategoryRepository(db: db.dbQueue)
    }()

    lazy var styleRepository: StyleRepository = {
        StyleRepository(db: db.dbQueue)
    }()

    lazy var seasonRepository: SeasonRepository = {
        SeasonRepository(db: db.dbQueue)
    }()

    lazy var coordinateRepository: CoordinateRepository = {
        CoordinateRepository(db: db.dbQueue)
    }()

    lazy var outfitLogRepository: OutfitLogRepository = {
        OutfitLogRepository(db: db.dbQueue)
    }()

    lazy var locationRepository: LocationRepository = {
        LocationRepository(db: db.dbQueue)
    }()

    lazy var sourceRepository: SourceRepository = {
        SourceRepository(db: db.dbQueue)
    }()

    lazy var recommendationRepository: RecommendationRepository = {
        RecommendationRepository(db: db.dbQueue)
    }()

    lazy var priceRepository: PriceRepository = {
        PriceRepository(db: db.dbQueue)
    }()

    lazy var paymentRepository: PaymentRepository = {
        PaymentRepository(db: db.dbQueue)
    }()

    // MARK: - Preset seeding

    private func seedPresetData() async throws {
        try await db.dbQueue.write { db in
            for brand in PresetData.brands {
                let b = Brand(name: brand, isPreset: true)
                try b.insert(db)
            }
            for cat in PresetData.categories {
                let c = Category(name: cat.name, group: cat.group, isPreset: true)
                try c.insert(db)
            }
            for style in PresetData.styles {
                let s = Style(name: style, isPreset: true)
                try s.insert(db)
            }
            for season in PresetData.seasons {
                let s = Season(name: season, isPreset: true)
                try s.insert(db)
            }
        }
    }
}
