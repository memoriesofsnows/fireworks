import Cocoa
import MetalKit

let BUFFER_BYTE_LEN = 10 * 1000 * 1000

class GameViewController: NSViewController, MTKViewDelegate {
    
    override var acceptsFirstResponder: Bool { return true }

    var device: MTLDevice! = nil
    var commandQueue: MTLCommandQueue! = nil
    var pipelineState: MTLRenderPipelineState! = nil

    var vertexBuffer: MTLBuffer! = nil
    var vertexColorBuffer: MTLBuffer! = nil
    
    let inflightSemaphore = DispatchSemaphore(value: 1)
    
    var fw_scene: FireworkScene! = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        
        device = MTLCreateSystemDefaultDevice()
        // Fallback to a blank NSView, an application could also fallback to
        // OpenGL here.
        guard device != nil else { 
            print("Metal is not supported on this device")
            self.view = NSView(frame: self.view.frame)
            return
        }

        // setup view properties
        let view = self.view as! MTKView
        view.delegate = self
        view.device = device
        view.sampleCount = 4
        
        self.view.window!.makeFirstResponder(self)
        loadAssets()

        fw_scene = FireworkScene()
        let size = self.view.frame
        fw_scene.set_screen_size(width: Float(size.width), 
                height: Float(size.height))
    }
    
    func loadAssets() {
        
        // load any resources required for rendering
        let view = self.view as! MTKView
        commandQueue = device.makeCommandQueue()
        commandQueue.label = "main command queue"
        
        let defaultLibrary = device.makeDefaultLibrary()!
        let fragmentProgram = defaultLibrary.makeFunction(name: "passThroughFragment")!
        let vertexProgram = defaultLibrary.makeFunction(name: "passThroughVertex")!
        
        let psd = MTLRenderPipelineDescriptor()
        psd.vertexFunction = vertexProgram
        psd.fragmentFunction = fragmentProgram
        psd.colorAttachments[0].pixelFormat = view.colorPixelFormat
        psd.sampleCount = view.sampleCount

        // Enable blending
        psd.colorAttachments[0].isBlendingEnabled = true
        psd.colorAttachments[0].rgbBlendOperation = .add
        psd.colorAttachments[0].alphaBlendOperation = .add
        psd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        psd.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        psd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        psd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: psd)
        } catch let error {
            print("Failed to create pipeline state, error \(error)")
        }
        
        vertexBuffer = device.makeBuffer(length: BUFFER_BYTE_LEN, options: [])
        vertexBuffer.label = "vertices"

        vertexColorBuffer = device.makeBuffer(length: BUFFER_BYTE_LEN, options: [])
        vertexColorBuffer.label = "colors"
    }
    
    func draw(in view: MTKView) {
        inflightSemaphore.wait();
        // get buffers ready for writing
        var bv = BufferWrapper(vertexBuffer)
        var bc = BufferWrapper(vertexColorBuffer)
        clearBackground(v: &bv, &bc)
        precondition(bv.pos == bc.pos)
        fw_scene.update(bv: &bv, bc: &bc)
        precondition(bv.pos == bc.pos)
        
        let vertexCount = bv.pos / 4
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        commandBuffer?.label = "Frame command buffer"
        
        // use completion handler to signal the semaphore when this frame is
        // completed allowing the encoding of the next frame to proceed
        // use capture list to avoid any retain cycles if the command buffer
        // gets retained anywhere besides this stack frame
        commandBuffer?.addCompletedHandler{ [weak self] commandBuffer in
            if let strongSelf = self {
                strongSelf.inflightSemaphore.signal()
            }
            return
        }
        
        if let renderPassDescriptor = view.currentRenderPassDescriptor, let currentDrawable = view.currentDrawable
        {
            // If you want to play with not entirely clearing the background, but fading it.
            // I think it's too big of a hammer.
            //renderPassDescriptor.colorAttachments[0].loadAction = .Load
            
            
            
            let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            renderEncoder?.label = "render encoder"
            
            renderEncoder?.pushDebugGroup("draw morphing triangle")
            renderEncoder?.setRenderPipelineState(pipelineState)
            renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder?.setVertexBuffer(vertexColorBuffer, offset: 0, index: 1)
            renderEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
            renderEncoder?.popDebugGroup()
            renderEncoder?.endEncoding()
            
            commandBuffer?.present(currentDrawable)
        }
        
        commandBuffer?.commit()
    }
    
    //replace
