import Testing
@testable import DuoTanks

struct BallisticsTests {
    private func ballistics(wind: Double = 0, targets: [Ballistics.Target] = []) -> Ballistics {
        Ballistics(
            terrain: Terrain(flatHeight: 100), wind: wind, gravity: Game.standardGravity,
            speedPerPower: Game.speedPerPower, origin: Vec(200, 107), ownerID: 0, tanks: targets
        )
    }

    @Test func rangeMatchesTheProjectileMotionFormula() throws {
        let impact = try #require(ballistics().impact(angle: 45, power: 50))
        // v² sin(2θ) / g = 300² / 200 = 450, plus a little for launching from above the ground.
        #expect((440...480).contains(impact.x - 200))
    }

    @Test func tailwindCarriesTheShotFarther() throws {
        let calm = try #require(ballistics().impact(angle: 45, power: 50))
        let windy = try #require(ballistics(wind: 30).impact(angle: 45, power: 50))
        #expect(windy.x > calm.x + 20)
    }

    @Test func shotsThatLeaveTheWorldReportNoImpact() {
        #expect(ballistics().impact(angle: 170, power: 100) == nil)
    }

    @Test func bestAimLandsOnTheTarget() throws {
        let target = Vec(640, 107)
        let aim = try #require(ballistics(wind: -18, targets: [.init(id: 1, center: target)]).bestAim(at: target))
        #expect(aim.miss <= Tank.standardRadius, "the shell stops as soon as it reaches the tank")
        #expect(aim.angle < 90)
    }

    @Test func bestAimNeverLandsOnTheShooter() throws {
        // A target right next to the shooter: the closest landing spot is the shooter itself, which must be ruled out.
        let shooter = ballistics(wind: -40)
        let aim = try #require(shooter.bestAim(at: Vec(230, 107), safeRadius: 40))
        #expect((aim.impact - Vec(200, 107)).length >= 40)
    }

    @Test func bestAimFacesTargetsOnTheLeft() throws {
        let shooter = Ballistics(terrain: Terrain(flatHeight: 100), wind: 0, gravity: Game.standardGravity,
                                 speedPerPower: Game.speedPerPower, origin: Vec(800, 107), ownerID: 0, tanks: [])
        let aim = try #require(shooter.bestAim(at: Vec(400, 100)))
        #expect(aim.angle > 90)
        #expect(aim.miss < 3)
    }
}
