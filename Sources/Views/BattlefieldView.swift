import SwiftUI

struct BattlefieldView: View {
    let game: Game

    var body: some View {
        let terrain = game.terrain
        let tanks = game.tanks
        let projectiles = game.projectiles
        let explosions = game.explosions
        let wind = game.wind
        let currentID = game.phase == .aiming ? game.current.id : nil

        GeometryReader { proxy in
            let mapper = WorldMapper(size: proxy.size)
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.08, green: 0.1, blue: 0.3), Color(red: 0.45, green: 0.3, blue: 0.5)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
                ))
                drawTerrain(terrain, in: &context, mapper: mapper)
                for tank in tanks {
                    drawTank(tank, isCurrent: tank.id == currentID, in: &context, mapper: mapper)
                }
                for projectile in projectiles {
                    drawProjectile(projectile, in: &context, mapper: mapper)
                }
                for explosion in explosions {
                    drawExplosion(explosion, in: &context, mapper: mapper)
                }
                drawWind(wind, in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard game.phase == .aiming else { return }
                let target = mapper.world(value.location)
                let delta = target - game.current.turretCenter
                let degrees = atan2(max(delta.y, 0), delta.x) * 180 / .pi
                game.setAngle(degrees)
            })
        }
    }

    private func drawTerrain(_ terrain: Terrain, in context: inout GraphicsContext, mapper: WorldMapper) {
        var path = Path()
        path.move(to: mapper.screen(Vec(0, 0)))
        for x in stride(from: 0, to: terrain.width, by: 2) {
            path.addLine(to: mapper.screen(Vec(Double(x), terrain.heights[x])))
        }
        path.addLine(to: mapper.screen(Vec(Double(terrain.width - 1), terrain.heights[terrain.width - 1])))
        path.addLine(to: mapper.screen(Vec(Double(terrain.width - 1), 0)))
        path.closeSubpath()
        context.fill(path, with: .linearGradient(
            Gradient(colors: [Color(red: 0.35, green: 0.65, blue: 0.25), Color(red: 0.4, green: 0.26, blue: 0.12)]),
            startPoint: mapper.screen(Vec(0, terrain.maxHeight * 0.75)), endPoint: mapper.screen(Vec(0, 0))
        ))
    }

    private func drawTank(_ tank: Tank, isCurrent: Bool, in context: inout GraphicsContext, mapper: WorldMapper) {
        let s = mapper.scale
        let color = tank.isAlive ? tank.color : .gray
        let turret = mapper.screen(tank.turretCenter)

        var barrel = Path()
        barrel.move(to: turret)
        barrel.addLine(to: mapper.screen(tank.turretCenter + tank.barrelDirection * Tank.barrelLength))
        context.stroke(barrel, with: .color(color), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))

        let base = mapper.screen(tank.position)
        let body = CGRect(x: base.x - 11 * s, y: base.y - Tank.bodyHeight * s, width: 22 * s, height: Tank.bodyHeight * s)
        context.fill(Path(roundedRect: body, cornerRadius: 3 * s), with: .color(color))
        context.fill(Path(ellipseIn: CGRect(x: turret.x - 6 * s, y: turret.y - 6 * s, width: 12 * s, height: 12 * s)), with: .color(color))

        guard tank.isAlive else { return }
        let bar = CGRect(x: base.x - 14 * s, y: turret.y - 22 * s, width: 28 * s, height: 3.5 * s)
        context.fill(Path(bar), with: .color(.black.opacity(0.5)))
        context.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: bar.width * tank.health / 100, height: bar.height)),
                     with: .color(tank.health > 35 ? .green : .orange))

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
        var trail = Path()
        trail.addLines((projectile.trail + [projectile.position]).map(mapper.screen))
        context.stroke(trail, with: .color(.white.opacity(0.35)), lineWidth: max(1, mapper.scale))
        let head = mapper.screen(projectile.position)
        let r = 2.5 * mapper.scale
        context.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)), with: .color(.white))
    }

    private func drawExplosion(_ explosion: Explosion, in context: inout GraphicsContext, mapper: WorldMapper) {
        let center = mapper.screen(explosion.center)
        let t = explosion.progress
        let r = explosion.radius * mapper.scale * (0.4 + 0.6 * min(t * 2, 1))
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        let fade = 1 - t
        if explosion.isDirt {
            context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.45, green: 0.3, blue: 0.15).opacity(fade * 0.8)))
        } else {
            context.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [.white.opacity(fade), .yellow.opacity(fade), .orange.opacity(fade * 0.9), .red.opacity(0)]),
                center: center, startRadius: 0, endRadius: r
            ))
        }
    }

    private func drawWind(_ wind: Double, in context: inout GraphicsContext, size: CGSize) {
        let arrow = wind == 0 ? "–" : (wind > 0 ? "→" : "←")
        let text = Text("Wind \(arrow) \(Int(abs(wind)))")
            .font(.caption.monospacedDigit().bold())
            .foregroundStyle(.white)
        context.draw(text, at: CGPoint(x: size.width / 2, y: 14))
    }
}

/// Maps the fixed-size world (y up) onto the view (y down), aspect-fit and bottom-aligned.
struct WorldMapper {
    let scale: Double
    let origin: CGPoint

    init(size: CGSize) {
        scale = min(size.width / Game.worldSize.x, size.height / Game.worldSize.y)
        origin = CGPoint(x: (size.width - Game.worldSize.x * scale) / 2, y: size.height)
    }

    func screen(_ p: Vec) -> CGPoint {
        CGPoint(x: origin.x + p.x * scale, y: origin.y - p.y * scale)
    }

    func world(_ p: CGPoint) -> Vec {
        Vec((p.x - origin.x) / scale, (origin.y - p.y) / scale)
    }
}
