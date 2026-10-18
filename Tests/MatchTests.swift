import Testing
@testable import DuoTanks

struct MatchTests {
    @Test func babyMissilesAreUnlimitedAndEverythingElseIsCounted() {
        var inventory = Inventory.starting
        #expect(inventory.count(of: .babyMissile) == nil)
        #expect(inventory.count(of: .missile) == 2)
        inventory.add(.weapon(.missile), quantity: ShopItem.weapon(.missile).bundle)
        #expect(inventory.count(of: .missile) == 5)
        inventory.add(.parachute, quantity: 2)
        #expect(inventory.count(of: ShopItem.parachute) == 2)
    }

    @Test func theCatalogSellsEverythingButTheFreeMissile() {
        #expect(!ShopItem.catalog.contains(.weapon(.babyMissile)))
        #expect(ShopItem.catalog.allSatisfy { $0.price > 0 && $0.bundle > 0 })
    }

    @Test func theMoonNeverHasWeather() {
        for setting in WeatherSetting.allCases {
            #expect(setting.resolve(for: .moon) == .clear)
        }
    }

    @Test func snowyWorldsSnowEvenWhenClear() {
        #expect(WeatherSetting.clear.resolve(for: .snow).precipitation == .snow)
        #expect(WeatherSetting.storm.resolve(for: .desert) == Weather(precipitation: .rain, hasLightning: true))
    }

    @Test func roundEarningsAddUp() {
        let earnings = RoundEarnings(damage: 1_200, kills: 2_500, bonus: 5_000)
        #expect(earnings.total == 8_700)
    }
}
