import AppKit
import SpriteKit

private enum Textures {
    // Photographic textures from Resources/Textures, with procedural fallbacks.
    static let rain = load(["raindrop_1", "raindrop_2"], maxDimension: 256) ?? [streak]
    static let snow = load(["snowflake_1", "snowflake_2", "snowflake_3"], maxDimension: 96) ?? [flake]
    static let clouds = load(["cloud_1", "cloud_2", "cloud_3"], maxDimension: 1536) ?? [blob]
    static let fog = load(["fog_1", "fog_2"], maxDimension: 1536) ?? [blob]
    static let lightning = load(["lightning_1", "lightning_2"], maxDimension: 1536) ?? []

    /// Thin vertical streak, brighter at the bottom (the leading edge of a falling drop).
    static let streak = make(width: 3, height: 64) { ctx, rect in
        let colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.maxY), end: .zero, options: [])
    }

    static let flake = radial(size: 24, locations: [0, 0.4, 1], alphas: [1, 0.8, 0])
    static let blob = radial(size: 256, locations: [0, 0.5, 1], alphas: [1, 0.45, 0])

    /// Water bead on glass: dark upper edge, bright lower edge (refraction), small specular highlight.
    static let droplet = make(width: 48, height: 56) { ctx, rect in
        let body = rect.insetBy(dx: 2, dy: 2)
        ctx.saveGState()
        ctx.addEllipse(in: body)
        ctx.clip()
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.1).cgColor)
        ctx.fill(body)
        let colors = [
            NSColor.white.withAlphaComponent(0.6).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.black.withAlphaComponent(0.4).cgColor,
        ] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: body)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: rect.width * 0.26, y: rect.height * 0.62, width: 8, height: 9))
    }

    private static func load(_ names: [String], maxDimension: Int) -> [SKTexture]? {
        let textures = names.compactMap { name -> SKTexture? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Textures"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            return maskTexture(from: image, maxDimension: maxDimension)
        }
        return textures.isEmpty ? nil : textures
    }

    /// Turns a white-on-black image into a white texture whose alpha is the source
    /// luminance, cropped to its visible content and scaled to fit `maxDimension`.
    private static func maskTexture(from image: CGImage, maxDimension: Int) -> SKTexture? {
        let width = image.width, height = image.height
        var gray = [UInt8](repeating: 0, count: width * height)
        guard let grayContext = CGContext(data: &gray, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        grayContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Anything darker than `floor` is treated as fully transparent background.
        let floor = 14
        var minX = width, maxX = -1, minY = height, maxY = -1
        // Dim subjects (fog) are normalised so their brightest point is fully opaque.
        let peak = Int(gray.max() ?? 255)
        for y in 0..<height {
            for x in 0..<width where Int(gray[y * width + x]) > floor + 6 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let cropWidth = maxX - minX + 1, cropHeight = maxY - minY + 1
        var rgba = [UInt8](repeating: 0, count: cropWidth * cropHeight * 4)
        for y in 0..<cropHeight {
            for x in 0..<cropWidth {
                let value = Int(gray[(y + minY) * width + x + minX])
                let alpha = UInt8(max(0, min(255, (value - floor) * 255 / max(1, peak - floor))))
                let i = (y * cropWidth + x) * 4
                // Premultiplied white.
                rgba[i] = alpha; rgba[i + 1] = alpha; rgba[i + 2] = alpha; rgba[i + 3] = alpha
            }
        }
        let rgb = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let cropContext = CGContext(data: &rgba, width: cropWidth, height: cropHeight, bitsPerComponent: 8,
                                          bytesPerRow: cropWidth * 4, space: rgb, bitmapInfo: info),
              let cropped = cropContext.makeImage()
        else { return nil }

        let scale = min(1, CGFloat(maxDimension) / CGFloat(max(cropWidth, cropHeight)))
        let outWidth = max(1, Int(CGFloat(cropWidth) * scale)), outHeight = max(1, Int(CGFloat(cropHeight) * scale))
        guard let outContext = CGContext(data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: rgb, bitmapInfo: info)
        else { return nil }
        outContext.interpolationQuality = .high
        outContext.draw(cropped, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))
        return outContext.makeImage().map { SKTexture(cgImage: $0) }
    }

    private static func radial(size: CGFloat, locations: [CGFloat], alphas: [CGFloat]) -> SKTexture {
        make(width: size, height: size) { ctx, rect in
            let colors = alphas.map { NSColor.white.withAlphaComponent($0).cgColor } as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations)!
            let center = CGPoint(x: rect.midX, y: rect.midY)
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size / 2, options: [])
        }
    }

    private static func make(width: CGFloat, height: CGFloat, draw: @escaping (CGContext, CGRect) -> Void) -> SKTexture {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(ctx, rect)
            return true
        }
        return SKTexture(image: image)
    }
}

