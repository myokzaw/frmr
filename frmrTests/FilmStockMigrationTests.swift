import AVFoundation
import CoreImage
import ImageIO
import Metal
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// Film stock / strip background: stored-value migrations, defaults persistence, spec tables.

// MARK: - v4 F8: background migration

struct StripBackgroundMigrationTests {

    private typealias Background = StripCustomization.StripBackground

    @Test func storedCreamAndUnknownValuesReadAsWhite() {
        #expect(Background(settingsName: "cream") == .white)
        #expect(Background(settingsName: "teal") == .white)
        #expect(Background(settingsName: nil) == .white)
        #expect(Background(settingsName: "white") == .white)
        #expect(Background(settingsName: "black") == .black)
    }

    @Test func pickersOfferWhiteThenBlackAndTheyRoundTrip() {
        #expect(Background.allCases == [.white, .black])
        for background in Background.allCases {
            #expect(Background(settingsName: background.settingsName) == background)
        }
        #expect(StripCustomization().background == .white)
    }

    @Test func textContrastsWithEachBackground() {
        #expect(Background.white.contrastingTextColor == .appBlack)
        #expect(Background.black.contrastingTextColor == .appCream)
    }

    @Test func storedCreamIsRewrittenToWhiteAtLaunch() throws {
        let defaults = try makeScratchDefaults()
        defaults.set("cream", forKey: Constants.DefaultsKeys.stripBackground)

        #expect(StripViewModel.loadDefaults(from: defaults).background == .white)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: Constants.DefaultsKeys.stripBackground) == "white")

        defaults.set("black", forKey: Constants.DefaultsKeys.stripBackground)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: Constants.DefaultsKeys.stripBackground) == "black")
    }
}

// MARK: - v2 F5: film stock migration

struct FilmStockMigrationTests {

    typealias FilmStock = StripCustomization.FilmStock
    private typealias PrintStock = StripCustomization.PrintStock

    @Test func legacyGrainToggleMapsOntoTheClosestStock() {
        #expect(FilmStock.migrating(fromLegacyGrainEnabled: false) == .none)
        // v2 mapped "on" to ISO 400, which v4 maps to Portrait 400
        #expect(FilmStock.migrating(fromLegacyGrainEnabled: true) == .portrait400)
    }

    // v4 F7 (OPEN v4-6): stored v2 raw values migrate; unknown or missing
    // ones read as Off; every current raw value round-trips.
    private static let storedValues: [(String?, FilmStock)] =
        [("iso100", .daylight200), ("iso400", .portrait400), ("iso3200", .cine500T), ("none", .none),
         ("iso800", .none), ("", .none), (nil, .none)]
        + FilmStock.allCases.map { ($0.rawValue, $0) }

    @Test(arguments: storedValues)
    func storedValuesMigrateToTheirStock(stored: String?, expected: FilmStock) {
        #expect(FilmStock.migrating(fromStoredValue: stored) == expected, "\(String(describing: stored))")
    }

    @Test func decodingAppliesTheSameMigration() throws {
        let decoded = try JSONDecoder().decode([FilmStock].self, from: Data(#"["iso400","cine500T","bogus"]"#.utf8))
        #expect(decoded == [.portrait400, .cine500T, .none])
    }

    @Test func everyStockExceptNoneHasCurvesGrainAndADefaultPrint() {
        for stock in FilmStock.allCases {
            let isOff = stock == .none
            #expect((stock.negative == nil) == isOff, "\(stock.label) curves")
            #expect((stock.grainIntensity > 0) == !isOff, "\(stock.label) grain")
            #expect((stock.defaultPrint == nil) == isOff, "\(stock.label) default print")
            #expect((stock.iso == nil) == isOff, "\(stock.label) ISO")
        }
    }

    @Test func launchSetMatchesTheSpecTable() {
        #expect(FilmStock.allCases.map(\.label) == [
            "Off", "Daylight 200", "Portrait 400", "Cine 500T", "Slide 100", "Mono 400", "Mono 3200",
        ])
        #expect(PrintStock.allCases.map(\.label) == ["Lab print", "Cinema print", "Matte paper", "Projection"])
        #expect(FilmStock.allCases.compactMap(\.iso) == [200, 400, 500, 100, 400, 3200])
        #expect(FilmStock.allCases.filter(\.isMonochrome) == [.mono400, .mono3200])
    }

    @Test func eachStockHasItsSpecDefaultPrint() {
        #expect(FilmStock.daylight200.defaultPrint == .lab)
        #expect(FilmStock.portrait400.defaultPrint == .lab)
        #expect(FilmStock.cine500T.defaultPrint == .cinema)
        #expect(FilmStock.slide100.defaultPrint == .projection)
        #expect(FilmStock.mono400.defaultPrint == .lab)
        #expect(FilmStock.mono3200.defaultPrint == .lab)
    }

    @Test func projectionIsSlideOnlyAndSlideIsProjectionOnly() {
        #expect(FilmStock.slide100.availablePrints == [.projection])
        #expect(FilmStock.none.availablePrints.isEmpty)
        for stock in FilmStock.allCases where stock != .none && stock != .slide100 {
            #expect(stock.availablePrints == [.lab, .cinema, .matte], "\(stock.label)")
        }
    }

    @Test func aNilPrintResolvesToTheStocksDefault() {
        for stock in FilmStock.allCases {
            var customization = StripCustomization()
            customization.filmStock = stock
            customization.printStock = nil
            #expect(customization.resolvedPrint == stock.defaultPrint, "\(stock.label)")
        }
    }

