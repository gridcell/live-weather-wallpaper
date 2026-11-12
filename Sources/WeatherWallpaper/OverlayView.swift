import MetalKit
import SpriteKit

/// Renders a `WeatherScene` into a transparent Metal view, one frame per `draw()` call.
final class OverlayView: MTKView, MTKViewDelegate {
    let scene: WeatherScene
    private let renderer: SKRenderer
    private let commandQueue: MTLCommandQueue

    init(frame: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice(), let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal is unavailable")
        }
        self.commandQueue = commandQueue
        scene = WeatherScene(size: frame.size)
        renderer = SKRenderer(device: device)
        renderer.scene = scene
        super.init(frame: frame, device: device)
        delegate = self
        layer?.isOpaque = false
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        // Frames are driven by the app delegate's timer, not the view's own display link.
        isPaused = true
        enableSetNeedsDisplay = false
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        renderer.update(atTime: CACurrentMediaTime())
        guard let descriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }
        renderer.render(withViewport: CGRect(origin: .zero, size: drawableSize), commandBuffer: commandBuffer, renderPassDescriptor: descriptor)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
