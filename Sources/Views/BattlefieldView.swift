import SwiftUI

struct BattlefieldView: View {
    private static let ridgeNoise = ValueNoise(seed: 7)
    /// Direction the moonlight comes from (upper right), used to light slopes.
    private static let moonlight = Vec(0.45, 0.89)

    let game: Game

    @State private var ambience = Ambience()
    @State private var soils: [WorldTheme: Image] = [:]

    var body: some View {
        let terrain = game.terrain
        let tanks = game.tanks
        let projectiles = game.projectiles
        let flames = game.flames
        let tracers = game.tracers
        let explosions = game.explosions
        let particles = game.particles
        let floatingTexts = game.floatingTexts
        let wind = game.wind
        let shake = game.shake
        let flash = game.flash
        let turrets = game.turrets
        let camera = game.camera
        let isKillCam = game.phase == .killCam
        let currentID = game.phase == .aiming ? game.current.id : nil
        let theme = game.theme
        let look = ThemeLook.for(theme)
        let weather = game.weather
        let soil = soils[theme]

        GeometryReader { proxy in
            let mapper = WorldMapper(size: proxy.size, camera: camera)
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let blasts = explosions.map { e in
                    let p = mapper.screen(e.center)
                    return Vec(p.x / proxy.size.width, p.y / proxy.size.height)
                }
                let _ = ambience.update(time: time, wind: wind, blasts: blasts, weather: weather, onStrike: game.thunder)
                Canvas { context, size in
                    drawSky(look, weather: weather, in: &context, size: size, mapper: mapper, time: time)
                    drawTerrain(terrain, look: look, soil: soil, in: &context, mapper: mapper, time: time, wind: wind)
                    drawTracers(tracers, tanks: tanks, in: &context, mapper: mapper)
                    drawFlames(flames, terrain: terrain, in: &context, mapper: mapper, time: time)
                    drawBeams(game.beams, in: &context, mapper: mapper)
                    for tank in tanks {
                        drawTank(tank, terrain: terrain, isCurrent: tank.id == currentID, in: &context, mapper: mapper, time: time)
                    }
                    for turret in turrets {
                        drawFlyingTurret(turret, in: &context, mapper: mapper)
                    }
                    drawParticles(particles, kinds: [.smoke], in: &context, mapper: mapper)
                    for explosion in explosions {
                        drawExplosion(explosion, in: &context, mapper: mapper)
                    }
                    drawParticles(particles, kinds: [.fire, .spark, .debris], in: &context, mapper: mapper)
                    for projectile in projectiles {
                        drawProjectile(projectile, in: &context, mapper: mapper)
                    }
                    for text in floatingTexts {
                        drawFloatingText(text, in: &context, mapper: mapper)
                    }
                    drawPrecipitation(in: &context, size: size, time: time)
                    drawVignette(in: &context, size: size)
                    if isKillCam {
                        drawKillCamFrame(in: &context, size: size)
                    } else {
                        drawWind(wind, in: &context, size: size)
                    }
                    if ambience.lightningFlash > 0.01 {
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.85, green: 0.9, blue: 1).opacity(ambience.lightningFlash * 0.35)))
                    }
                    if flash > 0.01 {
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flash * 0.8)))
                    }
                }
                .offset(x: Double.random(in: -1...1) * shake * 9, y: Double.random(in: -1...1) * shake * 9)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard game.phase == .aiming, !game.isComputerTurn else { return }
                let delta = mapper.world(value.location) - game.current.turretCenter
                game.setAngle(atan2(max(delta.y, 0), delta.x) * 180 / .pi)
            })
        }
        .background(Color(red: 0.05, green: 0.06, blue: 0.2))
        .clipped()
        .task(id: theme) {
            guard soils[theme] == nil else { return }
            let palette = SoilTexture.Palette.for(theme)
            let rendered = await Task.detached(priority: .userInitiated) { SoilTexture.make(palette: palette) }.value
            soils[theme] = rendered.map { Image(decorative: $0.image, scale: 1) }
        }
    }

    // MARK: Sky and background

    private func drawSky(_ look: ThemeLook, weather: Weather, in context: inout GraphicsContext, size: CGSize, mapper: WorldMapper, time: Double) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: look.sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
        ))

        let twinkles = look.starBrightness <= 1
        for i in 0..<(look.starBrightness > 1 ? 200 : 120) {
            let point = CGPoint(x: hash(i, 1) * size.width, y: pow(hash(i, 2), 1.6) * size.height * 0.7)
            let r = 0.3 + pow(hash(i, 4), 3) * 1.4
            let twinkle = twinkles ? 0.7 + 0.3 * sin(time * (0.8 + hash(i, 6) * 2.5) + Double(i)) : 1
            let fadeNearHorizon = 1 - point.y / (size.height * 0.75)
            let opacity = min(1, (0.25 + hash(i, 5) * 0.65) * twinkle * fadeNearHorizon * look.starBrightness)
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(opacity)))
        }

        for comet in ambience.comets {
            drawComet(comet, in: &context, size: size)
        }

        switch look.celestial {
        case let .moon(tint): drawMoon(at: mapper.screen(Vec(820, 330)), radius: 20 * mapper.scale, tint: tint, in: &context)
        case .sun: drawSun(at: mapper.screen(Vec(240, 235)), radius: 40 * mapper.scale, in: &context)
        case .earth: drawEarth(at: mapper.screen(Vec(790, 315)), radius: 30 * mapper.scale, time: time, in: &context)
        }

        let isOvercast = weather.precipitation == .rain || weather.hasLightning
        if isOvercast {
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.07, green: 0.07, blue: 0.1).opacity(0.6)))
        }

        if let cloudColor = look.cloudColor {
            let cloudOpacity = isOvercast ? 0.3 : 0.18
            for cloud in ambience.clouds {
                for puff in cloud.puffs {
                    let center = CGPoint(x: (cloud.x + puff.dx) * size.width, y: (cloud.y + puff.dy) * size.height)
                    let r = puff.radius * size.width * (isOvercast ? 1.5 : 1)
                    let rect = CGRect(x: center.x - r, y: center.y - r * 0.6, width: r * 2, height: r * 1.2)
                    context.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [(isOvercast ? Color(white: 0.45) : cloudColor).opacity(cloudOpacity), .clear]),
                        center: center, startRadius: 0, endRadius: r
                    ))
                }
            }
        }

        if let bolt = ambience.bolt {
            drawBolt(bolt, in: &context, size: size)
        }

        for (layer, ridge) in look.ridges.enumerated() {
            var path = Path()
            path.move(to: mapper.screen(Vec(0, 0)))
            for x in stride(from: 0.0, through: Game.worldSize.x, by: 6) {
                path.addLine(to: mapper.screen(Vec(x, ridgeHeight(x, layer: layer, ridge: ridge, shape: look.ridgeShape))))
            }
            path.addLine(to: mapper.screen(Vec(Game.worldSize.x, 0)))
            path.closeSubpath()
            context.fill(path, with: .color(ridge.color))

            if layer == look.ridges.count - 1 {
                drawTreeline(look.trees, ridge: ridge, layer: layer, shape: look.ridgeShape, in: &context, mapper: mapper)
            } else if let haze = look.haze {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [.clear, haze.opacity(0.16)]),
                    startPoint: mapper.screen(Vec(0, ridge.base + ridge.amplitude)), endPoint: mapper.screen(Vec(0, ridge.base * 0.5))
                ))
            }
        }

        if look.hasBirds {
            for flock in ambience.flocks {
                drawFlock(flock, in: &context, size: size)
            }
        }
    }

    private func ridgeHeight(_ x: Double, layer: Int, ridge: (base: Double, amplitude: Double, color: Color), shape: ThemeLook.RidgeShape) -> Double {
        let octaves = shape == .rounded ? 3 : 5
        let n = BattlefieldView.ridgeNoise.fbm(x * 0.0045 * (1 + Double(layer) * 0.7), Double(layer) * 17.3, octaves: octaves)
        switch shape {
        case .jagged:
            let ridged = 1 - abs(n * 2 - 1)
            return ridge.base + ridge.amplitude * (0.55 * n + 0.45 * ridged)
        case .mesa:
            return ridge.base + ridge.amplitude * min(1, max(0, (n - 0.38) * 3.2)) * 0.8
        case .rounded:
            return ridge.base + ridge.amplitude * n * 0.9
        }
    }

    private func drawTreeline(_ trees: ThemeLook.Trees, ridge: (base: Double, amplitude: Double, color: Color), layer: Int, shape: ThemeLook.RidgeShape,
                              in context: inout GraphicsContext, mapper: WorldMapper) {
        var silhouettes = Path()
        var snowCaps = Path()
        switch trees {
        case .none:
            return
        case let .pines(snowy):
            for x in stride(from: 4.0, to: Game.worldSize.x, by: 7) where hash(Int(x), 11) > 0.35 {
                let ground = ridgeHeight(x, layer: layer, ridge: ridge, shape: shape) - 1
                let height = 7 + 13 * hash(Int(x), 12)
                let halfWidth = height * 0.28
                for tier in 0..<3 {
                    let bottom = ground + height * Double(tier) * 0.25
                    let top = bottom + height * (0.55 - Double(tier) * 0.08)
                    let w = halfWidth * (1 - Double(tier) * 0.25)
                    silhouettes.move(to: mapper.screen(Vec(x - w, bottom)))
                    silhouettes.addLine(to: mapper.screen(Vec(x, top)))
                    silhouettes.addLine(to: mapper.screen(Vec(x + w, bottom)))
                    silhouettes.closeSubpath()
                    if snowy {
                        snowCaps.move(to: mapper.screen(Vec(x - w * 0.45, top - (top - bottom) * 0.45)))
                        snowCaps.addLine(to: mapper.screen(Vec(x, top)))
                        snowCaps.addLine(to: mapper.screen(Vec(x + w * 0.45, top - (top - bottom) * 0.45)))
                        snowCaps.closeSubpath()
                    }
                }
            }
        case .cacti:
            for x in stride(from: 10.0, to: Game.worldSize.x, by: 23) where hash(Int(x), 13) > 0.5 {
                let ground = ridgeHeight(x, layer: layer, ridge: ridge, shape: shape) - 1
                let height = 12 + 12 * hash(Int(x), 14)
                silhouettes.addRoundedRect(in: CGRect(origin: mapper.screen(Vec(x - 1.4, ground + height)), size: CGSize(width: 2.8 * mapper.scale, height: height * mapper.scale)),
                                           cornerSize: CGSize(width: 1.4 * mapper.scale, height: 1.4 * mapper.scale))
                for side in [-1.0, 1.0] where hash(Int(x) + Int(side * 3), 15) > 0.3 {
                    let armY = ground + height * (0.35 + 0.25 * hash(Int(x) + Int(side), 16))
                    let armTop = armY + height * 0.35
                    silhouettes.addRoundedRect(in: CGRect(origin: mapper.screen(Vec(x + side * 2.2 - (side > 0 ? 0 : 3.6), armY + 2)), size: CGSize(width: 3.6 * mapper.scale, height: 2 * mapper.scale)),
                                               cornerSize: CGSize(width: mapper.scale, height: mapper.scale))
                    silhouettes.addRoundedRect(in: CGRect(origin: mapper.screen(Vec(x + side * 4.6 - 1.1, armTop)), size: CGSize(width: 2.2 * mapper.scale, height: (armTop - armY) * mapper.scale)),
                                               cornerSize: CGSize(width: 1.1 * mapper.scale, height: 1.1 * mapper.scale))
                }
            }
        }
        context.fill(silhouettes, with: .color(ridge.color))
        context.fill(snowCaps, with: .color(Color(red: 0.85, green: 0.9, blue: 1).opacity(0.8)))
    }

    private func drawSun(at center: CGPoint, radius r: Double, in context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: CGRect(x: center.x - r * 5, y: center.y - r * 5, width: r * 10, height: r * 10)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.75, blue: 0.4).opacity(0.5), .clear]), center: center, startRadius: r, endRadius: r * 5))
        context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .linearGradient(
            Gradient(colors: [Color(red: 1, green: 0.93, blue: 0.65), Color(red: 1, green: 0.55, blue: 0.25)]),
            startPoint: CGPoint(x: center.x, y: center.y - r), endPoint: CGPoint(x: center.x, y: center.y + r)))
    }

    private func drawEarth(at center: CGPoint, radius r: Double, time: Double, in context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: CGRect(x: center.x - r * 1.6, y: center.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 0.6, blue: 1).opacity(0.35), .clear]), center: center, startRadius: r, endRadius: r * 1.6))
        let disc = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: disc), with: .radialGradient(
            Gradient(colors: [Color(red: 0.25, green: 0.5, blue: 0.95), Color(red: 0.05, green: 0.15, blue: 0.4)]),
            center: CGPoint(x: center.x - r * 0.35, y: center.y - r * 0.35), startRadius: 0, endRadius: r * 1.5))
        var surface = context
        surface.clip(to: Path(ellipseIn: disc))
        let spin = time * 0.01
        for i in 0..<6 {
            let u = (hash(i, 50) + spin).truncatingRemainder(dividingBy: 1) * 2.6 - 0.8
            let land = CGRect(x: center.x + (u - 0.5) * r * 2, y: center.y + (hash(i, 51) - 0.5) * r * 1.6, width: r * (0.4 + hash(i, 52) * 0.6), height: r * (0.25 + hash(i, 53) * 0.4))
            surface.fill(Path(ellipseIn: land), with: .color(Color(red: 0.25, green: 0.55, blue: 0.3).opacity(0.85)))
        }
        for i in 0..<5 {
            let u = (hash(i, 60) + spin * 1.6).truncatingRemainder(dividingBy: 1) * 2.6 - 0.8
            let cloud = CGRect(x: center.x + (u - 0.5) * r * 2, y: center.y + (hash(i, 61) - 0.5) * r * 1.8, width: r * (0.6 + hash(i, 62) * 0.7), height: r * 0.18)
            surface.fill(Path(roundedRect: cloud, cornerRadius: r * 0.09), with: .color(.white.opacity(0.7)))
        }
        surface.fill(Path(ellipseIn: disc), with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.65)]),
                                                                  startPoint: CGPoint(x: center.x - r * 0.2, y: center.y), endPoint: CGPoint(x: center.x + r, y: center.y)))
    }

    private func drawBolt(_ bolt: Ambience.Bolt, in context: inout GraphicsContext, size: CGSize) {
        let fade = 1 - bolt.age / Ambience.Bolt.lifetime
        var glow = context
        glow.blendMode = .plusLighter
        for (index, line) in ([bolt.trunk] + bolt.branches).enumerated() {
            var path = Path()
            path.addLines(line.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
            let width = index == 0 ? 2.4 : 1.2
            glow.stroke(path, with: .color(Color(red: 0.6, green: 0.7, blue: 1).opacity(fade * 0.5)), style: StrokeStyle(lineWidth: width * 4, lineCap: .round, lineJoin: .round))
            glow.stroke(path, with: .color(.white.opacity(fade)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawPrecipitation(in context: inout GraphicsContext, size: CGSize, time: Double) {
        guard !ambience.drops.isEmpty else { return }
        switch ambience.precipitation {
        case .none:
            return
        case .rain:
            var streaks = Path()
            let slant = game.wind / Game.windReference * 0.3
            for drop in ambience.drops {
                let top = CGPoint(x: drop.position.x * size.width, y: drop.position.y * size.height)
                streaks.move(to: top)
                streaks.addLine(to: CGPoint(x: top.x + slant * drop.size * size.height, y: top.y + drop.size * size.height))
            }
            context.stroke(streaks, with: .color(Color(red: 0.75, green: 0.8, blue: 0.95).opacity(0.35)), lineWidth: 1)
        case .snow:
            for (i, flake) in ambience.drops.enumerated() {
                let sway = sin(time * 1.3 + Double(i)) * 6
                let center = CGPoint(x: flake.position.x * size.width + sway, y: flake.position.y * size.height)
                let r = flake.size
                context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.85)))
            }
        }
    }

    private func drawMoon(at center: CGPoint, radius r: Double, tint: Color, in context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: CGRect(x: center.x - r * 4, y: center.y - r * 4, width: r * 8, height: r * 8)),
                     with: .radialGradient(Gradient(colors: [tint.opacity(0.22), .clear]),
                                           center: center, startRadius: r, endRadius: r * 4))
        let disc = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: disc), with: .radialGradient(
            Gradient(colors: [tint, tint.mix(with: .gray, by: 0.25)]),
            center: CGPoint(x: center.x - r * 0.3, y: center.y - r * 0.3), startRadius: 0, endRadius: r * 1.4
        ))
        var maria = context
        maria.clip(to: Path(ellipseIn: disc))
        for (dx, dy, size) in [(-0.3, -0.2, 0.45), (0.25, 0.1, 0.35), (-0.05, 0.4, 0.3), (0.35, -0.35, 0.2)] {
            let rect = CGRect(x: center.x + dx * r - size * r, y: center.y + dy * r - size * r * 0.8, width: size * r * 2, height: size * r * 1.6)
            maria.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.6, green: 0.58, blue: 0.55).opacity(0.35)))
        }
    }

    private func drawComet(_ comet: Ambience.Comet, in context: inout GraphicsContext, size: CGSize) {
        let head = CGPoint(x: comet.position.x * size.width, y: comet.position.y * size.height)
        let screenVelocity = Vec(comet.velocity.x * size.width, comet.velocity.y * size.height)
        let direction = screenVelocity / screenVelocity.length
        let tailLength = size.width * 0.14
        let tail = CGPoint(x: head.x - direction.x * tailLength, y: head.y - direction.y * tailLength)
        let brightness = comet.brightness

        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        context.stroke(path, with: .linearGradient(Gradient(colors: [.clear, Color(red: 0.7, green: 0.9, blue: 1).opacity(brightness)]),
                                                   startPoint: tail, endPoint: head),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))

        let glow = 6.0
        context.fill(Path(ellipseIn: CGRect(x: head.x - glow, y: head.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(brightness), .cyan.opacity(brightness * 0.4), .clear]),
                                           center: head, startRadius: 0, endRadius: glow))
    }

    private func drawFlock(_ flock: Ambience.Flock, in context: inout GraphicsContext, size: CGSize) {
        let span = min(max(size.width * 0.009, 4), 8)
        for (i, offset) in flock.offsets.enumerated() {
            let center = CGPoint(x: (flock.position.x + offset.x) * size.width, y: (flock.position.y + offset.y) * size.height)
            let lift = sin(flock.flap + Double(i) * 0.9) * span * 0.6
            var bird = Path()
            bird.move(to: CGPoint(x: center.x - span, y: center.y - lift))
            bird.addQuadCurve(to: center, control: CGPoint(x: center.x - span * 0.4, y: center.y - lift * 0.2 - span * 0.3))
            bird.addQuadCurve(to: CGPoint(x: center.x + span, y: center.y - lift), control: CGPoint(x: center.x + span * 0.4, y: center.y - lift * 0.2 - span * 0.3))
            context.stroke(bird, with: .color(Color(white: 0.06).opacity(0.85)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Ground

    private func drawTerrain(_ terrain: Terrain, look: ThemeLook, soil: Image?, in context: inout GraphicsContext, mapper: WorldMapper, time: Double, wind: Double) {
        let s = mapper.scale
        let heights = terrain.heights
        let last = terrain.width - 1

        var surface = Path()
        surface.move(to: mapper.screen(Vec(0, heights[0])))
        for x in stride(from: 2, to: terrain.width, by: 2) {
            surface.addLine(to: mapper.screen(Vec(Double(x), heights[x])))
        }
        surface.addLine(to: mapper.screen(Vec(Double(last), heights[last])))

        var groundPath = surface
        groundPath.addLine(to: mapper.screen(Vec(Double(last), -10)))
        groundPath.addLine(to: mapper.screen(Vec(0, -10)))
        groundPath.closeSubpath()

        var ground = context
        ground.clip(to: groundPath)
        let worldRect = CGRect(origin: mapper.screen(Vec(0, Game.worldSize.y)), size: CGSize(width: Game.worldSize.x * s, height: Game.worldSize.y * s))
        if let soil {
            ground.draw(soil, in: worldRect)
        } else {
            ground.fill(Path(worldRect), with: .color(Color(red: 0.38, green: 0.26, blue: 0.15)))
        }
        ground.stroke(surface, with: .color(Color(red: 0.12, green: 0.08, blue: 0.05).opacity(0.7)), style: StrokeStyle(lineWidth: 16 * s, lineJoin: .round))
        ground.stroke(surface, with: .color(Color(red: 0.18, green: 0.13, blue: 0.07)), style: StrokeStyle(lineWidth: 6 * s, lineJoin: .round))
        for mark in terrain.scorchMarks {
            let center = mapper.screen(mark.center)
            let r = mark.radius * s * 1.35
            ground.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0.8), location: 0),
                    .init(color: .black.opacity(0.7), location: 0.72),
                    .init(color: .black.opacity(0.35), location: 0.85),
                    .init(color: .clear, location: 1),
                ]),
                center: center, startRadius: 0, endRadius: r
            ))
        }
        ground.fill(Path(worldRect), with: .linearGradient(
            Gradient(colors: [.clear, .black.opacity(0.5)]),
            startPoint: mapper.screen(Vec(0, 160)), endPoint: mapper.screen(Vec(0, 0))
        ))

        var rims = Array(repeating: Path(), count: 5)
        var charred = Path()
        for x in stride(from: 0, to: last - 1, by: 2) {
            let a = Vec(Double(x), heights[x]), b = Vec(Double(x + 2), heights[x + 2])
            let d = b - a
            let normal = Vec(-d.y, d.x) / d.length
            let lit = max(0, normal.x * BattlefieldView.moonlight.x + normal.y * BattlefieldView.moonlight.y)
            let level = min(4, Int(lit * 5))
            if terrain.grass[x] < 0.3 {
                charred.move(to: mapper.screen(a))
                charred.addLine(to: mapper.screen(b))
            } else {
                rims[level].move(to: mapper.screen(a))
                rims[level].addLine(to: mapper.screen(b))
            }
        }
        context.stroke(charred, with: .color(Color(red: 0.13, green: 0.1, blue: 0.08)), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
        for (level, path) in rims.enumerated() {
            let t = Double(level) / 4
            let color: Color = switch look.surface {
            case .grass: Color(red: 0.2 + 0.35 * t, green: 0.22 + 0.4 * t, blue: 0.14 + 0.2 * t)
            case .snow: Color(red: 0.62 + 0.36 * t, green: 0.68 + 0.3 * t, blue: 0.82 + 0.18 * t)
            case let .dust(rim): rim.mix(with: .black, by: 0.55 - 0.45 * t)
            }
            let width: Double = if case .snow = look.surface { 4.5 } else { 2.2 }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * s, lineCap: .round))
        }

        if case .grass = look.surface {
            drawGrass(terrain, in: &context, mapper: mapper, time: time, wind: wind)
        }
    }

    private func drawGrass(_ terrain: Terrain, in context: inout GraphicsContext, mapper: WorldMapper, time: Double, wind: Double) {
        let heights = terrain.heights
        var blades = Array(repeating: Path(), count: 3)
        let lean = wind / Game.windReference
        for i in stride(from: 2, to: terrain.width - 3, by: 2) {
            guard hash(i, 21) < terrain.grass[i], abs(heights[i + 2] - heights[i - 2]) < 6 else { continue }
            for k in 0..<2 {
                let x = Double(i) + Double(k) + hash(i, 22 + k)
                let ground = terrain.height(at: x) - 0.6
                let length = 2.5 + 4.5 * hash(i, 30 + k)
                let bend = lean * 0.9 + sin(time * 2.2 + x * 0.07) * 0.35
                blades[Int(hash(i, 40 + k) * 3)].move(to: mapper.screen(Vec(x, ground)))
                blades[Int(hash(i, 40 + k) * 3)].addQuadCurve(
                    to: mapper.screen(Vec(x + bend * length * 0.45, ground + length)),
                    control: mapper.screen(Vec(x + bend * length * 0.1, ground + length * 0.6))
                )
            }
        }
        let colors = [Color(red: 0.2, green: 0.36, blue: 0.17), Color(red: 0.28, green: 0.46, blue: 0.21), Color(red: 0.4, green: 0.55, blue: 0.27)]
        for (i, path) in blades.enumerated() {
            context.stroke(path, with: .color(colors[i]), style: StrokeStyle(lineWidth: max(0.6, 0.9 * mapper.scale), lineCap: .round))
        }
    }

    // MARK: Actors

    private func drawTank(_ tank: Tank, terrain: Terrain, isCurrent: Bool, in context: inout GraphicsContext, mapper: WorldMapper, time: Double) {
        let s = mapper.scale
        let ground = mapper.screen(tank.position)
        let slope = atan((terrain.height(at: tank.position.x + 8) - terrain.height(at: tank.position.x - 8)) / 16)
        let lean = min(max(slope, -0.6), 0.6) + tank.tilt
        let base = CGPoint(x: ground.x, y: ground.y - tank.hop * s)
        let facing: Double = tank.angle <= 90 ? 1 : -1
        let paint = tank.isAlive ? tank.color.mix(with: Color(red: 0.32, green: 0.33, blue: 0.27), by: 0.45) : Color(red: 0.34, green: 0.29, blue: 0.25)
        let light = paint.mix(with: .white, by: 0.3)
        let dark = paint.mix(with: .black, by: 0.55)

        /// Screen rotation of the hull: world counter-clockwise is screen negative.
        let turn = -lean
        func rotated(_ v: CGPoint, by angle: Double) -> CGPoint {
            CGPoint(x: v.x * cos(angle) - v.y * sin(angle), y: v.x * sin(angle) + v.y * cos(angle))
        }
        let turretOffset = rotated(CGPoint(x: 0, y: -Tank.bodyHeight * s), by: turn)
        let turret = CGPoint(x: base.x + turretOffset.x, y: base.y + turretOffset.y)

        let shadowWidth = 34 * s / (1 + tank.hop * 0.05)
        context.fill(Path(ellipseIn: CGRect(x: ground.x - shadowWidth / 2, y: ground.y - 2 * s, width: shadowWidth, height: 5 * s)), with: .color(.black.opacity(0.45)))

        if isCurrent {
            let glow = 30 * s
            context.fill(Path(ellipseIn: CGRect(x: turret.x - glow, y: turret.y - glow, width: glow * 2, height: glow * 2)),
                         with: .radialGradient(Gradient(colors: [tank.color.opacity(0.3), .clear]), center: turret, startRadius: 0, endRadius: glow))
        }

        var body = context
        body.translateBy(x: base.x, y: base.y)
        body.rotate(by: .radians(turn))
        func p(_ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: dx * facing * s, y: -dy * s) }
        let localTurret = CGPoint(x: 0, y: -Tank.bodyHeight * s)

        if tank.hasTurret {
            // Keep the barrel on the real aim angle while the hull rocks.
            let aim = tank.angle * .pi / 180
            let reach = rotated(CGPoint(x: cos(aim) * Tank.barrelLength * s, y: -sin(aim) * Tank.barrelLength * s), by: -turn)
            let muzzle = CGPoint(x: localTurret.x + reach.x, y: localTurret.y + reach.y)
            var barrel = Path()
            barrel.move(to: localTurret)
            barrel.addLine(to: muzzle)
            body.stroke(barrel, with: .color(dark), style: StrokeStyle(lineWidth: 3.2 * s, lineCap: .butt))
            body.stroke(barrel, with: .color(light.opacity(0.6)), style: StrokeStyle(lineWidth: 1 * s, lineCap: .butt))
            var muzzleBrake = Path()
            muzzleBrake.move(to: CGPoint(x: muzzle.x - reach.x * 0.16, y: muzzle.y - reach.y * 0.16))
            muzzleBrake.addLine(to: muzzle)
            body.stroke(muzzleBrake, with: .color(dark), style: StrokeStyle(lineWidth: 4.6 * s, lineCap: .butt))
        }

        var hull = Path()
        hull.move(to: p(-14, 4))
        hull.addLine(to: p(-12, 9.5))
        hull.addLine(to: p(9, 9.5))
        hull.addLine(to: p(14.5, 5))
        hull.addLine(to: p(14, 4))
        hull.closeSubpath()
        body.fill(hull, with: .linearGradient(Gradient(colors: [light, paint, dark]), startPoint: p(0, 9.5), endPoint: p(0, 4)))
        var deck = Path()
        deck.move(to: p(-12, 9.5))
        deck.addLine(to: p(9, 9.5))
        body.stroke(deck, with: .color(.white.opacity(0.35)), lineWidth: 0.8 * s)

        let track = CGRect(x: -15 * s, y: -5 * s, width: 30 * s, height: 5 * s)
        body.fill(Path(roundedRect: track, cornerRadius: 2.5 * s), with: .color(Color(white: 0.1)))
        body.stroke(Path(roundedRect: track.insetBy(dx: 0.5 * s, dy: 0.5 * s), cornerRadius: 2.2 * s),
                    with: .color(Color(white: 0.4).opacity(0.5)), style: StrokeStyle(lineWidth: 0.8 * s, dash: [1.1 * s, 1.1 * s], dashPhase: -tank.treadTravel * facing * s))
        for i in 0..<6 {
            let wheel = CGPoint(x: track.minX + (3 + Double(i) * 4.8) * s, y: track.midY)
            let r = 1.9 * s
            body.fill(Path(ellipseIn: CGRect(x: wheel.x - r, y: wheel.y - r, width: r * 2, height: r * 2)),
                      with: .radialGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.25)]), center: wheel, startRadius: 0, endRadius: r))
        }

        if tank.hasTurret {
            let dome = CGRect(x: -7 * s, y: localTurret.y - 5 * s, width: 14 * s, height: 8 * s)
            body.fill(Path(roundedRect: dome, cornerRadius: 4 * s), with: .linearGradient(
                Gradient(colors: [light, paint, dark]), startPoint: CGPoint(x: dome.midX, y: dome.minY), endPoint: CGPoint(x: dome.midX, y: dome.maxY)))
            body.fill(Path(ellipseIn: CGRect(x: -(2 + 2.5 * facing) * s, y: localTurret.y - 6 * s, width: 4 * s, height: 1.8 * s)), with: .color(dark))
            var antenna = Path()
            antenna.move(to: CGPoint(x: -5 * facing * s, y: localTurret.y - 4 * s))
            antenna.addLine(to: CGPoint(x: -7 * facing * s, y: localTurret.y - 15 * s))
            body.stroke(antenna, with: .color(Color(white: 0.2)), lineWidth: 0.6 * s)
        }

        if tank.isParachuting {
            drawParachute(above: turret, scale: s, in: &context)
        }

        guard tank.isAlive else {
            var embers = context
            embers.blendMode = .plusLighter
            let glow = (10 + sin(time * 5 + tank.position.x) * 1.5) * s
            embers.fill(Path(ellipseIn: CGRect(x: base.x - glow, y: base.y - 6 * s - glow * 0.6, width: glow * 2, height: glow * 1.2)),
                        with: .radialGradient(Gradient(colors: [.orange.opacity(0.45), .red.opacity(0.15), .clear]),
                                              center: CGPoint(x: base.x, y: base.y - 6 * s), startRadius: 0, endRadius: glow))
            return
        }
        if tank.shield > 0 {
            drawShield(around: turret, strength: tank.shield / Tank.maxShield, scale: s, time: time, in: &context)
        }
        let bar = CGRect(x: ground.x - 14 * s, y: turret.y - 24 * s, width: 28 * s, height: 3.5 * s)
        context.fill(Path(roundedRect: bar, cornerRadius: 1.5 * s), with: .color(.black.opacity(0.55)))
        context.fill(Path(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * tank.health / 100, height: bar.height), cornerRadius: 1.5 * s),
                     with: .color(tank.health > 60 ? .green : tank.health > 30 ? .yellow : .red))

        if isCurrent {
            var marker = Path()
            let tip = CGPoint(x: ground.x, y: bar.minY - 3 * s)
            marker.move(to: tip)
            marker.addLine(to: CGPoint(x: tip.x - 5 * s, y: tip.y - 7 * s))
            marker.addLine(to: CGPoint(x: tip.x + 5 * s, y: tip.y - 7 * s))
            marker.closeSubpath()
            context.fill(marker, with: .color(.yellow))
        }
    }

    private func drawFlyingTurret(_ turret: FlyingTurret, in context: inout GraphicsContext, mapper: WorldMapper) {
        let s = mapper.scale
        let center = mapper.screen(turret.position)
        let charred = turret.color.mix(with: Color(red: 0.3, green: 0.26, blue: 0.22), by: 0.6)
        var piece = context
        piece.translateBy(x: center.x, y: center.y)
        piece.rotate(by: .radians(-turret.angle))
        var barrel = Path()
        barrel.move(to: .zero)
        barrel.addLine(to: CGPoint(x: Tank.barrelLength * s, y: 0))
        piece.stroke(barrel, with: .color(Color(white: 0.32)), style: StrokeStyle(lineWidth: 3 * s, lineCap: .butt))
        piece.fill(Path(roundedRect: CGRect(x: -7 * s, y: -5 * s, width: 14 * s, height: 8 * s), cornerRadius: 4 * s), with: .color(charred))
    }

    private func drawKillCamFrame(in context: inout GraphicsContext, size: CGSize) {
        let bar = size.height * 0.1
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: bar)), with: .color(.black))
        context.fill(Path(CGRect(x: 0, y: size.height - bar, width: size.width, height: bar)), with: .color(.black))
        let label = Text("● KILL CAM")
            .font(.system(size: max(11, bar * 0.45), weight: .heavy, design: .rounded))
            .foregroundStyle(.red)
        context.draw(label, at: CGPoint(x: 16, y: bar / 2), anchor: .leading)
    }

    private func drawParachute(above turret: CGPoint, scale s: Double, in context: inout GraphicsContext) {
        let canopy = CGRect(x: turret.x - 16 * s, y: turret.y - 40 * s, width: 32 * s, height: 18 * s)
        var dome = Path()
        dome.addArc(center: CGPoint(x: canopy.midX, y: canopy.maxY), radius: canopy.width / 2, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        dome.closeSubpath()
        context.fill(dome, with: .linearGradient(Gradient(colors: [Color(white: 0.95), Color(red: 0.85, green: 0.35, blue: 0.2)]),
                                                 startPoint: CGPoint(x: canopy.midX, y: canopy.minY), endPoint: CGPoint(x: canopy.midX, y: canopy.maxY)))
        var lines = Path()
        for dx in [-16.0, -6, 6, 16] {
            lines.move(to: CGPoint(x: canopy.midX + dx * s, y: canopy.maxY))
            lines.addLine(to: CGPoint(x: turret.x + dx * 0.3 * s, y: turret.y - 3 * s))
        }
        context.stroke(lines, with: .color(.white.opacity(0.6)), lineWidth: 0.6 * s)
    }

    private func drawShield(around turret: CGPoint, strength: Double, scale s: Double, time: Double, in context: inout GraphicsContext) {
        let r = (20 + sin(time * 3) * 0.6) * s
        let bubble = CGRect(x: turret.x - r, y: turret.y - r, width: r * 2, height: r * 2)
        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(Path(ellipseIn: bubble), with: .radialGradient(
            Gradient(colors: [.clear, .cyan.opacity(0.08 + 0.12 * strength), .cyan.opacity(0.25 + 0.35 * strength)]),
            center: turret, startRadius: 0, endRadius: r
        ))
        glow.stroke(Path(ellipseIn: bubble), with: .color(.cyan.opacity(0.4 + 0.5 * strength)), lineWidth: 1.2 * s)
    }

    private func drawTracers(_ tracers: [Int: [Vec]], tanks: [Tank], in context: inout GraphicsContext, mapper: WorldMapper) {
        for (ownerID, points) in tracers where points.count > 1 {
            let color = tanks.first { $0.id == ownerID }?.color ?? .white
            var path = Path()
            path.addLines(points.map(mapper.screen))
            context.stroke(path, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4]))
            if let end = points.last {
                let p = mapper.screen(end)
                context.stroke(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(color), lineWidth: 1.5)
            }
        }
    }

    private func drawFlames(_ flames: [Flame], terrain: Terrain, in context: inout GraphicsContext, mapper: WorldMapper, time: Double) {
        var glow = context
        glow.blendMode = .plusLighter
        for flame in flames {
            let base = mapper.screen(Vec(flame.x, terrain.height(at: flame.x) + 2))
            let flicker = 0.75 + 0.25 * sin(time * 17 + flame.x)
            let r = 14 * mapper.scale * flicker * min(1, flame.life)
            glow.fill(Path(ellipseIn: CGRect(x: base.x - r, y: base.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
                Gradient(colors: [.yellow.opacity(0.8), .orange.opacity(0.5), .clear]), center: base, startRadius: 0, endRadius: r))
        }
    }

    private func drawBeams(_ beams: [Beam], in context: inout GraphicsContext, mapper: WorldMapper) {
        var glow = context
        glow.blendMode = .plusLighter
        for beam in beams {
            let fade = 1 - beam.age / Beam.lifetime
            var path = Path()
            path.addLines(beam.points.map(mapper.screen))
            glow.stroke(path, with: .color(Color(red: 1, green: 0.2, blue: 0.4).opacity(fade * 0.5)), style: StrokeStyle(lineWidth: 9 * mapper.scale * fade, lineCap: .round))
            glow.stroke(path, with: .color(.white.opacity(fade)), style: StrokeStyle(lineWidth: max(1, 1.6 * mapper.scale), lineCap: .round))
        }
    }

    private func drawProjectile(_ projectile: Projectile, in context: inout GraphicsContext, mapper: WorldMapper) {
        let s = mapper.scale
        if projectile.burrowTimeLeft != nil { return }
        if projectile.rollDirection != nil {
            let center = mapper.screen(projectile.position)
            let r = 2.8 * s
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
                Gradient(colors: [Color(white: 0.75), Color(white: 0.2)]), center: CGPoint(x: center.x - r * 0.4, y: center.y - r * 0.4), startRadius: 0, endRadius: r * 1.6))
            var glow = context
            glow.blendMode = .plusLighter
            glow.fill(Path(ellipseIn: CGRect(x: center.x - r * 2.5, y: center.y - r * 2.5, width: r * 5, height: r * 5)),
                      with: .radialGradient(Gradient(colors: [.red.opacity(0.5), .clear]), center: center, startRadius: 0, endRadius: r * 2.5))
            return
        }
        let points = (projectile.trail + [projectile.position]).map(mapper.screen)
        var trail = Path()
        trail.addLines(points)
        context.stroke(trail, with: .color(.white.opacity(0.12)), lineWidth: max(0.8, 0.8 * s))

        let head = mapper.screen(projectile.position)
        if head.y < 0 {
            var marker = Path()
            marker.move(to: CGPoint(x: head.x, y: 4))
            marker.addLine(to: CGPoint(x: head.x - 6, y: 14))
            marker.addLine(to: CGPoint(x: head.x + 6, y: 14))
            marker.closeSubpath()
            context.fill(marker, with: .color(.orange.opacity(0.9)))
            return
        }
        var shell = context
        shell.translateBy(x: head.x, y: head.y)
        shell.rotate(by: .radians(atan2(-projectile.velocity.y, projectile.velocity.x)))
        var tracer = shell
        tracer.blendMode = .plusLighter
        tracer.fill(Path(ellipseIn: CGRect(x: -9 * s, y: -3 * s, width: 8 * s, height: 6 * s)),
                    with: .radialGradient(Gradient(colors: [.orange.opacity(0.9), .red.opacity(0.3), .clear]), center: CGPoint(x: -5 * s, y: 0), startRadius: 0, endRadius: 4 * s))
        shell.fill(Path(roundedRect: CGRect(x: -3.5 * s, y: -1.2 * s, width: 7 * s, height: 2.4 * s), cornerRadius: 1.2 * s),
                   with: .linearGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.2)]), startPoint: CGPoint(x: 0, y: -1.2 * s), endPoint: CGPoint(x: 0, y: 1.2 * s)))
    }

    private func drawExplosion(_ explosion: Explosion, in context: inout GraphicsContext, mapper: WorldMapper) {
        let center = mapper.screen(explosion.center)
        let t = explosion.progress
        let fade = 1 - t

        if explosion.style == .plasma {
            let r = explosion.radius * mapper.scale * (0.4 + 0.9 * min(t * 3, 1))
            var glow = context
            glow.blendMode = .plusLighter
            glow.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
                Gradient(colors: [.white.opacity(fade), Color(red: 0.7, green: 0.5, blue: 1).opacity(fade * 0.9), .cyan.opacity(fade * 0.4), .clear]),
                center: center, startRadius: 0, endRadius: r))
            glow.stroke(Path(ellipseIn: CGRect(x: center.x - r * 1.2, y: center.y - r * 1.2, width: r * 2.4, height: r * 2.4)),
                        with: .color(.cyan.opacity(fade * 0.6)), lineWidth: 2 * mapper.scale)
            return
        }
        if explosion.style == .dirt {
            let r = explosion.radius * mapper.scale * (0.5 + 0.5 * t)
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 0.28, blue: 0.15).opacity(fade * 0.7), .clear]),
                                               center: center, startRadius: 0, endRadius: r))
            return
        }

        let ring = explosion.radius * mapper.scale * (0.6 + 1.4 * t)
        context.stroke(Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)),
                       with: .color(.white.opacity(fade * 0.25)), lineWidth: max(1, 2 * mapper.scale * fade))

        let r = explosion.radius * mapper.scale * (0.5 + 0.9 * min(t * 4, 1))
        var light = context
        light.blendMode = .plusLighter
        light.fill(Path(ellipseIn: CGRect(x: center.x - r * 1.6, y: center.y - r * 1.6, width: r * 3.2, height: r * 3.2)), with: .radialGradient(
            Gradient(colors: [.orange.opacity(fade * 0.45), .clear]), center: center, startRadius: 0, endRadius: r * 1.6))
        let core = r * max(0, 1 - t * 2.5)
        light.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)), with: .radialGradient(
            Gradient(colors: [.white, .yellow.opacity(0.9), .orange.opacity(0.5), .clear]), center: center, startRadius: 0, endRadius: max(core, 0.1)))
    }

    private func drawParticles(_ particles: [Particle], kinds: Set<Particle.Kind>, in context: inout GraphicsContext, mapper: WorldMapper) {
        var additive = context
        additive.blendMode = .plusLighter
        for p in particles where kinds.contains(p.kind) {
            let point = mapper.screen(p.position)
            let t = p.progress
            let fade = 1 - t
            switch p.kind {
            case .spark:
                let r = p.size * mapper.scale
                additive.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .color(p.color.opacity(fade)))
            case .debris:
                let r = p.size * mapper.scale
                context.fill(Path(CGRect(x: point.x - r / 2, y: point.y - r / 2, width: r, height: r)), with: .color(p.color.opacity(min(1, fade * 2))))
            case .smoke:
                let r = p.size * mapper.scale * (0.6 + t)
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
                    Gradient(colors: [p.color.opacity(fade * 0.6), p.color.opacity(0)]), center: point, startRadius: 0, endRadius: r))
            case .fire:
                let r = p.size * mapper.scale * (0.6 + 0.9 * t)
                let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                if t < 0.5 {
                    let heat = t / 0.5
                    let color = Color(red: 1, green: 0.95 - 0.6 * heat, blue: 0.7 - 0.65 * heat)
                    additive.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [color.opacity(0.9 - heat * 0.4), color.opacity(0)]), center: point, startRadius: 0, endRadius: r))
                } else {
                    let cool = (t - 0.5) / 0.5
                    context.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [Color(white: 0.12).opacity(0.6 * (1 - cool)), .clear]), center: point, startRadius: 0, endRadius: r))
                }
            }
        }
    }

    private func drawFloatingText(_ text: FloatingText, in context: inout GraphicsContext, mapper: WorldMapper) {
        let point = mapper.screen(text.position + Vec(0, 30 * text.progress))
        let label = Text(text.text)
            .font(.system(size: max(12, 16 * mapper.scale), weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
        var shadowed = context
        shadowed.opacity = 1 - pow(text.progress, 2)
        shadowed.addFilter(.shadow(color: text.color, radius: 3))
        shadowed.draw(label, at: point)
    }

    private func drawVignette(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.55)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [.clear, .clear, .black.opacity(0.45)]),
            center: center, startRadius: 0, endRadius: max(size.width, size.height) * 0.75
        ))
    }

    private func drawWind(_ wind: Double, in context: inout GraphicsContext, size: CGSize) {
        let arrow = wind == 0 ? "–" : (wind > 0 ? "→" : "←")
        let text = Text("Wind \(arrow) \(Int(abs(wind)))")
            .font(.caption.monospacedDigit().bold())
            .foregroundStyle(.white)
        context.draw(text, at: CGPoint(x: size.width / 2, y: 14))
    }

    /// Stable pseudo-random 0..<1 so scenery doesn't jump between frames.
    private func hash(_ i: Int, _ salt: Int) -> Double {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return v - v.rounded(.down)
    }
}

/// Maps the fixed-size world (y up) onto the view (y down), filling the width and bottom-aligned.
/// On short views the empty sky at the top of the world is cropped.
struct WorldMapper {
    let scale: Double
    let origin: CGPoint

    init(size: CGSize, camera: Camera? = nil) {
        let fit = size.width / Game.worldSize.x
        guard let camera else {
            scale = fit
            origin = CGPoint(x: 0, y: size.height)
            return
        }
        scale = fit * camera.zoom
        // Never show below the bottom of the world.
        let centerY = max(camera.center.y, size.height / 2 / scale)
        origin = CGPoint(x: size.width / 2 - camera.center.x * scale, y: size.height / 2 + centerY * scale)
    }

    func screen(_ p: Vec) -> CGPoint {
        CGPoint(x: origin.x + p.x * scale, y: origin.y - p.y * scale)
    }

    func world(_ p: CGPoint) -> Vec {
        Vec((p.x - origin.x) / scale, (origin.y - p.y) / scale)
    }
}
