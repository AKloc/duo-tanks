import Testing
@testable import DuoTanks

struct TerrainTests {
    @Test func carvingDigsACraterToTheBottomOfTheBlast() {
        var terrain = Terrain(flatHeight: 100)
        terrain.carve(center: Vec(500, 100), radius: 20)
        #expect(abs(terrain.height(at: 500) - 80) < 0.01)
        #expect(terrain.height(at: 530) == 100)
    }

    @Test func blastsAboveTheGroundLeaveItAlone() {
        var terrain = Terrain(flatHeight: 100)
        terrain.carve(center: Vec(500, 130), radius: 20)
        #expect(terrain.height(at: 500) == 100)
    }

    @Test func groundAboveAnUndergroundHoleCollapsesIntoIt() {
        var terrain = Terrain(flatHeight: 100)
        terrain.carve(center: Vec(500, 60), radius: 10, leavesScorch: false)
        #expect(abs(terrain.height(at: 500) - 80) < 0.01)
    }

    @Test func dirtPilesUpAsAMound() {
        var terrain = Terrain(flatHeight: 100)
        terrain.addDirt(center: Vec(500, 100), radius: 20)
        #expect(abs(terrain.height(at: 500) - 140) < 0.01)
        #expect(terrain.grass[500] == 0)
    }

    @Test func blastsBurnGrassAndLeaveAScorchMark() {
        var terrain = Terrain(flatHeight: 100)
        terrain.carve(center: Vec(500, 100), radius: 20)
        #expect(terrain.grass[500] == 0)
        #expect(terrain.grass[100] == 1)
        #expect(terrain.scorchMarks.count == 1)
    }

    @Test func liquidDirtRunsDownhillAndFillsTheValleyLevel() {
        // A V-shaped valley bottoming out at x = 500, 50 units deep.
        let heights = (0..<1000).map { x in 100 + min(50, abs(Double(x) - 500) * 0.5) }
        var terrain = Terrain(heights: heights)
        let before = terrain.heights.reduce(0, +)
        terrain.pourLiquid(at: 470, volume: 1_000)
        let added = terrain.heights.reduce(0, +) - before
        #expect(abs(added - 1_000) < 5)
        let level = terrain.height(at: 500)
        #expect(level > 100)
        #expect(abs(terrain.height(at: 490) - level) < 0.01, "the pool's surface is flat")
        #expect(terrain.height(at: 300) == 150, "the hillsides above the pool are untouched")
    }

    @Test func flatteningLevelsTheGroundToItsAverage() {
        var heights = Array(repeating: 100.0, count: 1000)
        heights[500] = 130
        var terrain = Terrain(heights: heights)
        terrain.flatten(around: 500, halfWidth: 1)
        #expect(abs(terrain.height(at: 499) - 110) < 0.01)
        #expect(abs(terrain.height(at: 501) - 110) < 0.01)
    }
}
