import SwiftUI

struct BattlefieldView: View {
    private static let ridgeNoise = ValueNoise(seed: 7)
    /// Direction the moonlight comes from (upper right), used to light slopes.
    private static let moonlight = Vec(0.45, 0.89)

    let game: Game

    @State private var ambience = Ambience()
    @State private var soil: Image?

    var body: some View {
        let terrain = game.terrain
        let tanks = game.tanks
        let projectiles = game.projectiles
        let explosions = game.explosions
        let particles = game.particles
        let floatingTexts = game.floatingTexts
        let wind = game.wind
        let shake = game.shake
        let flash = game.flash
        let currentID = game.phase == .aiming ? game.current.id : nil

        GeometryReader { proxy in
            let mapper = WorldMapper(size: proxy.size)
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let blasts = explosions.map { e in
                    let p = mapper.screen(e.center)
                    return Vec(p.x / proxy.size.width, p.y / proxy.size.height)
                }
                let _ = ambience.update(time: time, wind: wind, blasts: blasts)
                Canvas { context, size in
                    drawSky(in: &context, size: size, mapper: mapper, time: time)
                    drawTerrain(terrain, in: &context, mapper: mapper, time: time, wind: wind)
                    for tank in tanks {
                        drawTank(tank, isCurrent: tank.id == currentID, in: &context, mapper: mapper)
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
                    drawVignette(in: &context, size: size)
                    drawWind(wind, in: &context, size: size)
                    if flash > 0.01 {
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flash * 0.8)))
                    }
                }
                .offset(x: Double.random(in: -1...1) * shake * 9, y: Double.random(in: -1...1) * shake * 9)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard game.phase == .aiming else { return }
                let delta = mapper.world(value.location) - game.current.turretCenter
                game.setAngle(atan2(max(delta.y, 0), delta.x) * 180 / .pi)
            })
        }
        .background(Color(red: 0.05, green: 0.06, blue: 0.2))
        .clipped()
        .task {
            guard soil == nil else { return }
            let rendered = await Task.detached(priority: .userInitiated) { SoilTexture.make() }.value
            soil = rendered.map { Image(decorative: $0.image, scale: 1) }
        }
    }

    // MARK: Sky and background

    private func drawSky(in context: inout GraphicsContext, size: CGSize, mapper: WorldMapper, time: Double) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.03, green: 0.04, blue: 0.14), location: 0),
                .init(color: Color(red: 0.12, green: 0.1, blue: 0.3), location: 0.45),
                .init(color: Color(red: 0.42, green: 0.24, blue: 0.4), location: 0.75),
                .init(color: Color(red: 0.85, green: 0.5, blue: 0.42), location: 1),
            ]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
        ))

        for i in 0..<120 {
            let point = CGPoint(x: hash(i, 1) * size.width, y: pow(hash(i, 2), 1.6) * size.height * 0.7)
            let r = 0.3 + pow(hash(i, 4), 3) * 1.4
            let twinkle = 0.7 + 0.3 * sin(time * (0.8 + hash(i, 6) * 2.5) + Double(i))
            let fadeNearHorizon = 1 - point.y / (size.height * 0.75)
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity((0.25 + hash(i, 5) * 0.65) * twinkle * fadeNearHorizon)))
        }

        for comet in ambience.comets {
            drawComet(comet, in: &context, size: size)
        }

        drawMoon(at: mapper.screen(Vec(820, 330)), radius: 20 * mapper.scale, in: &context)

        for cloud in ambience.clouds {
            for puff in cloud.puffs {
                let center = CGPoint(x: (cloud.x + puff.dx) * size.width, y: (cloud.y + puff.dy) * size.height)
                let r = puff.radius * size.width
                let rect = CGRect(x: center.x - r, y: center.y - r * 0.6, width: r * 2, height: r * 1.2)
                context.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.8, green: 0.72, blue: 0.9).opacity(0.18), .clear]),
                    center: center, startRadius: 0, endRadius: r
                ))
            }
        }

        let ridges: [(base: Double, amplitude: Double, color: Color)] = [
            (175, 140, Color(red: 0.36, green: 0.27, blue: 0.46)),
            (120, 120, Color(red: 0.22, green: 0.16, blue: 0.32)),
            (70, 95, Color(red: 0.11, green: 0.08, blue: 0.18)),
        ]
        for (layer, ridge) in ridges.enumerated() {
            var path = Path()
            path.move(to: mapper.screen(Vec(0, 0)))
            for x in stride(from: 0.0, through: Game.worldSize.x, by: 6) {
                path.addLine(to: mapper.screen(Vec(x, ridgeHeight(x, layer: layer, base: ridge.base, amplitude: ridge.amplitude))))
            }
            path.addLine(to: mapper.screen(Vec(Game.worldSize.x, 0)))
            path.closeSubpath()
            context.fill(path, with: .color(ridge.color))

            if layer == ridges.count - 1 {
                context.fill(treeline(base: ridge.base, amplitude: ridge.amplitude, layer: layer, mapper: mapper), with: .color(ridge.color))
            } else {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [.clear, Color(red: 0.75, green: 0.45, blue: 0.5).opacity(0.16)]),
                    startPoint: mapper.screen(Vec(0, ridge.base + ridge.amplitude)), endPoint: mapper.screen(Vec(0, ridge.base * 0.5))
                ))
            }
        }

        for flock in ambience.flocks {
            drawFlock(flock, in: &context, size: size)
        }
    }

    private func ridgeHeight(_ x: Double, layer: Int, base: Double, amplitude: Double) -> Double {
        let n = BattlefieldView.ridgeNoise.fbm(x * 0.0045 * (1 + Double(layer) * 0.7), Double(layer) * 17.3, octaves: 5)
        let ridged = 1 - abs(n * 2 - 1)
        return base + amplitude * (0.55 * n + 0.45 * ridged)
    }

    private func treeline(base: Double, amplitude: Double, layer: Int, mapper: WorldMapper) -> Path {
        var trees = Path()
        for x in stride(from: 4.0, to: Game.worldSize.x, by: 7) where hash(Int(x), 11) > 0.35 {
            let ground = ridgeHeight(x, layer: layer, base: base, amplitude: amplitude) - 1
            let height = 7 + 13 * hash(Int(x), 12)
            let halfWidth = height * 0.28
            for tier in 0..<3 {
                let bottom = ground + height * Double(tier) * 0.25
                let top = bottom + height * (0.55 - Double(tier) * 0.08)
                let w = halfWidth * (1 - Double(tier) * 0.25)
                trees.move(to: mapper.screen(Vec(x - w, bottom)))
                trees.addLine(to: mapper.screen(Vec(x, top)))
                trees.addLine(to: mapper.screen(Vec(x + w, bottom)))
                trees.closeSubpath()
            }
        }
        return trees
    }

    private func drawMoon(at center: CGPoint, radius r: Double, in context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: CGRect(x: center.x - r * 4, y: center.y - r * 4, width: r * 8, height: r * 8)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.85).opacity(0.22), .clear]),
                                           center: center, startRadius: r, endRadius: r * 4))
        let disc = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: disc), with: .radialGradient(
            Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.9), Color(red: 0.88, green: 0.84, blue: 0.74)]),
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

    private func drawTerrain(_ terrain: Terrain, in context: inout GraphicsContext, mapper: WorldMapper, time: Double, wind: Double) {
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
            context.stroke(path, with: .color(Color(red: 0.2 + 0.35 * t, green: 0.22 + 0.4 * t, blue: 0.14 + 0.2 * t)),
                           style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
        }

        drawGrass(terrain, in: &context, mapper: mapper, time: time, wind: wind)
    }

    private func drawGrass(_ terrain: Terrain, in context: inout GraphicsContext, mapper: WorldMapper, time: Double, wind: Double) {
        let heights = terrain.heights
        var blades = Array(repeating: Path(), count: 3)
        let lean = wind / Game.maxWind
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

    private func drawTank(_ tank: Tank, isCurrent: Bool, in context: inout GraphicsContext, mapper: WorldMapper) {
        let s = mapper.scale
        let base = mapper.screen(tank.position)
        let turret = mapper.screen(tank.turretCenter)
        let facing: Double = tank.angle <= 90 ? 1 : -1
        let paint = tank.isAlive ? tank.color.mix(with: Color(red: 0.32, green: 0.33, blue: 0.27), by: 0.45) : Color(white: 0.16)
        let light = paint.mix(with: .white, by: 0.3)
        let dark = paint.mix(with: .black, by: 0.55)
        func p(_ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: base.x + dx * facing * s, y: base.y - dy * s) }

        context.fill(Path(ellipseIn: CGRect(x: base.x - 17 * s, y: base.y - 2 * s, width: 34 * s, height: 5 * s)), with: .color(.black.opacity(0.45)))

        if isCurrent {
            let glow = 30 * s
            context.fill(Path(ellipseIn: CGRect(x: turret.x - glow, y: turret.y - glow, width: glow * 2, height: glow * 2)),
                         with: .radialGradient(Gradient(colors: [tank.color.opacity(0.3), .clear]), center: turret, startRadius: 0, endRadius: glow))
        }

        let muzzle = mapper.screen(tank.muzzle)
        var barrel = Path()
        barrel.move(to: turret)
        barrel.addLine(to: muzzle)
        context.stroke(barrel, with: .color(dark), style: StrokeStyle(lineWidth: 3.2 * s, lineCap: .butt))
        context.stroke(barrel, with: .color(light.opacity(0.6)), style: StrokeStyle(lineWidth: 1 * s, lineCap: .butt))
        let brake = tank.barrelDirection
        var muzzleBrake = Path()
        muzzleBrake.move(to: mapper.screen(tank.muzzle - brake * 2.5))
        muzzleBrake.addLine(to: muzzle)
        context.stroke(muzzleBrake, with: .color(dark), style: StrokeStyle(lineWidth: 4.6 * s, lineCap: .butt))

        var hull = Path()
        hull.move(to: p(-14, 4))
        hull.addLine(to: p(-12, 9.5))
        hull.addLine(to: p(9, 9.5))
        hull.addLine(to: p(14.5, 5))
        hull.addLine(to: p(14, 4))
        hull.closeSubpath()
        context.fill(hull, with: .linearGradient(Gradient(colors: [light, paint, dark]), startPoint: p(0, 9.5), endPoint: p(0, 4)))
        var deck = Path()
        deck.move(to: p(-12, 9.5))
        deck.addLine(to: p(9, 9.5))
        context.stroke(deck, with: .color(.white.opacity(0.35)), lineWidth: 0.8 * s)

        let track = CGRect(x: base.x - 15 * s, y: base.y - 5 * s, width: 30 * s, height: 5 * s)
        context.fill(Path(roundedRect: track, cornerRadius: 2.5 * s), with: .color(Color(white: 0.1)))
        context.stroke(Path(roundedRect: track.insetBy(dx: 0.5 * s, dy: 0.5 * s), cornerRadius: 2.2 * s),
                       with: .color(Color(white: 0.4).opacity(0.5)), style: StrokeStyle(lineWidth: 0.8 * s, dash: [1.1 * s, 1.1 * s]))
        for i in 0..<6 {
            let wheel = CGPoint(x: track.minX + (3 + Double(i) * 4.8) * s, y: track.midY)
            let r = 1.9 * s
            context.fill(Path(ellipseIn: CGRect(x: wheel.x - r, y: wheel.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.25)]), center: wheel, startRadius: 0, endRadius: r))
        }

        let dome = CGRect(x: turret.x - 7 * s, y: turret.y - 5 * s, width: 14 * s, height: 8 * s)
        context.fill(Path(roundedRect: dome, cornerRadius: 4 * s), with: .linearGradient(
            Gradient(colors: [light, paint, dark]), startPoint: CGPoint(x: dome.midX, y: dome.minY), endPoint: CGPoint(x: dome.midX, y: dome.maxY)))
        context.fill(Path(ellipseIn: CGRect(x: turret.x - (2 + 2.5 * facing) * s, y: turret.y - 6 * s, width: 4 * s, height: 1.8 * s)), with: .color(dark))
        var antenna = Path()
        antenna.move(to: CGPoint(x: turret.x - 5 * facing * s, y: turret.y - 4 * s))
        antenna.addLine(to: CGPoint(x: turret.x - 7 * facing * s, y: turret.y - 15 * s))
        context.stroke(antenna, with: .color(Color(white: 0.2)), lineWidth: 0.6 * s)

        guard tank.isAlive else { return }
        let bar = CGRect(x: base.x - 14 * s, y: turret.y - 24 * s, width: 28 * s, height: 3.5 * s)
        context.fill(Path(roundedRect: bar, cornerRadius: 1.5 * s), with: .color(.black.opacity(0.55)))
        context.fill(Path(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * tank.health / 100, height: bar.height), cornerRadius: 1.5 * s),
                     with: .color(tank.health > 60 ? .green : tank.health > 30 ? .yellow : .red))

        if isCurrent {
            var marker = Path()
            let tip = CGPoint(x: base.x, y: bar.minY - 3 * s)
            marker.move(to: tip)
            marker.addLine(to: CGPoint(x: tip.x - 5 * s, y: tip.y - 7 * s))
            marker.addLine(to: CGPoint(x: tip.x + 5 * s, y: tip.y - 7 * s))
            marker.closeSubpath()
            context.fill(marker, with: .color(.yellow))
        }
    }

    private func drawProjectile(_ projectile: Projectile, in context: inout GraphicsContext, mapper: WorldMapper) {
        let s = mapper.scale
        let points = (projectile.trail + [projectile.position]).map(mapper.screen)
        var trail = Path()
        trail.addLines(points)
        context.stroke(trail, with: .color(.white.opacity(0.12)), lineWidth: max(0.8, 0.8 * s))

        let head = mapper.screen(projectile.position)
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

        if explosion.isDirt {
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

    init(size: CGSize) {
        scale = size.width / Game.worldSize.x
        origin = CGPoint(x: 0, y: size.height)
    }

    func screen(_ p: Vec) -> CGPoint {
        CGPoint(x: origin.x + p.x * scale, y: origin.y - p.y * scale)
    }

    func world(_ p: CGPoint) -> Vec {
        Vec((p.x - origin.x) / scale, (origin.y - p.y) / scale)
    }
}