    @Test func aPrintTheStockCannotUseFallsBackToItsDefault() {
        var customization = StripCustomization()
        customization.filmStock = .slide100
        customization.printStock = .matte
        #expect(customization.resolvedPrint == .projection)

        customization.filmStock = .daylight200
        customization.printStock = .projection
        #expect(customization.resolvedPrint == .lab)

        customization.printStock = .matte
        #expect(customization.resolvedPrint == .matte)
    }

    @Test func effectDefaultsArePerSpec() {
        // Halation on for every stock (each at its own strength, Cine 500T
        // strongest); bloom and light leak opt-in
        for stock in FilmStock.allCases {
            let effects = StripCustomization.FilmEffects.defaults(for: stock)
            #expect(effects.halation && !effects.bloom && !effects.lightLeak, "\(stock.label)")
        }
        #expect(StripCustomization().effects == .stockDefaults)
    }

    @Test func monochromeStocksAlwaysRenderInBlackAndWhite() {
        var customization = StripCustomization()
        customization.blackAndWhite = false
        customization.filmStock = .mono400
        #expect(customization.rendersInBlackAndWhite)
        customization.filmStock = .daylight200
        #expect(!customization.rendersInBlackAndWhite)
        customization.blackAndWhite = true
        #expect(customization.rendersInBlackAndWhite)
    }
}

// MARK: - v4 F7: strip defaults persistence

struct StripDefaultsTests {

    @Test func emptyStoreLoadsTheSpecDefaults() throws {
        let loaded = StripViewModel.loadDefaults(from: try makeScratchDefaults())
        #expect(loaded == StripCustomization())
        #expect(loaded.effects.halation, "a missing halation key means the stock default, which is on")
    }

    @Test func storedDefaultsRoundTrip() throws {
        let defaults = try makeScratchDefaults()
        var customization = StripCustomization()
        customization.background = .black
        customization.filmStock = .cine500T
        customization.printStock = .matte
        customization.effects = .init(halation: false, bloom: true, lightLeak: true)
        customization.blackAndWhite = true

        StripViewModel.storeDefaults(customization, in: defaults)
        #expect(StripViewModel.loadDefaults(from: defaults) == customization)

        customization.printStock = nil
        StripViewModel.storeDefaults(customization, in: defaults)
        #expect(StripViewModel.loadDefaults(from: defaults).printStock == nil)
    }

    @Test func v2StockKeyMigratesOnLoadAndInPlace() throws {
        let defaults = try makeScratchDefaults()
        defaults.set("iso3200", forKey: Constants.DefaultsKeys.stripFilmStock)
        #expect(StripViewModel.loadDefaults(from: defaults).filmStock == .cine500T)

        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: Constants.DefaultsKeys.stripFilmStock) == "cine500T")
        // Idempotent
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: Constants.DefaultsKeys.stripFilmStock) == "cine500T")
    }

    @Test func preV2GrainKeyMigratesInPlace() throws {
        let defaults = try makeScratchDefaults()
        defaults.set(true, forKey: Constants.DefaultsKeys.stripFilmGrain)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: Constants.DefaultsKeys.stripFilmStock) == "portrait400")
    }
}

// MARK: - v4 F12: Settings stock default

struct StripStockDefaultMigrationTests {

    private let key = Constants.DefaultsKeys.stripFilmStock

    @Test func aFreshInstallDefaultsToAsShot() throws {
        let defaults = try makeScratchDefaults()
        #expect(StripViewModel.loadDefaults(from: defaults).filmStock == nil)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.object(forKey: key) == nil)
    }

    @Test func storedV4StocksStayOverrides() throws {
        let defaults = try makeScratchDefaults()
        for stock in StripCustomization.FilmStock.allCases {
            defaults.set(stock.rawValue, forKey: key)
            StripViewModel.migrateLegacyDefaults(defaults)
            #expect(StripViewModel.loadDefaults(from: defaults).filmStock == stock, "\(stock.label)")
            #expect(defaults.string(forKey: key) == stock.rawValue)
        }
    }

    @Test func asShotRoundTripsThroughItsStoredValue() throws {
        let defaults = try makeScratchDefaults()
        var customization = StripCustomization()
        customization.filmStock = .cine500T
        StripViewModel.storeDefaults(customization, in: defaults)
        customization.filmStock = nil
        StripViewModel.storeDefaults(customization, in: defaults)

        #expect(defaults.string(forKey: key) == Constants.Strip.asShotStoredValue)
        #expect(StripViewModel.loadDefaults(from: defaults).filmStock == nil)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: key) == Constants.Strip.asShotStoredValue, "migration leaves As shot alone")
    }

    // Stored As shot wins over a leftover pre-v2 grain key
    @Test func asShotIsNotOverriddenByTheLegacyGrainKey() throws {
        let defaults = try makeScratchDefaults()
        defaults.set(true, forKey: Constants.DefaultsKeys.stripFilmGrain)
        defaults.set(Constants.Strip.asShotStoredValue, forKey: key)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(StripViewModel.loadDefaults(from: defaults).filmStock == nil)
    }

    @Test func storedValueMappingIsTotal() {
        #expect(StripCustomization.stockChoice(fromStoredValue: nil) == nil)
        #expect(StripCustomization.stockChoice(fromStoredValue: "asShot") == nil)
        #expect(StripCustomization.stockChoice(fromStoredValue: "iso3200") == .cine500T)
        #expect(StripCustomization.stockChoice(fromStoredValue: "bogus") == StripCustomization.FilmStock.none)
        for choice in StripCustomization.stockChoices {
            let stored = StripCustomization.storedValue(forStockChoice: choice)
            #expect(StripCustomization.stockChoice(fromStoredValue: stored) == choice)
        }
    }
}
