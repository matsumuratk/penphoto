import AVFoundation
import SwiftUI
import CoreImage
import UIKit

final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published var ready = false
    @Published var error: String?
    @Published var captured: UIImage?
    @Published var beautyPreview: UIImage?
    @Published var beautyFaceCount: Int?
    @Published var capturing = false
    @Published var hasFlash = false
    @Published var zoom: Double = 1
    @Published var maxZoom: Double = 5
    private let queue = DispatchQueue(label: "penphoto.camera")
    private let frames = DispatchQueue(label: "penphoto.frames", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var wantsRunning = false
    private var previewEnabled = false // Main thread only.
    private var previewToken = UUID() // Main thread only.
    private var frameToken = UUID() // Frames queue only.
    private var beautyStyle: BeautyStyle = .natural // Frames queue only.
    private var strength = 0.0 // Only read/written on frames queue.
    private var lastFrame = CFAbsoluteTimeGetCurrent()
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] _ in
            self?.ready = false; self?.error = "カメラが中断されました。ほかのアプリの使用を終えてから再開してください。"
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in self?.start() })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] _ in
            self?.ready = false; self?.capturing = false; self?.error = "カメラを再開してください。"
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func start() {
        #if targetEnvironment(simulator)
        DispatchQueue.main.async { self.error = "シミュレータではカメラを使えません。サンプルや読み込んだ写真で編集を試せます。" }
        return
        #else
        queue.async { self.wantsRunning = true }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { DispatchQueue.main.async { self.error = "撮影するには、設定でカメラへのアクセスを許可してください。" }; return }
            self.queue.async {
                guard self.wantsRunning else { return }
                do {
                    if !self.configured { try self.configure() }
                    if !self.session.isRunning { self.session.startRunning() }
                    DispatchQueue.main.async { self.ready = self.session.isRunning; self.error = nil }
                } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
            }
        }
        #endif
    }
    func stop() {
        previewToken = UUID()
        queue.async { self.wantsRunning = false; if self.session.isRunning { self.session.stopRunning() } }
        DispatchQueue.main.async { self.ready = false; self.beautyPreview = nil; self.beautyFaceCount = nil }
    }
    private func configure() throws {
        session.beginConfiguration(); defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw AppError.message("カメラが見つかりません。写真を読み込むか、サンプルで編集を試せます。")
        }
        let newInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(newInput), session.canAddOutput(output), session.canAddOutput(video) else { throw AppError.message("カメラを起動できませんでした。") }
        session.addInput(newInput); input = newInput
        session.addOutput(output)
        video.alwaysDiscardsLateVideoFrames = true
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        video.setSampleBufferDelegate(self, queue: frames)
        session.addOutput(video)
        configureConnections()
        configured = true
        updateCapabilities(device)
    }
    private func configureConnections() {
        if let connection = video.connection(with: .video) {
            if connection.videoRotationAngle != 90, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = input?.device.position == .front }
        }
    }
    private func updateCapabilities(_ device: AVCaptureDevice) {
        DispatchQueue.main.async { self.hasFlash = device.hasFlash; self.zoom = 1; self.maxZoom = Double(min(device.activeFormat.videoMaxZoomFactor, 6)) }
    }
    func switchCamera() {
        queue.async {
            guard let old = self.input else { return }
            let position: AVCaptureDevice.Position = old.device.position == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position), let replacement = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(old)
            if self.session.canAddInput(replacement) { self.session.addInput(replacement); self.input = replacement }
            else { self.session.addInput(old) }
            self.configureConnections(); self.session.commitConfiguration()
            self.updateCapabilities(self.input!.device)
            DispatchQueue.main.async { self.beautyPreview = nil }
        }
    }
    func setBeauty(_ value: Double, style: BeautyStyle = .natural) {
        previewEnabled = value > 0
        let token = UUID(); previewToken = token
        frames.async { self.strength = value; self.beautyStyle = style; self.frameToken = token }
        if value == 0 { beautyPreview = nil; beautyFaceCount = nil }
    }
    func setZoom(_ value: Double) {
        queue.async {
            guard let device = self.input?.device else { return }
            do { try device.lockForConfiguration(); defer { device.unlockForConfiguration() }; device.videoZoomFactor = max(1, min(CGFloat(value), min(device.activeFormat.videoMaxZoomFactor, 6))) }
            catch { DispatchQueue.main.async { self.error = "ズームを変更できませんでした。" } }
        }
    }
    func focus(at point: CGPoint) {
        queue.async {
            guard let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) { device.focusPointOfInterest = point; device.focusMode = .autoFocus }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) { device.exposurePointOfInterest = point; device.exposureMode = .continuousAutoExposure }
            } catch { DispatchQueue.main.async { self.error = "ピントを調整できませんでした。" } }
        }
    }
    func setExposure(_ value: Float) {
        queue.async {
            guard let device = self.input?.device else { return }
            do { try device.lockForConfiguration(); defer { device.unlockForConfiguration() }; device.setExposureTargetBias(max(device.minExposureTargetBias, min(value, device.maxExposureTargetBias))) }
            catch { DispatchQueue.main.async { self.error = "明るさを変更できませんでした。" } }
        }
    }
    func capture(flash: Bool) {
        guard ready, !capturing else { return }
        capturing = true
        let orientation = UIDevice.current.orientation
        let angle: CGFloat = orientation == .landscapeLeft ? 0 : orientation == .landscapeRight ? 180 : orientation == .portraitUpsideDown ? 270 : 90
        queue.async {
            guard self.session.isRunning else { DispatchQueue.main.async { self.capturing = false }; return }
            if let connection = self.output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = self.input?.device.position == .front }
            }
            let settings = AVCapturePhotoSettings()
            if self.input?.device.hasFlash == true { settings.flashMode = flash ? .on : .off }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        DispatchQueue.main.async {
            if let error { self.error = error.localizedDescription }
            else if let image { self.captured = image }
            else { self.error = "写真を取得できませんでした。もう一度お試しください。" }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        DispatchQueue.main.async { self.capturing = false; if let error { self.error = error.localizedDescription } }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard strength > 0, CFAbsoluteTimeGetCurrent() - lastFrame > 1.0 / 12.0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = CFAbsoluteTimeGetCurrent()
        autoreleasepool {
            let ci = CIImage(cvPixelBuffer: buffer)
            let scale = 640 / max(ci.extent.width, ci.extent.height)
            let token = frameToken
            let result = ImageProcessor.shared.beautyFrame(ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale)), strength: strength, style: beautyStyle)
            DispatchQueue.main.async {
                if self.previewEnabled && self.ready && self.previewToken == token {
                    self.beautyPreview = result.image; self.beautyFaceCount = result.faceCount
                }
            }
        }
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self)))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.videoRotationAngle != 90, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
}
struct CameraPreview: UIViewRepresentable {
    let camera: CameraService
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView(); view.previewLayer.session = camera.session; view.previewLayer.videoGravity = .resizeAspectFill
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verify-preview-lifecycle") {
            view.isAccessibilityElement = true
            view.accessibilityIdentifier = "previewInstance"
            view.accessibilityValue = UUID().uuidString
        }
        #endif
        view.onFocus = camera.focus; return view
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
