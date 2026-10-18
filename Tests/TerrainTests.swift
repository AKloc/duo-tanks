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

    @Test func flatteningLevelsTheGroundToItsAverage() {
        var heights = Array(repeating: 100.0, count: 1000)
        heights[500] = 130
        var terrain = Terrain(heights: heights)
        terrain.flatten(around: 500, halfWidth: 1)
        #expect(abs(terrain.height(at: 499) - 110) < 0.01)
        #expect(abs(terrain.height(at: 501) - 110) < 0.01)
    }
}
