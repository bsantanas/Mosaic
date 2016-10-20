//
//  ViewController.swift
//  Mosaic
//
//  Created by Bernardo Santana on 9/27/16.
//  Copyright © 2016 Bernardo Santana. All rights reserved.
//

import UIKit
import Metal
import MetalKit
import QuartzCore
import AVFoundation

class ViewController: UIViewController {
    
    //MARK: - Outlets
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var pixelSizeSlider: UISlider!
    //let metalView = VideoMetalView(frame: CGRect.zero)
    
    // MARK: - Metal Configuration
    var videoTextureCache : CVMetalTextureCache?
    let queue = DispatchQueue(label: "com.invasivecode.metalQueue")
    var device: MTLDevice!
    lazy var defaultLibrary: MTLLibrary! = {
        self.device.newDefaultLibrary()
    }()
    lazy var commandQueue: MTLCommandQueue! = {
        NSLog("\(self.device.name!)")
        return self.device.makeCommandQueue()
    }()
    var inTexture: MTLTexture!
    var outTexture: MTLTexture!
    let bytesPerPixel: Int = 4
    var pipelineState: MTLComputePipelineState!
    
    func setUpMetal() {
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Not a Metal-compatible device")
            return
        }
        
        self.device = device
        
       // metalView.framebufferOnly = false
        
        // Texture for Y
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &videoTextureCache)
        
        // Texture for CbCr
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &videoTextureCache)
        
        if let kernelFunction = defaultLibrary.makeFunction(name: "pixelate") {
            do {
                pipelineState = try device.makeComputePipelineState(function: kernelFunction)
            }
            catch {
                fatalError("Impossible to setup Metal")
            }
            
        }
    }
    
    let threadGroupCount = MTLSizeMake(16, 16, 1)
    
    lazy var threadGroups: MTLSize = {
        MTLSizeMake(Int(self.inTexture.width) / self.threadGroupCount.width, Int(self.inTexture.height) / self.threadGroupCount.height, 1)
    }()

    //MARK: - Vars
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var pixelSize: UInt = 60
    
    //MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = AVCaptureSessionPresetPhoto

        let backCamera = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .back)
        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            captureSession.addInput(input)
        } catch {
            failed()
            return
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer delegate"))
        } else {
            failed()
        }
        
        // although we don't use this, it's required to get captureOutput invoked
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer!.frame = view.layer.bounds // comment to "hide"
        previewLayer!.videoGravity = AVLayerVideoGravityResizeAspectFill
        view.layer.addSublayer(previewLayer!)
        
//        view.addSubview(metalView)
        
        captureSession.startRunning()
        

        queue.async {
            self.setUpMetal()
        }
    }
    
    func failed() {
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning a code from an item. Please use a device with a camera.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if (captureSession?.isRunning == false) {
            captureSession.startRunning();
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        queue.async{
            
            guard let _ = self.device else { return }
            
            self.importTexture()
            
            self.applyFilter()
            
            let finalResult = self.imageFrom(texture: self.outTexture)
            
            DispatchQueue.main.async {
                self.imageView.image = finalResult
            }
            
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning();
        }
    }

    
//    override func viewDidLayoutSubviews()
//    {
//        metalView.frame = view.bounds
//        
//        metalView.drawableSize = CGSize(width: view.bounds.width * 2, height: view.bounds.height * 2)
//        
//        
//    }
    
    // MARK: -
    
    func importTexture() {
        guard let image = UIImage(named: "invasivecode") else {
            fatalError("Can't read image")
        }
        inTexture = textureFrom(image)
    }
    
    func applyFilter() {
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()
        
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setTexture(inTexture, at: 0)
        commandEncoder.setTexture(outTexture, at: 1)
        
        let buffer = device.makeBuffer(bytes: &pixelSize, length: MemoryLayout<UInt>.size, options: [MTLResourceOptions.storageModeShared])
        commandEncoder.setBuffer(buffer, offset: 0, at: 0)
        
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    func textureFrom(_ image: UIImage) -> MTLTexture {
        
        //Rotate image so that y points downards in the texture
        UIGraphicsBeginImageContext(image.size);
        let context = UIGraphicsGetCurrentContext()
        context!.rotate(by: CGFloat(M_PI))
        image.draw(at: CGPoint(x:0,y:0))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        
        guard let cgImage = image!.cgImage else {
            fatalError("Can't open image \(image)")
        }
        
        
        let textureLoader = MTKTextureLoader(device: self.device)
        do {
            let textureOut = try textureLoader.newTexture(with: cgImage, options: nil)
            print(textureOut.pixelFormat)
            let pixelFormat = MTLPixelFormat.bgra8Unorm
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: textureOut.pixelFormat, width: textureOut.width, height: textureOut.height, mipmapped: false)
            outTexture = self.device.makeTexture(descriptor: textureDescriptor)
            return textureOut
        }
        catch {
            fatalError("Can't load texture")
        }
    }
    
    
    func imageFrom(texture: MTLTexture) -> UIImage {
        
        let imageByteCount = texture.width * texture.height * bytesPerPixel
        let bytesPerRow = texture.width * bytesPerPixel
        var src = [UInt8](repeating: 0, count: Int(imageByteCount))
        
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        texture.getBytes(&src, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        
        let grayColorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 8
        let context = CGContext(data: &src, width: texture.width, height: texture.height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: grayColorSpace, bitmapInfo: bitmapInfo.rawValue)
        
        let dstImageFilter = context!.makeImage()
        
        return UIImage(cgImage: dstImageFilter!, scale: 0.0, orientation: UIImageOrientation.downMirrored)
    }

    @IBAction func changePixelSize(sender: AnyObject) {
        if let slider = sender as? UISlider {
            pixelSize = UInt(slider.value)
            
            guard let _ = device else { return }
            
            queue.async {
                
                self.applyFilter()
                
                let finalResult = self.imageFrom(texture: self.outTexture)
                
                DispatchQueue.main.async {
                    self.imageView.image = finalResult
                }
                
            }
            
        }
    }

}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        
        guard let _ = device else { return }
        
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        
        // Y: luma
        
        var yTextureRef : CVMetalTexture?
        
        let yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer!, 0);
        let yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer!, 0);
        
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                  videoTextureCache!,
                                                  pixelBuffer!,
                                                  nil,
                                                  MTLPixelFormat.r8Unorm,
                                                  yWidth, yHeight, 0,
                                                  &yTextureRef)
        
        
        // CbCr: CB and CR are the blue-difference and red-difference chroma components /
        
        var cbcrTextureRef : CVMetalTexture?
        
        let cbcrWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer!, 1);
        let cbcrHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer!, 1);
        
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                  videoTextureCache!,
                                                  pixelBuffer!,
                                                  nil,
                                                  MTLPixelFormat.rg8Unorm,
                                                  cbcrWidth, cbcrHeight, 1,
                                                  &cbcrTextureRef)
        
        let yTexture:MTLTexture? = CVMetalTextureGetTexture(yTextureRef!)
        let cbcrTexture:MTLTexture? = CVMetalTextureGetTexture(cbcrTextureRef!)
        
        //self.metalView.addTextures(yTexture: yTexture!, cbcrTexture: cbcrTexture!)
        
    }
}

