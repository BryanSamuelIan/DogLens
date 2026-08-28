import SwiftUI
import AVFoundation

// MARK: - SwiftUI Representable

struct LiveScannerView: UIViewControllerRepresentable {
    var isActive: Bool
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> LiveCameraViewController {
        let vc = LiveCameraViewController()
        vc.onClose = onClose
        vc.setActive(isActive)
        return vc
    }

    func updateUIViewController(_ uiViewController: LiveCameraViewController, context: Context) {
        uiViewController.onClose = onClose
        uiViewController.setActive(isActive)
    }
}

// MARK: - UIKit Camera Controller

class LiveCameraViewController: UIViewController {
    
    // MARK: AV
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var videoDevice: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "com.doglens.liveSessionQueue")
    private(set) var isActive: Bool = true

    // MARK: Callbacks
    var onClose: (() -> Void)?

    // MARK: State
    private var initialZoomFactor: CGFloat = 1.0
    private var zoomTimer: Timer?
    private var focusRingView: UIView?
    
    // Bounding Boxes / Inference
    private var boundingBoxContainerView: UIView?
    private let videoDataOutputQueue = DispatchQueue(label: "com.doglens.liveVideoDataOutputQueue", qos: .userInitiated)
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastInferenceTime = Date.distantPast
    private let inferenceInterval: TimeInterval = 1.0 / 15.0
    
    private let queueLock = NSLock()
    private var isProcessingLiveFrame = false

    // MARK: UI Elements
    private let closeButton = UIButton(type: .system)
    private let zoomLabel = UILabel()
    
    func setActive(_ active: Bool) {
        guard self.isActive != active else { return }
        self.isActive = active
        if active {
            startCameraSession()
        } else {
            stopCameraSession()
        }
    }

    private func startCameraSession() {
        guard isActive else { return }
        if previewLayer?.session == nil {
            previewLayer?.session = captureSession
        }
        if previewLayer?.superlayer == nil, let previewLayer = previewLayer {
            view.layer.insertSublayer(previewLayer, at: 0)
        }
        let session = captureSession
        sessionQueue.async {
            if session?.isRunning == false {
                session?.startRunning()
            }
        }
    }

    private func stopCameraSession() {
        previewLayer?.removeFromSuperlayer()
        previewLayer?.session = nil
        // Clear bounding boxes when session stops
        DispatchQueue.main.async { [weak self] in
            self?.boundingBoxContainerView?.subviews.forEach { $0.removeFromSuperview() }
        }
        let session = captureSession
        sessionQueue.async {
            if session?.isRunning == true {
                session?.stopRunning()
            }
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
        setupGestures()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Clear bounding boxes initially
        boundingBoxContainerView?.subviews.forEach { $0.removeFromSuperview() }

        if let conn = previewLayer?.connection {
            conn.isEnabled = true
            setPortraitOrientation(on: conn)
        }
        if let conn = videoDataOutput?.connection(with: .video) {
            setPortraitOrientation(on: conn)
        }
        
        startCameraSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCameraSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCameraSession()
    }

    deinit {
        zoomTimer?.invalidate()
        let session = captureSession
        sessionQueue.async {
            if session?.isRunning == true {
                session?.stopRunning()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        if let conn = previewLayer?.connection { setPortraitOrientation(on: conn) }
        if let conn = videoDataOutput?.connection(with: .video) { setPortraitOrientation(on: conn) }
        boundingBoxContainerView?.frame = view.bounds
    }

    // MARK: - Camera Setup

    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720

        // Video input
        guard let vDevice = AVCaptureDevice.default(for: .video),
              let vInput = try? AVCaptureDeviceInput(device: vDevice),
              captureSession.canAddInput(vInput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(vInput)
        videoDevice = vDevice

        // Video data output
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        dataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if captureSession.canAddOutput(dataOutput) {
            captureSession.addOutput(dataOutput)
            if let conn = dataOutput.connection(with: .video) {
                setPortraitOrientation(on: conn)
            }
        }
        self.videoDataOutput = dataOutput
        captureSession.commitConfiguration()

        // Preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        if let conn = previewLayer.connection { setPortraitOrientation(on: conn) }
        view.layer.addSublayer(previewLayer)

        // Bounding Box Container (placed right above preview layer but below UI buttons)
        let container = UIView(frame: view.bounds)
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        view.addSubview(container)
        self.boundingBoxContainerView = container

        DispatchQueue.global(qos: .userInitiated).async { self.captureSession.startRunning() }
    }

    private func setPortraitOrientation(on connection: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        } else {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        }
    }

    // MARK: - UI Setup

    func setupUI() {
        // ── Close button ──────────────────────────────────────────────
        let xConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closeButton.layer.cornerRadius = 20
        closeButton.clipsToBounds = true
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        // ── Zoom label ────────────────────────────────────────────────
        zoomLabel.font = .systemFont(ofSize: 13, weight: .bold)
        zoomLabel.textColor = .white
        zoomLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        zoomLabel.textAlignment = .center
        zoomLabel.layer.cornerRadius = 13
        zoomLabel.clipsToBounds = true
        zoomLabel.alpha = 0
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomLabel)

        // ── Layout ───────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 26),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),

            zoomLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -120),
            zoomLabel.widthAnchor.constraint(equalToConstant: 64),
            zoomLabel.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    // MARK: - Gestures

    func setupGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapFocus(_:)))
        view.addGestureRecognizer(tap)
    }

    // MARK: - Actions

    @objc func closeTapped() {
        stopCameraSession()
        onClose?()
    }

    // MARK: - Zoom

    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device = videoDevice else { return }
        if gesture.state == .began { initialZoomFactor = device.videoZoomFactor }

        let maxZoom = min(5.0, device.activeFormat.videoMaxZoomFactor)
        let newZoom = min(max(initialZoomFactor * gesture.scale, 1.0), maxZoom)

        try? device.lockForConfiguration()
        device.videoZoomFactor = newZoom
        device.unlockForConfiguration()

        zoomLabel.text = String(format: "%.1fx", newZoom)
        zoomLabel.alpha = 1.0
        zoomTimer?.invalidate()
        zoomTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) { self?.zoomLabel.alpha = 0 }
        }
    }

    // MARK: - Focus

    @objc func handleTapFocus(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        guard let device = videoDevice else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        try? device.lockForConfiguration()
        if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
            device.focusPointOfInterest = devicePoint
            device.focusMode = .autoFocus
        }
        if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
            device.exposurePointOfInterest = devicePoint
            device.exposureMode = .autoExpose
        }
        device.unlockForConfiguration()
        showFocusRing(at: point)
    }

    private func showFocusRing(at point: CGPoint) {
        focusRingView?.removeFromSuperview()
        let size: CGFloat = 70
        let ring = UIView(frame: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
        ring.layer.borderColor = UIColor.orange.cgColor
        ring.layer.borderWidth = 2
        ring.layer.cornerRadius = 8
        ring.backgroundColor = .clear
        ring.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        view.addSubview(ring)
        focusRingView = ring

        UIView.animate(withDuration: 0.25, animations: {
            ring.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.4, delay: 0.3) { ring.alpha = 0 } completion: { _ in
                ring.removeFromSuperview()
            }
        }
    }
    
    // MARK: - Helper Frame Converter
    
    private func convertRect(_ rect: CGRect, fromImageOfSize imageSize: CGSize, toViewOfSize viewSize: CGSize) -> CGRect {
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let displayedWidth = imageSize.width * scale
        let displayedHeight = imageSize.height * scale
        let offsetX = (viewSize.width - displayedWidth) / 2
        let offsetY = (viewSize.height - displayedHeight) / 2
        
        return CGRect(
            x: rect.origin.x * scale + offsetX,
            y: rect.origin.y * scale + offsetY,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        )
    }

    // MARK: - Drawing Bounding Boxes
    
    private func drawBoundingBoxes(_ results: [DetectionResult], originalSize: CGSize) {
        guard let container = boundingBoxContainerView else { return }
        
        container.subviews.forEach { $0.removeFromSuperview() }
        
        let viewSize = container.bounds.size
        
        for result in results {
            let viewRect = convertRect(result.boundingBox, fromImageOfSize: originalSize, toViewOfSize: viewSize)
            
            let boxView = UIView(frame: viewRect)
            boxView.layer.borderColor = UIColor.orange.cgColor
            boxView.layer.borderWidth = 3
            boxView.layer.cornerRadius = 8
            boxView.backgroundColor = .clear
            
            let label = UILabel()
            label.text = String(format: "%@ %.0f%%", result.label, result.confidence * 100)
            label.font = .systemFont(ofSize: 12, weight: .bold)
            label.textColor = .white
            label.backgroundColor = .orange
            label.layer.cornerRadius = 4
            label.clipsToBounds = true
            label.sizeToFit()
            
            let labelWidth = label.frame.width + 8
            let labelHeight = label.frame.height + 4
            
            // Check if label fits above the box
            if viewRect.origin.y >= labelHeight + 6 {
                label.frame = CGRect(x: 0, y: -labelHeight, width: labelWidth, height: labelHeight)
            } else {
                label.frame = CGRect(x: 0, y: 0, width: labelWidth, height: labelHeight)
            }
            
            boxView.addSubview(label)
            container.addSubview(boxView)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension LiveCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isActive else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastInferenceTime) >= inferenceInterval else { return }
        
        queueLock.lock()
        if isProcessingLiveFrame {
            queueLock.unlock()
            return
        }
        isProcessingLiveFrame = true
        queueLock.unlock()
        
        lastInferenceTime = now
        
        Task {
            defer {
                queueLock.lock()
                isProcessingLiveFrame = false
                queueLock.unlock()
            }
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
            let image = UIImage(cgImage: cgImage)
            
            do {
                let results = try await ModelService.shared.detectDogs(in: image)
                await MainActor.run {
                    if self.isActive {
                        self.drawBoundingBoxes(results, originalSize: image.size)
                    }
                }
            } catch {
                print("Live inference error: \(error)")
            }
        }
    }
}
