import SwiftUI

struct BattlefieldView: View {
    private static let ridgeNoise = ValueNoise(seed: 7)
    /// Direction the moonlight comes from (upper right), used to light slopes.
    private static let moonlight = Vec(0.45, 0.89)

    let game: Game
    /// Follows the action with its own camera (director mode).
    var director: DirectorCamera?
    /// Outlines what `viewport`'s camera is showing (the mini-map).
    var viewport: DirectorCamera?
    /// A second copy of the battlefield on screen; it stays quiet so thunder isn't doubled.
    var isSecondary = false
    /// When set, the view is scaled so this much of the world's height always fits, instead of filling the width.
    var fitHeight: Double?

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
        let leviathan = game.leviathan
        let previewFraction = game.aimPreviewFraction
        let aimPreview = previewFraction > 0 ? game.previewPath(power: game.chargePower ?? game.current.power) : []
        let currentID = game.phase == .aiming ? game.current.id : nil
        let theme = game.theme
        let look = ThemeLook.for(theme)
        let weather = game.weather
        let soil = soils[theme]

        GeometryReader { proxy in
            let mapper = WorldMapper(size: proxy.size, camera: camera, fitHeight: fitHeight)
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let view = camera ?? director?.update(game: game, time: time)
                let mapper = WorldMapper(size: proxy.size, camera: view, fitHeight: fitHeight)
                let _ = director?.record(visible: view == nil ? nil : mapper.visibleWorld(in: proxy.size))
                let blasts = explosions.map { e in
                    let p = mapper.screen(e.center)
                    return Vec(p.x / proxy.size.width, p.y / proxy.size.height)
                }
                let _ = ambience.update(time: time, wind: wind, blasts: blasts, weather: weather, hasUFOs: theme == .moon, onStrike: isSecondary ? {} : game.thunder)
                Canvas { context, size in
                    drawSky(look, weather: weather, in: &context, size: size, mapper: mapper, time: time)
                    // Buried tanks go behind the ground so the dirt covers them.
                    for tank in tanks where tank.isBuried(in: terrain) {
                        drawTank(tank, terrain: terrain, isCurrent: tank.id == currentID, in: &context, mapper: mapper, time: time)
                    }
                    drawTerrain(terrain, look: look, soil: soil, in: &context, mapper: mapper, time: time, wind: wind)
                    for tank in tanks where tank.isBuried(in: terrain) {
                        drawBuriedMarker(tank, terrain: terrain, isCurrent: tank.id == currentID, in: &context, mapper: mapper)
                    }
                    drawTracers(tracers, tanks: tanks, in: &context, mapper: mapper)
                    drawFlames(flames, terrain: terrain, in: &context, mapper: mapper, time: time)
                    drawBeams(game.beams, in: &context, mapper: mapper)
                    if let leviathan {
                        drawLeviathan(leviathan, tanks: tanks, in: &context, mapper: mapper, time: time)
                    }
                    for tank in tanks where !tank.isBuried(in: terrain) {
                        drawTank(tank, terrain: terrain, isCurrent: tank.id == currentID, in: &context, mapper: mapper, time: time)
                    }
                    for turret in turrets {
                        drawFlyingTurret(turret, in: &context, mapper: mapper)
                    }
                    drawAimPreview(aimPreview, fraction: previewFraction, in: &context, mapper: mapper)
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
                    } else if viewport == nil {
                        drawWind(wind, in: &context, size: size)
                    }
                    if let frame = viewport?.visibleWorld {
                        let topLeft = mapper.screen(Vec(frame.minX, frame.maxY))
                        let bottomRight = mapper.screen(Vec(frame.maxX, frame.minY))
                        let box = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
                        context.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(.white.opacity(0.85)), lineWidth: 1.5)
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
        for ufo in ambience.ufos {
            drawUFO(ufo, in: &context, size: size, time: time)
        }

        switch look.celestial {
        case let .moon(tint): drawMoon(at: mapper.screen(Vec(820, 330)), radius: 20 * mapper.scale, tint: tint, in: &context)
        case .sun: drawSun(at: mapper.screen(Vec(240, 235)), radius: 40 * mapper.scale, in: &context)
        case .earth: drawEarth(at: mapper.screen(Vec(790, 315)), radius: 30 * mapper.scale, time: time, in: &context)
        case .ringedPlanet: drawRingedPlanet(at: mapper.screen(Vec(760, 300)), radius: 52 * mapper.scale, in: &context)
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
            let span = mapper.visibleX
            let from = min(0, span.lowerBound), to = max(Game.worldSize.x, span.upperBound)
            var path = Path()
            path.move(to: mapper.screen(Vec(from, -10)))
            for x in stride(from: from, through: to, by: 6) {
                path.addLine(to: mapper.screen(Vec(x, ridgeHeight(x, layer: layer, ridge: ridge, shape: look.ridgeShape))))
            }
            path.addLine(to: mapper.screen(Vec(to, -10)))
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

        if look.hasFloatingBackdrop {
            drawFloatingBackdrop(in: &context, mapper: mapper, time: time)
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
            Gradient(colors: [Color(red: 0.2, green: 0.45, blue: 0.9), Color(red: 0.04, green: 0.12, blue: 0.38)]),
            center: CGPoint(x: center.x - r * 0.35, y: center.y - r * 0.35), startRadius: 0, endRadius: r * 1.5))

        // Orthographic projection of a slowly turning globe, tilted toward us. Each cell of a grid over the disc
        // is traced back to a longitude and latitude and colored from the land map.
        let spin = (time * 4).truncatingRemainder(dividingBy: 360) - 100
        let tilt = 20.0 * .pi / 180
        var surface = context
        surface.clip(to: Path(ellipseIn: disc))
        var land = Path(), ice = Path()
        let cells = 30
        let cell = 2 * r / Double(cells)
        for row in 0..<cells {
            for column in 0..<cells {
                let x = (Double(column) + 0.5) / Double(cells) * 2 - 1
                let y = 1 - (Double(row) + 0.5) / Double(cells) * 2
                let ρ2 = x * x + y * y
                guard ρ2 < 1 else { continue }
                let z = (1 - ρ2).squareRoot()
                let φ = asin(y * cos(tilt) + z * sin(tilt))
                let λ = atan2(x, z * cos(tilt) - y * sin(tilt))
                let lon = λ * 180 / .pi + spin, lat = φ * 180 / .pi
                guard let kind = EarthMap.surface(lon: lon, lat: lat) else { continue }
                let rect = CGRect(x: center.x - r + Double(column) * cell, y: center.y - r + Double(row) * cell, width: cell + 0.6, height: cell + 0.6)
                if kind == .ice { ice.addRect(rect) } else { land.addRect(rect) }
            }
        }
        surface.fill(land, with: .color(Color(red: 0.3, green: 0.56, blue: 0.28)))
        surface.fill(ice, with: .color(Color(white: 0.92)))
        func project(_ lon: Double, _ lat: Double) -> CGPoint {
            let λ = (lon - spin) * .pi / 180, φ = lat * .pi / 180
            let x = cos(φ) * sin(λ)
            let y = cos(tilt) * sin(φ) - sin(tilt) * cos(φ) * cos(λ)
            return CGPoint(x: center.x + x * r, y: center.y - y * r)
        }
        for i in 0..<5 {
            let lon = hash(i, 60) * 360 + time * 6, lat = (hash(i, 61) - 0.5) * 110
            let p = project(lon, lat)
            let facing = sin(tilt) * sin(lat * .pi / 180) + cos(tilt) * cos(lat * .pi / 180) * cos((lon - spin) * .pi / 180)
            guard facing > 0.1 else { continue }
            let cloud = CGRect(x: p.x - r * 0.35, y: p.y - r * 0.06, width: r * 0.7, height: r * 0.12)
            surface.fill(Path(roundedRect: cloud, cornerRadius: r * 0.06), with: .color(.white.opacity(0.65)))
        }
        surface.fill(Path(ellipseIn: disc), with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.6)]),
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

    private func drawUFO(_ ufo: Ambience.UFO, in context: inout GraphicsContext, size: CGSize, time: Double) {
        let bob = sin(ufo.age * 2.6) * 3
        let center = CGPoint(x: ufo.position.x * size.width, y: ufo.position.y * size.height + bob)
        let w = min(max(size.width * 0.045, 22), 46)

        if ufo.beamStrength > 0 {
            var beam = Path()
            let bottom = size.height * 0.95
            beam.move(to: CGPoint(x: center.x - w * 0.18, y: center.y + w * 0.12))
            beam.addLine(to: CGPoint(x: center.x + w * 0.18, y: center.y + w * 0.12))
            beam.addLine(to: CGPoint(x: center.x + w * 0.75, y: bottom))
            beam.addLine(to: CGPoint(x: center.x - w * 0.75, y: bottom))
            beam.closeSubpath()
            var glow = context
            glow.blendMode = .plusLighter
            glow.fill(beam, with: .linearGradient(Gradient(colors: [Color(red: 0.6, green: 1, blue: 0.7).opacity(0.45 * ufo.beamStrength), .clear]),
                                                  startPoint: center, endPoint: CGPoint(x: center.x, y: bottom)))
        }

        var tilted = context
        tilted.translateBy(x: center.x, y: center.y)
        tilted.rotate(by: .degrees(ufo.stage == .leaving ? -12 * ufo.direction : sin(ufo.age * 1.7) * 4))
        let dome = CGRect(x: -w * 0.24, y: -w * 0.32, width: w * 0.48, height: w * 0.4)
        tilted.fill(Path(ellipseIn: dome), with: .linearGradient(Gradient(colors: [Color(red: 0.7, green: 0.95, blue: 1).opacity(0.9), Color(red: 0.2, green: 0.5, blue: 0.7).opacity(0.8)]),
                                                                 startPoint: CGPoint(x: 0, y: dome.minY), endPoint: CGPoint(x: 0, y: dome.maxY)))
        let saucer = CGRect(x: -w / 2, y: -w * 0.1, width: w, height: w * 0.26)
        tilted.fill(Path(ellipseIn: saucer), with: .linearGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.45)]),
                                                                   startPoint: CGPoint(x: 0, y: saucer.minY), endPoint: CGPoint(x: 0, y: saucer.maxY)))
        let colors: [Color] = [.red, .yellow, .green, .cyan, .pink]
        for i in 0..<5 {
            let x = (Double(i) - 2) * w * 0.18
            let lit = Int(time * 6 + Double(i)) % 5 == i
            let r = w * 0.035
            tilted.fill(Path(ellipseIn: CGRect(x: x - r, y: w * 0.02 - r, width: r * 2, height: r * 2)),
                        with: .color(colors[i].opacity(lit ? 1 : 0.45)))
        }
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
        drawUpdrafts(terrain.updrafts, in: &context, mapper: mapper, time: time)
        if terrain.hasAbyss {
            drawCloudSea(in: &context, mapper: mapper, time: time)
        } else {
            drawGround(terrain, look: look, soil: soil, in: &context, mapper: mapper, time: time, wind: wind)
        }
        for island in terrain.islands {
            drawIsland(island, look: look, soil: soil, in: &context, mapper: mapper, time: time, wind: wind)
        }
    }

    private func drawGround(_ terrain: Terrain, look: ThemeLook, soil: Image?, in context: inout GraphicsContext, mapper: WorldMapper, time: Double, wind: Double) {
        let s = mapper.scale
        let heights = terrain.heights
        let last = terrain.width - 1

        // Past the world's edges (when letterboxed) the ground carries on level, so there are no bare strips.
        let leftEdge = min(0, mapper.visibleX.lowerBound - 10), rightEdge = max(Double(last), mapper.visibleX.upperBound + 10)
        var surface = Path()
        surface.move(to: mapper.screen(Vec(leftEdge, heights[0])))
        surface.addLine(to: mapper.screen(Vec(0, heights[0])))
        for x in stride(from: 2, to: terrain.width, by: 2) {
            surface.addLine(to: mapper.screen(Vec(Double(x), heights[x])))
        }
        surface.addLine(to: mapper.screen(Vec(Double(last), heights[last])))
        surface.addLine(to: mapper.screen(Vec(rightEdge, heights[last])))

        var groundPath = surface
        // Well below the bottom so the ground never ends inside the view, even mid-resize.
        groundPath.addLine(to: mapper.screen(Vec(rightEdge, -2_000)))
        groundPath.addLine(to: mapper.screen(Vec(leftEdge, -2_000)))
        groundPath.closeSubpath()

        var ground = context
        ground.clip(to: groundPath)
        let worldRect = CGRect(origin: mapper.screen(Vec(0, Game.worldSize.y)), size: CGSize(width: Game.worldSize.x * s, height: Game.worldSize.y * s))
        ground.fill(groundPath, with: .color(look.ridges.last?.color.mix(with: Color(red: 0.4, green: 0.28, blue: 0.16), by: 0.6) ?? .brown))
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

    // MARK: Floating isles

    private func drawIsland(_ island: Island, look: ThemeLook, soil: Image?, in context: inout GraphicsContext, mapper: WorldMapper, time: Double, wind: Double) {
        let s = mapper.scale
        let columns = Array(stride(from: 0, to: island.width, by: 2)) + [island.width - 1]
        let solid = columns.filter { island.tops[$0] > island.bottoms[$0] }
        guard let first = solid.first else { return }

        // Outline: along the top left to right, back along the underside, splitting into pieces wherever rock is missing.
        var shape = Path()
        var piece: [Int] = []
        func closePiece() {
            guard piece.count > 1 else { piece = []; return }
            shape.move(to: mapper.screen(island.offset + Vec(Double(piece[0]), island.tops[piece[0]])))
            for c in piece.dropFirst() { shape.addLine(to: mapper.screen(island.offset + Vec(Double(c), island.tops[c]))) }
            for c in piece.reversed() { shape.addLine(to: mapper.screen(island.offset + Vec(Double(c), island.bottoms[c]))) }
            shape.closeSubpath()
            piece = []
        }
        for c in columns {
            if island.tops[c] > island.bottoms[c] { piece.append(c) } else { closePiece() }
        }
        closePiece()

        var rock = context
        rock.clip(to: shape)
        let drift = island.offset - island.home
        let worldRect = CGRect(origin: mapper.screen(Vec(drift.x, Game.worldSize.y + drift.y)),
                               size: CGSize(width: Game.worldSize.x * s, height: Game.worldSize.y * s))
        rock.fill(shape, with: .color(Color(red: 0.36, green: 0.28, blue: 0.26)))
        if let soil { rock.draw(soil, in: worldRect) }
        let topY = island.offset.y + (island.tops.max() ?? 0), bottomY = island.offset.y + (island.bottoms.min() ?? 0)
        rock.fill(shape, with: .linearGradient(Gradient(colors: [.clear, Color(red: 0.12, green: 0.06, blue: 0.2).opacity(0.85)]),
                                               startPoint: mapper.screen(Vec(0, topY - 6)), endPoint: mapper.screen(Vec(0, bottomY))))

        // Vines and glowing pods hanging from the underside.
        var vines = Path()
        var glow = context
        glow.blendMode = .plusLighter
        for c in stride(from: first + 4, to: island.width - 4, by: 7) where island.tops[c] > island.bottoms[c] && hash(c + island.id * 97, 70) > 0.3 {
            let root = island.offset + Vec(Double(c), island.bottoms[c] + 1)
            let length = 8 + 26 * hash(c + island.id * 97, 71)
            let sway = sin(time * 1.3 + Double(c) * 0.4) * 2.5
            let tip = root + Vec(sway, -length)
            vines.move(to: mapper.screen(root))
            vines.addQuadCurve(to: mapper.screen(tip), control: mapper.screen(root + Vec(-sway, -length * 0.5)))
            if hash(c + island.id * 97, 72) > 0.55 {
                let p = mapper.screen(tip)
                let r = (2.2 + sin(time * 2 + Double(c)) * 0.5) * s
                glow.fill(Path(ellipseIn: CGRect(x: p.x - r * 3, y: p.y - r * 3, width: r * 6, height: r * 6)),
                          with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 1, blue: 0.9).opacity(0.7), .clear]), center: p, startRadius: 0, endRadius: r * 3))
            }
        }
        context.stroke(vines, with: .color(Color(red: 0.2, green: 0.45, blue: 0.35).opacity(0.85)), style: StrokeStyle(lineWidth: 1.1 * s, lineCap: .round))

        // Grassy rim and blades along the top.
        var rim = Path(), bare = Path()
        var blades = Path()
        let lean = wind / Game.windReference
        for c in solid.dropLast() {
            let next = min(c + 2, island.width - 1)
            guard island.tops[next] > island.bottoms[next] else { continue }
            let a = island.offset + Vec(Double(c), island.tops[c]), b = island.offset + Vec(Double(next), island.tops[next])
            if island.grass[c] < 0.3 {
                bare.move(to: mapper.screen(a))
                bare.addLine(to: mapper.screen(b))
                continue
            }
            rim.move(to: mapper.screen(a))
            rim.addLine(to: mapper.screen(b))
            guard hash(c + island.id * 31, 21) < island.grass[c] else { continue }
            let length = 2.5 + 4 * hash(c + island.id * 31, 30)
            let bend = lean * 0.9 + sin(time * 2.2 + a.x * 0.07) * 0.35
            blades.move(to: mapper.screen(a))
            blades.addQuadCurve(to: mapper.screen(a + Vec(bend * length * 0.45, length)), control: mapper.screen(a + Vec(bend * length * 0.1, length * 0.6)))
        }
        context.stroke(bare, with: .color(Color(red: 0.16, green: 0.12, blue: 0.1)), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
        context.stroke(rim, with: .color(Color(red: 0.35, green: 0.72, blue: 0.42)), style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round))
        context.stroke(blades, with: .color(Color(red: 0.42, green: 0.82, blue: 0.5)), style: StrokeStyle(lineWidth: max(0.6, 0.9 * s), lineCap: .round))
    }

    private func drawCloudSea(in context: inout GraphicsContext, mapper: WorldMapper, time: Double) {
        let span = mapper.visibleX
        let surface = mapper.screen(Vec(0, 34)).y
        let bottom = mapper.screen(Vec(0, -400)).y
        context.fill(Path(CGRect(x: 0, y: surface, width: mapper.viewWidth, height: bottom - surface)), with: .linearGradient(
            Gradient(colors: [Color(red: 0.96, green: 0.86, blue: 0.94), Color(red: 0.72, green: 0.62, blue: 0.86)]),
            startPoint: CGPoint(x: 0, y: surface), endPoint: CGPoint(x: 0, y: surface + 60 * mapper.scale)))
        for layer in 0..<2 {
            for i in 0..<16 {
                let speed = layer == 0 ? 5.0 : 9.0
                let wrapped = (hash(i, 80 + layer) * 1_200 + time * speed).truncatingRemainder(dividingBy: 1_200) - 100
                let x = span.lowerBound + wrapped / 1_200 * (span.upperBound - span.lowerBound + 200)
                let y = 26 + hash(i, 82 + layer) * 18 - Double(layer) * 10
                let r = 26 + hash(i, 84 + layer) * 30
                let center = mapper.screen(Vec(x, y))
                let radius = r * mapper.scale
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.55, width: radius * 2, height: radius * 1.1)),
                             with: .radialGradient(Gradient(colors: [Color.white.opacity(layer == 0 ? 0.8 : 0.95), Color.white.opacity(0)]),
                                                   center: center, startRadius: 0, endRadius: radius))
            }
        }
    }

    private func drawUpdrafts(_ updrafts: [Updraft], in context: inout GraphicsContext, mapper: WorldMapper, time: Double) {
        for draft in updrafts {
            let left = mapper.screen(Vec(draft.x.lowerBound, 0)), right = mapper.screen(Vec(draft.x.upperBound, 0))
            let top = mapper.screen(Vec(0, Game.worldSize.y * 1.2)).y
            let column = CGRect(x: left.x, y: top, width: right.x - left.x, height: left.y - top)
            context.fill(Path(column), with: .linearGradient(Gradient(colors: [.clear, Color(red: 0.7, green: 0.95, blue: 1).opacity(0.12), .clear]),
                                                            startPoint: CGPoint(x: column.minX, y: 0), endPoint: CGPoint(x: column.maxX, y: 0)))
            var streaks = Path()
            for k in 0..<14 {
                let x = draft.x.lowerBound + hash(k, 90) * (draft.x.upperBound - draft.x.lowerBound)
                let y = (time * 70 + hash(k, 91) * 420).truncatingRemainder(dividingBy: 420)
                streaks.move(to: mapper.screen(Vec(x, y)))
                streaks.addLine(to: mapper.screen(Vec(x, y + 14)))
            }
            context.stroke(streaks, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: max(1, mapper.scale), lineCap: .round))
        }
    }

    private func drawFloatingBackdrop(in context: inout GraphicsContext, mapper: WorldMapper, time: Double) {
        for i in 0..<6 {
            let x = hash(i, 100) * Game.worldSize.x
            let y = 210 + hash(i, 101) * 140 + sin(time * 0.4 + Double(i)) * 3
            let w = 26 + hash(i, 102) * 50
            var shape = Path()
            shape.move(to: mapper.screen(Vec(x - w / 2, y)))
            shape.addQuadCurve(to: mapper.screen(Vec(x + w / 2, y)), control: mapper.screen(Vec(x, y + 6)))
            shape.addQuadCurve(to: mapper.screen(Vec(x - w / 2, y)), control: mapper.screen(Vec(x, y - w * 0.9)))
            context.fill(shape, with: .color(Color(red: 0.32, green: 0.38, blue: 0.56).opacity(0.55)))
        }
    }

    private func drawRingedPlanet(at center: CGPoint, radius r: Double, in context: inout GraphicsContext) {
        let tilt = Angle.degrees(-16)
        var back = context
        back.translateBy(x: center.x, y: center.y)
        back.rotate(by: tilt)
        let ring = CGRect(x: -r * 1.9, y: -r * 0.42, width: r * 3.8, height: r * 0.84)
        back.stroke(Path(ellipseIn: ring), with: .color(Color(red: 0.95, green: 0.85, blue: 0.75).opacity(0.5)), lineWidth: r * 0.12)
        context.fill(Path(ellipseIn: CGRect(x: center.x - r * 2, y: center.y - r * 2, width: r * 4, height: r * 4)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.9, green: 0.7, blue: 0.8).opacity(0.25), .clear]), center: center, startRadius: r, endRadius: r * 2))
        let disc = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: disc), with: .linearGradient(
            Gradient(colors: [Color(red: 0.98, green: 0.82, blue: 0.7), Color(red: 0.85, green: 0.55, blue: 0.62), Color(red: 0.45, green: 0.3, blue: 0.55)]),
            startPoint: CGPoint(x: disc.minX, y: disc.minY), endPoint: CGPoint(x: disc.maxX, y: disc.maxY)))
        var bands = context
        bands.clip(to: Path(ellipseIn: disc))
        for i in 0..<5 {
            let y = disc.minY + r * (0.35 + Double(i) * 0.35)
            bands.fill(Path(CGRect(x: disc.minX, y: y, width: disc.width, height: r * 0.09)), with: .color(.white.opacity(0.12)))
        }
        var front = context
        front.translateBy(x: center.x, y: center.y)
        front.rotate(by: tilt)
        front.clip(to: Path(CGRect(x: -r * 2, y: 0, width: r * 4, height: r)))
        front.stroke(Path(ellipseIn: ring), with: .color(Color(red: 0.98, green: 0.9, blue: 0.8).opacity(0.75)), lineWidth: r * 0.12)
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
        switch tank.kind {
        case .bastion: return drawBastion(tank, isCurrent: isCurrent, in: &context, mapper: mapper, time: time)
        case .pod: return drawPod(tank, isCurrent: isCurrent, in: &context, mapper: mapper, time: time)
        case .standard: break
        }
        let s = mapper.scale
        let ground = mapper.screen(tank.position)
        let probe = tank.position.y + 4
        let slope = tank.isAnchored ? 0 : atan((terrain.support(at: tank.position.x + 8, y: probe) - terrain.support(at: tank.position.x - 8, y: probe)) / 16)
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

    /// Shows where a buried tank is: a dashed outline through the dirt, its health and a tag at the surface.
    private func drawBuriedMarker(_ tank: Tank, terrain: Terrain, isCurrent: Bool, in context: inout GraphicsContext, mapper: WorldMapper) {
        let s = mapper.scale
        let base = mapper.screen(tank.position)
        let outline = CGRect(x: base.x - 15 * s, y: base.y - 16 * s, width: 30 * s, height: 16 * s)
        context.stroke(Path(roundedRect: outline, cornerRadius: 5 * s), with: .color(tank.color.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.2 * s, dash: [3 * s, 2 * s]))
        guard tank.isAlive else { return }
        let surface = mapper.screen(Vec(tank.position.x, terrain.support(at: tank.position.x, y: tank.position.y)))
        let bar = CGRect(x: surface.x - 14 * s, y: surface.y - 12 * s, width: 28 * s, height: 3.5 * s)
        context.fill(Path(roundedRect: bar, cornerRadius: 1.5 * s), with: .color(.black.opacity(0.55)))
        context.fill(Path(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * tank.health / 100, height: bar.height), cornerRadius: 1.5 * s),
                     with: .color(tank.health > 60 ? .green : tank.health > 30 ? .yellow : .red))
        let label = Text("BURIED")
            .font(.system(size: max(9, 9 * s), weight: .heavy, design: .rounded))
            .foregroundStyle(isCurrent ? Color.yellow : tank.color)
        context.draw(label, at: CGPoint(x: surface.x, y: bar.minY - 7 * s))
    }

    // MARK: Bosses

    private func drawHealthBar(for tank: Tank, at point: CGPoint, width: Double, in context: inout GraphicsContext, scale s: Double) {
        let bar = CGRect(x: point.x - width / 2 * s, y: point.y, width: width * s, height: 4 * s)
        context.fill(Path(roundedRect: bar, cornerRadius: 2 * s), with: .color(.black.opacity(0.55)))
        context.fill(Path(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * tank.healthFraction, height: bar.height), cornerRadius: 2 * s),
                     with: .color(tank.healthFraction > 0.6 ? .green : tank.healthFraction > 0.3 ? .yellow : .red))
        if tank.shield > 0 {
            let shieldBar = CGRect(x: bar.minX, y: bar.minY - 5 * s, width: bar.width * min(1, tank.shield / tank.shieldCap), height: 3 * s)
            context.fill(Path(roundedRect: shieldBar, cornerRadius: 1.5 * s), with: .color(.cyan))
        }
    }

    private func drawBastion(_ tank: Tank, isCurrent: Bool, in context: inout GraphicsContext, mapper: WorldMapper, time: Double) {
        let s = mapper.scale
        let base = mapper.screen(tank.position)
        func p(_ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: base.x + dx * s, y: base.y - dy * s) }
        let concrete = tank.isAlive ? Color(red: 0.56, green: 0.56, blue: 0.52) : Color(red: 0.3, green: 0.27, blue: 0.24)

        context.fill(Path(ellipseIn: CGRect(x: base.x - 40 * s, y: base.y - 3 * s, width: 80 * s, height: 7 * s)), with: .color(.black.opacity(0.45)))
        var bunker = Path()
        bunker.move(to: p(-36, 0))
        bunker.addLine(to: p(-28, 26))
        bunker.addLine(to: p(28, 26))
        bunker.addLine(to: p(36, 0))
        bunker.closeSubpath()
        context.fill(bunker, with: .linearGradient(Gradient(colors: [concrete.mix(with: .white, by: 0.2), concrete, concrete.mix(with: .black, by: 0.45)]),
                                                   startPoint: p(0, 26), endPoint: p(0, 0)))
        var seams = Path()
        for dy in [8.0, 17.0] {
            seams.move(to: p(-34 + dy * 0.3, dy))
            seams.addLine(to: p(34 - dy * 0.3, dy))
        }
        context.stroke(seams, with: .color(.black.opacity(0.25)), lineWidth: 0.8 * s)
        context.fill(Path(roundedRect: CGRect(origin: p(-18, 15), size: CGSize(width: 36 * s, height: 4 * s)), cornerRadius: 1 * s), with: .color(.black.opacity(0.8)))
        if tank.isAlive {
            var glow = context
            glow.blendMode = .plusLighter
            glow.fill(Path(roundedRect: CGRect(origin: p(-16, 14.5), size: CGSize(width: 32 * s, height: 2.5 * s)), cornerRadius: 1 * s),
                      with: .color(Color.red.opacity(0.5 + 0.3 * sin(time * 3))))
        }
        let turret = mapper.screen(tank.turretCenter)
        if tank.hasTurret {
            var barrel = Path()
            barrel.move(to: turret)
            barrel.addLine(to: mapper.screen(tank.muzzle))
            context.stroke(barrel, with: .color(Color(white: 0.2)), style: StrokeStyle(lineWidth: 6 * s, lineCap: .butt))
            context.fill(Path(ellipseIn: CGRect(x: turret.x - 12 * s, y: turret.y - 9 * s, width: 24 * s, height: 18 * s)),
                         with: .linearGradient(Gradient(colors: [concrete.mix(with: .white, by: 0.25), concrete.mix(with: .black, by: 0.3)]),
                                               startPoint: CGPoint(x: turret.x, y: turret.y - 9 * s), endPoint: CGPoint(x: turret.x, y: turret.y + 9 * s)))
        }
        guard tank.isAlive else { return }
        if tank.shield > 0 {
            let r = 44 * s
            var dome = context
            dome.blendMode = .plusLighter
            let rect = CGRect(x: base.x - r, y: base.y - r, width: r * 2, height: r * 2)
            dome.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [.clear, .cyan.opacity(0.1), .cyan.opacity(0.35 * tank.shield / tank.shieldCap)]), center: base, startRadius: 0, endRadius: r))
            dome.stroke(Path(ellipseIn: rect), with: .color(.cyan.opacity(0.6)), lineWidth: 1.2 * s)
        }
        drawHealthBar(for: tank, at: p(0, 56), width: 60, in: &context, scale: s)
        if isCurrent { drawTurnMarker(at: p(0, 66), scale: s, in: &context) }
    }

    private func drawPod(_ tank: Tank, isCurrent: Bool, in context: inout GraphicsContext, mapper: WorldMapper, time: Double) {
        let s = mapper.scale
        let center = mapper.screen(tank.position)
        let shell = tank.isAlive ? Color(red: 0.25, green: 0.4, blue: 0.45) : Color(red: 0.2, green: 0.18, blue: 0.18)
        if tank.isAlive {
            var barrel = Path()
            barrel.move(to: center)
            barrel.addLine(to: mapper.screen(tank.muzzle))
            context.stroke(barrel, with: .color(Color(white: 0.2)), style: StrokeStyle(lineWidth: 3.5 * s, lineCap: .butt))
        }
        let r = 11 * s
        context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r * 0.8, width: r * 2, height: r * 1.6)),
                     with: .linearGradient(Gradient(colors: [shell.mix(with: .white, by: 0.3), shell.mix(with: .black, by: 0.4)]),
                                           startPoint: CGPoint(x: center.x, y: center.y - r), endPoint: CGPoint(x: center.x, y: center.y + r)))
        guard tank.isAlive else { return }
        var glow = context
        glow.blendMode = .plusLighter
        let eye = 3.5 * s * (1 + 0.15 * sin(time * 4 + tank.position.x))
        glow.fill(Path(ellipseIn: CGRect(x: center.x - eye, y: center.y - eye, width: eye * 2, height: eye * 2)),
                  with: .radialGradient(Gradient(colors: [.white, tank.color, .clear]), center: center, startRadius: 0, endRadius: eye * 2))
        drawHealthBar(for: tank, at: CGPoint(x: center.x, y: center.y - 22 * s), width: 26, in: &context, scale: s)
        if isCurrent { drawTurnMarker(at: CGPoint(x: center.x, y: center.y - 26 * s), scale: s, in: &context) }
    }

    private func drawTurnMarker(at tip: CGPoint, scale s: Double, in context: inout GraphicsContext) {
        var marker = Path()
        marker.move(to: tip)
        marker.addLine(to: CGPoint(x: tip.x - 5 * s, y: tip.y - 7 * s))
        marker.addLine(to: CGPoint(x: tip.x + 5 * s, y: tip.y - 7 * s))
        marker.closeSubpath()
        context.fill(marker, with: .color(.yellow))
    }

    /// A great ray-like creature with glowing markings; it sags and dims as its pods are destroyed.
    private func drawLeviathan(_ flight: LeviathanFlight, tanks: [Tank], in context: inout GraphicsContext, mapper: WorldMapper, time: Double) {
        let s = mapper.scale
        let pods = flight.pods.compactMap { tanks.indices.contains($0.index) ? tanks[$0.index] : nil }
        let strength = pods.isEmpty ? 0 : Double(pods.filter(\.isAlive).count) / Double(pods.count)
        let flap = sin(time * 1.6) * 10 * (0.4 + 0.6 * strength)
        let c = flight.center + Vec(0, -6 - 30 * (1 - strength))
        func p(_ dx: Double, _ dy: Double) -> CGPoint { mapper.screen(c + Vec(dx, dy)) }

        var body = Path()
        body.move(to: p(-150, flap + 4))
        body.addQuadCurve(to: p(0, 14), control: p(-80, 28 + flap * 0.5))
        body.addQuadCurve(to: p(150, flap + 4), control: p(80, 28 + flap * 0.5))
        body.addQuadCurve(to: p(30, -14), control: p(90, -16 + flap * 0.3))
        body.addQuadCurve(to: p(-30, -14), control: p(0, -22))
        body.addQuadCurve(to: p(-150, flap + 4), control: p(-90, -16 + flap * 0.3))
        body.closeSubpath()
        let skin = Color(red: 0.1, green: 0.16, blue: 0.3).mix(with: .gray, by: 0.5 * (1 - strength))
        context.fill(body, with: .linearGradient(Gradient(colors: [skin.mix(with: .white, by: 0.2), skin, skin.mix(with: .black, by: 0.5)]),
                                                 startPoint: p(0, 26), endPoint: p(0, -20)))
        var tail = Path()
        tail.move(to: p(-10, -14))
        tail.addQuadCurve(to: p(sin(time * 1.2) * 30, -90), control: p(-20, -50))
        tail.addQuadCurve(to: p(10, -14), control: p(20, -50))
        context.fill(tail, with: .color(skin.mix(with: .black, by: 0.3)))

        var glow = context
        glow.blendMode = .plusLighter
        for i in 0..<9 {
            let side = i % 2 == 0 ? -1.0 : 1.0
            let dx = side * (20 + Double(i / 2) * 26)
            let point = p(dx, 8 + flap * Double(i / 2) / 6)
            let r = (2.4 + sin(time * 2 + Double(i)) * 0.6) * s
            glow.fill(Path(ellipseIn: CGRect(x: point.x - r * 2.5, y: point.y - r * 2.5, width: r * 5, height: r * 5)),
                      with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 1, blue: 0.9).opacity(0.8 * max(strength, 0.15)), .clear]),
                                            center: point, startRadius: 0, endRadius: r * 2.5))
        }
        let eye = p(0, -8)
        let eyeR = 4 * s
        glow.fill(Path(ellipseIn: CGRect(x: eye.x - eyeR, y: eye.y - eyeR, width: eyeR * 2, height: eyeR * 2)),
                  with: .color(Color(red: 1, green: 0.5, blue: 0.3).opacity(0.4 + 0.6 * strength)))
    }

    private func drawAimPreview(_ path: [Vec], fraction: Double, in context: inout GraphicsContext, mapper: WorldMapper) {
        guard fraction > 0, path.count > 1 else { return }
        let shown = max(2, Int(Double(path.count) * fraction))
        for (i, point) in path.prefix(shown).enumerated() where i % 2 == 0 {
            let p = mapper.screen(point)
            let fade = 1 - Double(i) / Double(shown)
            let r = max(1.2, 1.8 * mapper.scale)
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.75 * fade)))
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
            let base = mapper.screen(Vec(flame.x, flame.y + 2))
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
    let viewWidth: Double

    /// World x coordinates at the left and right edges of the view, which can lie beyond the world when it's letterboxed.
    var visibleX: ClosedRange<Double> {
        ((0 - origin.x) / scale)...((viewWidth - origin.x) / scale)
    }

    init(size: CGSize, camera: Camera? = nil, fitHeight: Double? = nil) {
        viewWidth = size.width
        var fit = size.width / Game.worldSize.x
        if let fitHeight { fit = min(fit, size.height / fitHeight) }
        guard let camera else {
            scale = fit
            origin = CGPoint(x: (size.width - Game.worldSize.x * fit) / 2, y: size.height)
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

    /// The part of the world showing in a view of this size.
    func visibleWorld(in size: CGSize) -> CGRect {
        let topLeft = world(.zero), bottomRight = world(CGPoint(x: size.width, y: size.height))
        return CGRect(x: topLeft.x, y: bottomRight.y, width: bottomRight.x - topLeft.x, height: topLeft.y - bottomRight.y)
    }
}