final class WeatherScene: SKScene {
    private var weather: Weather?
    private var effect: SKNode?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .fill
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ weather: Weather?) {
        guard weather != self.weather else { return }
        self.weather = weather
        rebuild(fade: 2)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        if weather != nil { rebuild(fade: 0) }
    }

    private func rebuild(fade: TimeInterval) {
        effect?.run(.sequence([.fadeOut(withDuration: fade), .removeFromParent()]))
        effect = nil
        guard let weather, size.width > 0, size.height > 0 else { return }
        let node = makeEffect(for: weather)
        node.alpha = 0
        addChild(node)
        node.run(.fadeIn(withDuration: fade))
        effect = node
    }

    // MARK: - Effects

    private func makeEffect(for weather: Weather) -> SKNode {
        let root = SKNode()
        let wind = max(-1, min(1, weather.windX / 50))

        switch weather.kind {
        case .clear:
            if weather.isDay { root.addChild(sunGlow()) }
        case .partlyCloudy:
            if weather.isDay { root.addChild(sunGlow()) }
            root.addChild(drifting(Textures.clouds, count: 4, band: 0.75...1.0, alpha: 0.55, speed: 10, wind: wind))
        case .cloudy:
            root.addChild(tint(0.08))
            root.addChild(drifting(Textures.clouds, count: 10, band: 0.65...1.0, alpha: 0.6, speed: 12, wind: wind))
        case .fog:
            root.addChild(drifting(Textures.fog, count: 12, band: 0.0...1.0, alpha: 0.45, speed: 7, wind: wind))
        case .drizzle:
            root.addChild(tint(0.06))
            root.addChild(rain(rate: 110, speed: 750, length: 35, alpha: 0.3, wind: wind))
            root.addChild(stuckDrops(every: 3, melting: false))
        case .rain:
            root.addChild(tint(0.1))
            root.addChild(rain(rate: 190, speed: 900, length: 40, alpha: 0.25, wind: wind))
            root.addChild(rain(rate: 190, speed: 1250, length: 65, alpha: 0.4, wind: wind))
            root.addChild(stuckDrops(every: 1.5, melting: false))
        case .heavyRain:
            root.addChild(tint(0.16))
            root.addChild(rain(rate: 450, speed: 1050, length: 45, alpha: 0.28, wind: wind))
            root.addChild(rain(rate: 450, speed: 1500, length: 80, alpha: 0.45, wind: wind))
            root.addChild(stuckDrops(every: 0.7, melting: false))
        case .thunderstorm:
            root.addChild(tint(0.2))
            root.addChild(rain(rate: 400, speed: 1050, length: 45, alpha: 0.28, wind: wind))
            root.addChild(rain(rate: 400, speed: 1500, length: 80, alpha: 0.45, wind: wind))
            root.addChild(stuckDrops(every: 0.7, melting: false))
            root.addChild(lightning())
        case .snow:
            root.addChild(snow(rate: 22, speed: 55, diameter: 7, alpha: 0.6, wind: wind))
            root.addChild(snow(rate: 14, speed: 95, diameter: 14, alpha: 0.85, wind: wind))
            root.addChild(snow(rate: 2, speed: 150, diameter: 34, alpha: 0.5, wind: wind))
            root.addChild(stuckDrops(every: 3, melting: true))
        case .heavySnow:
            root.addChild(tint(0.05))
            root.addChild(snow(rate: 60, speed: 70, diameter: 7, alpha: 0.6, wind: wind))
            root.addChild(snow(rate: 40, speed: 120, diameter: 15, alpha: 0.85, wind: wind))
            root.addChild(snow(rate: 6, speed: 190, diameter: 36, alpha: 0.5, wind: wind))
            root.addChild(stuckDrops(every: 1.5, melting: true))
        }
        return root
    }

    /// Emitter spanning the top edge, aimed downward and leaned by `tilt` radians.
    private func fallingEmitter(texture: SKTexture, rate: CGFloat, speed: CGFloat, tilt: CGFloat) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        let drift = tan(tilt) * size.height
        emitter.particleTexture = texture
        emitter.particleBirthRate = rate * size.width / 1500
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.25
        emitter.emissionAngle = -.pi / 2 + tilt
        emitter.particleLifetime = (size.height + 120) / (speed * 0.85)
        emitter.position = CGPoint(x: size.width / 2 - drift / 2, y: size.height + 60)
        emitter.particlePositionRange = CGVector(dx: size.width * 1.1 + abs(drift), dy: 0)
        emitter.particleColorBlendFactor = 1
        return emitter
    }

    /// One emitter per texture variant, sharing `rate` between them.
    private func falling(_ textures: [SKTexture], rate: CGFloat, speed: CGFloat, tilt: CGFloat,
                         configure: (SKEmitterNode, SKTexture) -> Void) -> SKNode {
        let container = SKNode()
        for texture in textures {
            let emitter = fallingEmitter(texture: texture, rate: rate / CGFloat(textures.count), speed: speed, tilt: tilt)
            configure(emitter, texture)
            emitter.advanceSimulationTime(TimeInterval(emitter.particleLifetime))
            container.addChild(emitter)
        }
        return container
    }

    /// `length` is the on-screen streak length in points.
    private func rain(rate: CGFloat, speed: CGFloat, length: CGFloat, alpha: CGFloat, wind: Double) -> SKNode {
        let tilt = CGFloat(wind) * 0.35
        return falling(Textures.rain, rate: rate, speed: speed, tilt: tilt) { emitter, texture in
            let scale = length / texture.size().height
            emitter.particleRotation = tilt
            emitter.particleScale = scale
            emitter.particleScaleRange = scale * 0.4
            emitter.particleAlpha = alpha
            emitter.particleAlphaRange = alpha * 0.5
            emitter.particleColor = NSColor(calibratedRed: 0.85, green: 0.92, blue: 1, alpha: 1)
        }
    }

    private func snow(rate: CGFloat, speed: CGFloat, diameter: CGFloat, alpha: CGFloat, wind: Double) -> SKNode {
        falling(Textures.snow, rate: rate, speed: speed, tilt: CGFloat(wind) * 0.8) { emitter, texture in
            let scale = diameter / max(texture.size().width, texture.size().height)
            emitter.emissionAngleRange = 0.5
            emitter.particleScale = scale
            emitter.particleScaleRange = scale * 0.6
            emitter.particleRotationRange = .pi * 2
            emitter.particleRotationSpeed = 0.6
            emitter.particleAlpha = alpha
            emitter.particleAlphaRange = 0.3
            emitter.particleColor = .white
        }
    }

    /// Clouds or fog drifting sideways across a horizontal band of the screen.
    private func drifting(_ textures: [SKTexture], count: Int, band: ClosedRange<CGFloat>, alpha: CGFloat, speed: CGFloat, wind: Double) -> SKNode {
        let container = SKNode()
        // Lay everything out drifting rightward, then mirror for a leftward wind.
        if wind < 0 {
            container.xScale = -1
            container.position.x = size.width
        }
        let pace = speed * (1 + CGFloat(abs(wind)) * 2)
        for index in 0..<count {
            let texture = textures[index % textures.count]
            let width = CGFloat.random(in: 0.45...0.9) * size.width
            let sprite = SKSpriteNode(texture: texture)
            sprite.size = CGSize(width: width, height: width * texture.size().height / texture.size().width)
            sprite.xScale = Bool.random() ? 1 : -1
            sprite.alpha = alpha * CGFloat.random(in: 0.6...1)
            let start = CGFloat.random(in: -width / 2...size.width + width / 2)
            let end = size.width + width / 2
            sprite.position = CGPoint(x: start, y: CGFloat.random(in: band) * size.height)
            let lap = SKAction.sequence([
                .moveTo(x: -width / 2, duration: 0),
                .moveTo(x: end, duration: TimeInterval((end + width / 2) / pace)),
            ])
            sprite.run(.sequence([
                .moveTo(x: end, duration: TimeInterval((end - start) / pace)),
                .repeatForever(lap),
            ]))
            container.addChild(sprite)
        }
        return container
    }

    private func sunGlow() -> SKNode {
        let glow = SKSpriteNode(texture: Textures.blob)
        let diameter = size.height * 1.3
        glow.size = CGSize(width: diameter, height: diameter)
        glow.position = CGPoint(x: size.width * 0.9, y: size.height)
        glow.color = NSColor(calibratedRed: 1, green: 0.82, blue: 0.5, alpha: 1)
        glow.colorBlendFactor = 1
        glow.blendMode = .add
        glow.alpha = 0.3
        let pulse = SKAction.sequence([.fadeAlpha(to: 0.42, duration: 6), .fadeAlpha(to: 0.3, duration: 6)])
        pulse.timingMode = .easeInEaseOut
        glow.run(.repeatForever(pulse))
        return glow
    }

    /// Periodic strikes: a bolt at a random spot along the top plus a full-screen flash.
    private func lightning() -> SKNode {
        let container = SKNode()
        let flash = SKSpriteNode(color: .white, size: size)
        flash.anchorPoint = .zero
        flash.alpha = 0
        let bolt = SKSpriteNode()
        bolt.anchorPoint = CGPoint(x: 0.5, y: 1)
        bolt.blendMode = .add
        bolt.alpha = 0
        container.addChild(flash)
        container.addChild(bolt)

        let sceneSize = size
        let strike = SKAction.run { [weak flash, weak bolt] in
            if let bolt, let texture = Textures.lightning.randomElement() {
                let height = sceneSize.height * CGFloat.random(in: 0.55...0.85)
                bolt.texture = texture
                bolt.size = CGSize(width: height * texture.size().width / texture.size().height, height: height)
                bolt.xScale = Bool.random() ? 1 : -1
                bolt.position = CGPoint(x: sceneSize.width * CGFloat.random(in: 0.1...0.9), y: sceneSize.height)
                bolt.run(.sequence([
                    .fadeAlpha(to: 1, duration: 0.03),
                    .fadeAlpha(to: 0.25, duration: 0.08),
                    .fadeAlpha(to: 0.9, duration: 0.04),
                    .fadeAlpha(to: 0, duration: 0.45),
                ]))
            }
            flash?.run(.sequence([
                .fadeAlpha(to: 0.3, duration: 0.04),
                .fadeAlpha(to: 0.05, duration: 0.08),
                .fadeAlpha(to: 0.22, duration: 0.04),
                .fadeAlpha(to: 0, duration: 0.5),
            ]))
        }
        container.run(.repeatForever(.sequence([.wait(forDuration: 8, withRange: 10), strike])))
        return container
    }

    /// Now and then something sticks to the "glass": a raindrop that beads up and then
    /// trickles down, or (when `melting`) a snowflake that melts into a bead first.
    private func stuckDrops(every interval: TimeInterval, melting: Bool) -> SKNode {
        let container = SKNode()
        container.zPosition = 1
        let spawn = SKAction.run { [weak self, weak container] in
            guard let self, let container else { return }
            self.addStuckDrop(to: container, melting: melting)
        }
        container.run(.repeatForever(.sequence([.wait(forDuration: interval, withRange: interval), spawn])))
        return container
    }

    private func addStuckDrop(to container: SKNode, melting: Bool) {
        let point = CGPoint(x: .random(in: 0...size.width), y: .random(in: size.height * 0.25...size.height))
        let width = CGFloat.random(in: 7...13)
        let drop = SKSpriteNode(texture: Textures.droplet)
        drop.size = CGSize(width: width, height: width * 1.2)
        drop.position = point
        drop.alpha = 0
        container.addChild(drop)

        let arrive: SKAction
        if melting, let texture = Textures.snow.randomElement() {
            let flake = SKSpriteNode(texture: texture)
            flake.size = CGSize(width: width * 2, height: width * 2)
            flake.position = point
            flake.zRotation = .random(in: 0...(.pi * 2))
            flake.alpha = 0
            container.addChild(flake)
            let sit = TimeInterval.random(in: 1.5...4)
            flake.run(.sequence([
                .fadeAlpha(to: 0.9, duration: 0.1),
                .wait(forDuration: sit),
                .group([.fadeOut(withDuration: 2), .scale(to: 0.4, duration: 2)]),
                .removeFromParent(),
            ]))
            // The bead forms as the flake melts away.
            arrive = .sequence([
                .wait(forDuration: sit + 0.5),
                .fadeAlpha(to: 0.9, duration: 1.5),
                .wait(forDuration: .random(in: 0.5...1.5)),
            ])
        } else {
            arrive = .sequence([.fadeAlpha(to: 0.9, duration: 0.12), .wait(forDuration: .random(in: 0.8...3.5))])
        }

        // Real drops run in fits and starts, wandering slightly sideways.
        var steps: [SKAction] = []
        for _ in 0..<Int.random(in: 3...6) {
            let fall = CGFloat.random(in: 30...130)
            let move = SKAction.moveBy(x: .random(in: -5...5), y: -fall, duration: TimeInterval(fall / .random(in: 90...260)))
            move.timingMode = .easeIn
            steps.append(move)
            steps.append(.wait(forDuration: .random(in: 0...0.7)))
        }
        let running = SKAction.sequence(steps)

        // Leave a wet trail that dries behind the drop.
        var lastTrail = point
        let trail = SKAction.run { [weak drop, weak container] in
            guard let drop, let container, abs(drop.position.y - lastTrail.y) > 3 else { return }
            lastTrail = drop.position
            let streak = SKSpriteNode(texture: Textures.flake)
            streak.size = CGSize(width: width * 0.5, height: max(width * 0.9, 14))
            streak.position = drop.position
            streak.alpha = 0.16
            streak.zPosition = -0.5
            container.addChild(streak)
            streak.run(.sequence([.fadeOut(withDuration: 1.8), .removeFromParent()]))
        }
        let trailing = SKAction.repeat(.sequence([trail, .wait(forDuration: 0.03)]), count: Int(running.duration / 0.03) + 1)

        drop.run(.sequence([
            arrive,
            .group([running, trailing, .scale(to: 0.7, duration: running.duration)]),
            .fadeOut(withDuration: 0.4),
            .removeFromParent(),
        ]))
    }

    /// Darkens the wallpaper slightly for overcast moods.
    private func tint(_ alpha: CGFloat) -> SKNode {
        let node = SKSpriteNode(color: .black, size: size)
        node.anchorPoint = .zero
        node.alpha = alpha
        node.zPosition = -1
        return node
    }
}