// MARK: -
class VideoMetalView: MTKView  {
    
    var ytexture:MTLTexture?
    var cbcrTexture: MTLTexture?
    
    var pipelineState: MTLComputePipelineState!
    let queue = DispatchQueue(label: "com.invasivecode.metalQueue")
    lazy var defaultLibrary: MTLLibrary! = {
        self.device!.newDefaultLibrary()
    }()
    lazy var commandQueue: MTLCommandQueue! = {
        NSLog("\(self.device!.name!)")
        return self.device!.makeCommandQueue()
    }()
    let bytesPerPixel: Int = 4
    let threadGroupCount = MTLSizeMake(16, 16, 1)
    lazy var threadGroups: MTLSize = {
        MTLSizeMake(Int(self.ytexture!.width) / self.threadGroupCount.width, Int(self.ytexture!.height) / self.threadGroupCount.height, 1)
    }()
    var pixelSize: UInt = 60
    
    required init(frame: CGRect) {
        super.init(frame: frame, device:  MTLCreateSystemDefaultDevice())
        
        let kernelFunction = defaultLibrary.makeFunction(name: "YCbCrColorConversion")
        
        do {
            pipelineState = try device!.makeComputePipelineState(function: kernelFunction!)
        } catch {
            fatalError("Unable to create pipeline state")
        }
        
        //threadGroups = MTLSizeMake(2048 / threadGroupCount.width, 1536 / threadGroupCount.height, 1)
        
        //blur = MPSImageGaussianBlur(device: device!, sigma: 0)
    }
    
    required init(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func addTextures(yTexture ytexture:MTLTexture, cbcrTexture: MTLTexture)
    {
        self.ytexture = ytexture
        self.cbcrTexture = cbcrTexture
    }
    
    func setBlurSigma(sigma: Float)
    {
        //blur = MPSImageGaussianBlur(device: device!, sigma: sigma)
    }
    
    override func draw(_ dirtyRect: CGRect) {
        guard let drawable = currentDrawable, let ytexture = ytexture, let cbcrTexture = cbcrTexture else { return }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()
        
        commandEncoder.setComputePipelineState(pipelineState)
        
        commandEncoder.setTexture(ytexture, at: 0)
        commandEncoder.setTexture(cbcrTexture, at: 1)
        commandEncoder.setTexture(drawable.texture, at: 2) // out texture
        
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        
        commandEncoder.endEncoding()
        
        let inPlaceTexture = UnsafeMutablePointer<MTLTexture?>.allocate(capacity: 1)
        inPlaceTexture.initialize(to: drawable.texture)
        
//        blur.encodeToCommandBuffer(commandBuffer, inPlaceTexture: inPlaceTexture, fallbackCopyAllocator: nil)
        
        let buffer = device?.makeBuffer(bytes: &pixelSize, length: MemoryLayout<UInt>.size, options: [MTLResourceOptions.storageModeShared])
        commandEncoder.setBuffer(buffer, offset: 0, at: 0)
        commandEncoder.endEncoding()

        
        commandBuffer.present(drawable)
        commandBuffer.commit();
//        commandBuffer.waitUntilCompleted()
        
    }
}