//    func drawInMTKView(view: MTKView) {
//        inflightSemaphore.wait();
//        print("sssss")
//        // get buffers ready for writing
//        var bv = BufferWrapper(vertexBuffer)
//        var bc = BufferWrapper(vertexColorBuffer)
//        clearBackground(v: &bv, &bc)
//        precondition(bv.pos == bc.pos)
//        fw_scene.update(bv: &bv, bc: &bc)
//        precondition(bv.pos == bc.pos)
//
//        let vertexCount = bv.pos / 4
//
//        let commandBuffer = commandQueue.makeCommandBuffer()
//        commandBuffer?.label = "Frame command buffer"
//
//        // use completion handler to signal the semaphore when this frame is
//        // completed allowing the encoding of the next frame to proceed
//        // use capture list to avoid any retain cycles if the command buffer
//        // gets retained anywhere besides this stack frame
//        commandBuffer?.addCompletedHandler{ [weak self] commandBuffer in
//            if let strongSelf = self {
//                strongSelf.inflightSemaphore.signal()
//            }
//            return
//        }
//
//        if let renderPassDescriptor = view.currentRenderPassDescriptor, let currentDrawable = view.currentDrawable
//        {
//            // If you want to play with not entirely clearing the background, but fading it.
//            // I think it's too big of a hammer.
//            //renderPassDescriptor.colorAttachments[0].loadAction = .Load
//
//
//
//            let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
//            renderEncoder?.label = "render encoder"
//
//            renderEncoder?.pushDebugGroup("draw morphing triangle")
//            renderEncoder?.setRenderPipelineState(pipelineState)
//            renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
//            renderEncoder?.setVertexBuffer(vertexColorBuffer, offset: 0, index: 1)
//            renderEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
//            renderEncoder?.popDebugGroup()
//            renderEncoder?.endEncoding()
//
//            commandBuffer?.present(currentDrawable)
//        }
//
//        commandBuffer?.commit()
//    }
    
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        fw_scene.set_screen_size(width: Float(size.width), 
                height: Float(size.height))
    }


    // Draw two triangles and clear the background.
    func clearBackground( v: inout BufferWrapper, _ c: inout BufferWrapper) {
        let vertexBackground:[Float] = [
         -1.0, -1.0, 0.0, 1.0,
         -1.0,  1.0, 0.0, 1.0,
          1.0, -1.0, 0.0, 1.0,
         
          1.0, -1.0, 0.0, 1.0,
          1.0,  1.0, 0.0, 1.0,
         -1.0,  1.0, 0.0, 1.0,
        ]

        let bgcolor = Color4(r: 0.0, g: 0.0, b: 0.0, a: 1.0)
        let vertexBackgroundColor:[Color4] = [
            bgcolor,
            bgcolor,
            bgcolor,

            bgcolor,
            bgcolor,
            bgcolor,
        ]

        for f in vertexBackground {
            v.append(f)
        }
        for f in vertexBackgroundColor {
            c.append(f)
        }
    }

    override func keyDown(with theEvent: NSEvent) {
        print(theEvent)
        if (theEvent.characters! == " ") {
            clock_toggle_pause()
        } else if (theEvent.characters! == "j") {
            clock_step_pause(usecs: 16667)
        } else if (theEvent.characters! == "k") {
            clock_step_pause(usecs: -16667)
        } else {
            super.keyDown(with: theEvent)
        }
    }
    
}
