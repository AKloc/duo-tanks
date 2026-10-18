import SwiftUI

struct BattlefieldView: View {
    let game: Game

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
            Canvas { context, size in
                drawSky(in: &context, size: size, mapper: mapper)
                drawTerrain(terrain, in: &context, mapper: mapper)
                for tank in tanks {
                    drawTank(tank, isCurrent: tank.id == currentID, in: &context, mapper: mapper)
                }
                drawParticles(particles.filter { $0.kind == .smoke }, in: &context, mapper: mapper)
                for explosion in explosions {
                    drawExplosion(explosion, in: &context, mapper: mapper)
                }
                drawParticles(particles.filter { $0.kind != .smoke }, in: &context, mapper: mapper)
                for projectile in projectiles {
                    drawProjectile(projectile, in: &context, mapper: mapper)
                }
                for text in floatingTexts {
                    drawFloatingText(text, in: &context, mapper: mapper)
                }
                drawWind(wind, in: &context, size: size)
                if flash > 0.01 {
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flash * 0.8)))
                }
            }
            .offset(x: Double.random(in: -1...1) * shake * 9, y: Double.random(in: -1...1) * shake * 9)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard game.phase == .aiming else { return }
                let delta = mapper.world(value.location) - game.current.turretCenter
                game.setAngle(atan2(max(delta.y, 0), delta.x) * 180 / .pi)
            })
        }
        .background(Color(red: 0.05, green: 0.06, blue: 0.2))
        .clipped()
    }

    // MARK: Scenery

    private func drawSky(in context: inout GraphicsContext, size: CGSize, mapper: WorldMapper) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.04, green: 0.05, blue: 0.2),
                Color(red: 0.2, green: 0.12, blue: 0.38),
                Color(red: 0.75, green: 0.35, blue: 0.4),
            ]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
        ))

        for i in 0..<90 {
            let point = CGPoint(x: hash(i, 1) * size.width, y: hash(i, 2) * hash(i, 3) * size.height * 0.75)
            let r = 0.4 + hash(i, 4) * 1.1
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.3 + hash(i, 5) * 0.6)))
        }

        let moon = mapper.screen(Vec(820, 330))
        let moonRadius = 22 * mapper.scale
        context.fill(Path(ellipseIn: CGRect(x: moon.x - moonRadius * 3, y: moon.y - moonRadius * 3, width: moonRadius * 6, height: moonRadius * 6)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.25), .clear]), center: moon, startRadius: moonRadius, endRadius: moonRadius * 3))
        context.fill(Path(ellipseIn: CGRect(x: moon.x - moonRadius, y: moon.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)),
                     with: .color(Color(red: 1, green: 0.96, blue: 0.85)))

        for (layer, color) in [(0, Color(red: 0.22, green: 0.14, blue: 0.35)), (1, Color(red: 0.15, green: 0.1, blue: 0.28))] {
            var ridge = Path()
            ridge.move(to: mapper.screen(Vec(0, 0)))
            for x in stride(from: 0.0, through: Game.worldSize.x, by: 10) {
                let t = x / Game.worldSize.x * 2 * .pi
                let base = layer == 0 ? 210.0 : 160.0
                let h = base + 40 * sin(t * (2 + Double(layer)) + Double(layer)) + 22 * sin(t * 5.3 + 1.7 * Double(layer))
                ridge.addLine(to: mapper.screen(Vec(x, h)))
            }
            ridge.addLine(to: mapper.screen(Vec(Game.worldSize.x, 0)))
            ridge.closeSubpath()
            context.fill(ridge, with: .color(color))
        }
    }

    private func drawTerrain(_ terrain: Terrain, in context: inout GraphicsContext, mapper: WorldMapper) {
        var surface = Path()
        surface.move(to: mapper.screen(Vec(0, terrain.heights[0])))
        for x in stride(from: 2, to: terrain.width, by: 2) {
            surface.addLine(to: mapper.screen(Vec(Double(x), terrain.heights[x])))
        }
        surface.addLine(to: mapper.screen(Vec(Double(terrain.width - 1), terrain.heights[terrain.width - 1])))

        var ground = surface
        ground.addLine(to: mapper.screen(Vec(Double(terrain.width - 1), 0)))
        ground.addLine(to: mapper.screen(Vec(0, 0)))
        ground.closeSubpath()
        context.fill(ground, with: .linearGradient(
            Gradient(colors: [Color(red: 0.55, green: 0.38, blue: 0.2), Color(red: 0.3, green: 0.18, blue: 0.1)]),
            startPoint: mapper.screen(Vec(0, terrain.maxHeight * 0.7)), endPoint: mapper.screen(Vec(0, 0))
        ))
        context.stroke(surface, with: .color(Color(red: 0.35, green: 0.75, blue: 0.3)), style: StrokeStyle(lineWidth: 3 * mapper.scale, lineCap: .round, lineJoin: .round))
    }

    // MARK: Actors

    private func drawTank(_ tank: Tank, isCurrent: Bool, in context: inout GraphicsContext, mapper: WorldMapper) {
        let s = mapper.scale
        let color = tank.isAlive ? tank.color : Color(white: 0.25)
        let turret = mapper.screen(tank.turretCenter)
        let base = mapper.screen(tank.position)

        if isCurrent {
            let glow = 26 * s
            context.fill(Path(ellipseIn: CGRect(x: turret.x - glow, y: turret.y - glow, width: glow * 2, height: glow * 2)),
                         with: .radialGradient(Gradient(colors: [tank.color.opacity(0.45), .clear]), center: turret, startRadius: 0, endRadius: glow))
        }

        var barrel = Path()
        barrel.move(to: turret)
        barrel.addLine(to: mapper.screen(tank.muzzle))
        context.stroke(barrel, with: .color(Color(white: 0.85)), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))

        context.fill(Path(ellipseIn: CGRect(x: turret.x - 6 * s, y: turret.y - 6 * s, width: 12 * s, height: 12 * s)), with: .color(color))

        var hull = Path()
        hull.move(to: CGPoint(x: base.x - 12 * s, y: base.y - 3 * s))
        hull.addLine(to: CGPoint(x: base.x - 9 * s, y: base.y - Tank.bodyHeight * s - 1 * s))
        hull.addLine(to: CGPoint(x: base.x + 9 * s, y: base.y - Tank.bodyHeight * s - 1 * s))
        hull.addLine(to: CGPoint(x: base.x + 12 * s, y: base.y - 3 * s))
        hull.closeSubpath()
        context.fill(hull, with: .linearGradient(Gradient(colors: [color.opacity(0.95), color.mix(with: .black, by: 0.45)]),
                                                 startPoint: CGPoint(x: base.x, y: base.y - 9 * s), endPoint: CGPoint(x: base.x, y: base.y)))

        let tread = CGRect(x: base.x - 12 * s, y: base.y - 4 * s, width: 24 * s, height: 4 * s)
        context.fill(Path(roundedRect: tread, cornerRadius: 2 * s), with: .color(Color(white: 0.15)))
        for i in 0..<5 {
            let wheel = CGPoint(x: tread.minX + (2.4 + Double(i) * 4.8) * s, y: tread.midY)
            context.fill(Path(ellipseIn: CGRect(x: wheel.x - 1.3 * s, y: wheel.y - 1.3 * s, width: 2.6 * s, height: 2.6 * s)), with: .color(Color(white: 0.5)))
        }

        guard tank.isAlive else { return }
        let bar = CGRect(x: base.x - 14 * s, y: turret.y - 22 * s, width: 28 * s, height: 3.5 * s)
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
        let points = (projectile.trail + [projectile.position]).map(mapper.screen)
        if points.count > 1 {
            for i in 1..<points.count {
                var segment = Path()
                segment.move(to: points[i - 1])
                segment.addLine(to: points[i])
                let t = Double(i) / Double(points.count)
                context.stroke(segment, with: .color(Color(red: 1, green: 0.85, blue: 0.6).opacity(t * 0.6)),
                               style: StrokeStyle(lineWidth: max(1, mapper.scale * 2 * t), lineCap: .round))
            }
        }
        let head = mapper.screen(projectile.position)
        let glow = 9 * mapper.scale
        context.fill(Path(ellipseIn: CGRect(x: head.x - glow, y: head.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [.orange.opacity(0.8), .clear]), center: head, startRadius: 0, endRadius: glow))
        let r = 2.5 * mapper.scale
        context.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)), with: .color(.white))
    }

    private func drawExplosion(_ explosion: Explosion, in context: inout GraphicsContext, mapper: WorldMapper) {
        let center = mapper.screen(explosion.center)
        let t = explosion.progress
        let fade = 1 - t

        if explosion.isDirt {
            let r = explosion.radius * mapper.scale * (0.5 + 0.5 * t)
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                         with: .color(Color(red: 0.45, green: 0.3, blue: 0.15).opacity(fade * 0.6)))
            return
        }

        let ring = explosion.radius * mapper.scale * (0.6 + 1.2 * t)
        context.stroke(Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)),
                       with: .color(.white.opacity(fade * 0.5)), lineWidth: max(1, 3 * mapper.scale * fade))

        let r = explosion.radius * mapper.scale * (0.35 + 0.75 * min(t * 3, 1))
        var glowContext = context
        glowContext.blendMode = .plusLighter
        glowContext.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
            Gradient(colors: [.white.opacity(fade), .yellow.opacity(fade), .orange.opacity(fade * 0.85), .red.opacity(fade * 0.4), .clear]),
            center: center, startRadius: 0, endRadius: r
        ))
    }

    private func drawParticles(_ particles: [Particle], in context: inout GraphicsContext, mapper: WorldMapper) {
        var sparkContext = context
        sparkContext.blendMode = .plusLighter
        for p in particles {
            let point = mapper.screen(p.position)
            let fade = 1 - p.progress
            switch p.kind {
            case .spark:
                let r = p.size * mapper.scale
                sparkContext.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .color(p.color.opacity(fade)))
            case .debris:
                let r = p.size * mapper.scale
                context.fill(Path(CGRect(x: point.x - r / 2, y: point.y - r / 2, width: r, height: r)), with: .color(p.color.opacity(min(1, fade * 2))))
            case .smoke:
                let r = p.size * mapper.scale * (0.6 + p.progress)
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .color(p.color.opacity(fade * 0.35)))
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

    private func drawWind(_ wind: Double, in context: inout GraphicsContext, size: CGSize) {
        let arrow = wind == 0 ? "–" : (wind > 0 ? "→" : "←")
        let text = Text("Wind \(arrow) \(Int(abs(wind)))")
            .font(.caption.monospacedDigit().bold())
            .foregroundStyle(.white)
        context.draw(text, at: CGPoint(x: size.width / 2, y: 14))
    }

    /// Stable pseudo-random 0..<1 so the stars don't jump between frames.
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
