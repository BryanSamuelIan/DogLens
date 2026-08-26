import SwiftUI
import AVFoundation

struct ScannerView: UIViewControllerRepresentable {
    var onCapture: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onCapture = onCapture
        return vc
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

class CameraViewController: UIViewController {
    var captureSession: AVCaptureSession!
    var photoOutput: AVCapturePhotoOutput!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var videoDevice: AVCaptureDevice?
    var onCapture: ((UIImage?) -> Void)?
    
    private var initialZoomFactor: CGFloat = 1.0
    private let zoomLabel = UILabel()
    private var zoomTimer: Timer?
    private var focusRingView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
        setupGestures()
    }
    
    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        self.videoDevice = device
        
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: device)
        } catch {
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return
        }
        
        photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        } else {
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspect
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        view.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        if let connection = previewLayer?.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
    
    func setupUI() {
        // Zoom Label
        zoomLabel.font = .systemFont(ofSize: 13, weight: .bold)
        zoomLabel.textColor = .white
        zoomLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        zoomLabel.textAlignment = .center
        zoomLabel.layer.cornerRadius = 13
        zoomLabel.clipsToBounds = true
        zoomLabel.alpha = 0
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomLabel)

        // Capture Button (Native HIG Shutter Style)
        let captureButton = UIButton(type: .custom)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 36
        captureButton.layer.borderWidth = 5
        captureButton.layer.borderColor = UIColor.orange.cgColor
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(captureButton)

        // Close Button (HIG Translucent Circle with Bold X-mark)
        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        let xImage = UIImage(systemName: "xmark", withConfiguration: config)
        closeButton.setImage(xImage, for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closeButton.layer.cornerRadius = 20
        closeButton.clipsToBounds = true
        closeButton.addTarget(self, action: #selector(closeCamera), for: .touchUpInside)
        view.addSubview(closeButton)

        // Layout Constraints
        NSLayoutConstraint.activate([
            // Close Button (Top-Left, Safe Area compliant)
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),

            // Capture Button (Bottom Center, Safe Area compliant - positioned safely above home bar)
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            captureButton.widthAnchor.constraint(equalToConstant: 72),
            captureButton.heightAnchor.constraint(equalToConstant: 72),

            // Zoom Label (Centered above Capture Button)
            zoomLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomLabel.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
            zoomLabel.widthAnchor.constraint(equalToConstant: 64),
            zoomLabel.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    func setupGestures() {
        // Pinch gesture for zooming
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)

        // Tap gesture for autofocus
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapFocus(_:)))
        view.addGestureRecognizer(tapGesture)

        // Long press gesture for hold-to-autofocus
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressFocus(_:)))
        longPressGesture.minimumPressDuration = 0.3
        view.addGestureRecognizer(longPressGesture)
    }

    // MARK: - Zooming
    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device = videoDevice else { return }
        
        if gesture.state == .began {
            initialZoomFactor = device.videoZoomFactor
        }
        
        let maxZoom = min(5.0, device.activeFormat.videoMaxZoomFactor)
        let newZoomFactor = min(max(initialZoomFactor * gesture.scale, 1.0), maxZoom)
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = newZoomFactor
            device.unlockForConfiguration()
            showZoomLabel(zoom: newZoomFactor)
        } catch {
            print("Failed to set videoZoomFactor: \(error)")
        }
    }

    private func showZoomLabel(zoom: CGFloat) {
        zoomLabel.text = String(format: "%.1fx", zoom)
        zoomLabel.alpha = 1.0
        zoomTimer?.invalidate()
        zoomTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) {
                self?.zoomLabel.alpha = 0
            }
        }
    }

    // MARK: - Autofocus
    @objc func handleTapFocus(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        focus(at: location)
    }

    @objc func handleLongPressFocus(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            let location = gesture.location(in: view)
            focus(at: location)
        }
    }

    private func focus(at point: CGPoint) {
        guard let device = videoDevice, let previewLayer = previewLayer else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        do {
            try device.lockForConfiguration()
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
        } catch {
            print("Failed to set focusPointOfInterest: \(error)")
        }
    }

    private func showFocusRing(at point: CGPoint) {
        focusRingView?.removeFromSuperview()

        let ringSize: CGFloat = 70
        let ring = UIView(frame: CGRect(x: point.x - ringSize / 2, y: point.y - ringSize / 2, width: ringSize, height: ringSize))
        ring.layer.borderColor = UIColor.orange.cgColor
        ring.layer.borderWidth = 2
        ring.layer.cornerRadius = 8
        ring.backgroundColor = .clear
        ring.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        ring.alpha = 1.0

        view.addSubview(ring)
        self.focusRingView = ring

        UIView.animate(withDuration: 0.25, animations: {
            ring.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.4, delay: 0.3, options: [], animations: {
                ring.alpha = 0
            }) { _ in
                ring.removeFromSuperview()
            }
        }
    }

    // MARK: - Photo Capture
    @objc func capturePhoto() {
        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    @objc func closeCamera() {
        dismiss(animated: true)
    }
}

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            onCapture?(image)
            dismiss(animated: true)
        }
    }
}
