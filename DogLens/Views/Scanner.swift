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
        zoomLabel.font = .systemFont(ofSize: 14, weight: .bold)
        zoomLabel.textColor = .white
        zoomLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        zoomLabel.textAlignment = .center
        zoomLabel.layer.cornerRadius = 14
        zoomLabel.clipsToBounds = true
        zoomLabel.frame = CGRect(x: (view.frame.width - 60) / 2, y: view.frame.height - 180, width: 60, height: 28)
        zoomLabel.alpha = 0
        view.addSubview(zoomLabel)

        // Capture Button
        let captureButton = UIButton(frame: CGRect(x: (view.frame.width - 70) / 2, y: view.frame.height - 120, width: 70, height: 70))
        captureButton.layer.cornerRadius = 35
        captureButton.backgroundColor = .white
        captureButton.layer.borderWidth = 5
        captureButton.layer.borderColor = UIColor.orange.cgColor
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(captureButton)
        
        // Close Button
        let closeButton = UIButton(frame: CGRect(x: 20, y: 50, width: 40, height: 40))
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeCamera), for: .touchUpInside)
        view.addSubview(closeButton)
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
