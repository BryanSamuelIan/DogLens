import SwiftUI
import AVFoundation

// MARK: - SwiftUI Representable

struct VideoScannerView: UIViewControllerRepresentable {
    var onRecordingFinished: (URL) -> Void
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> VideoCameraViewController {
        let vc = VideoCameraViewController()
        vc.onRecordingFinished = onRecordingFinished
        vc.onClose = onClose
        return vc
    }

    func updateUIViewController(_ uiViewController: VideoCameraViewController, context: Context) {}
}

// MARK: - UIKit Camera Controller

class VideoCameraViewController: UIViewController {

    // MARK: AV
    var captureSession: AVCaptureSession!
    var movieOutput: AVCaptureMovieFileOutput!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var videoDevice: AVCaptureDevice?

    // MARK: Callbacks
    var onRecordingFinished: ((URL) -> Void)?
    var onClose: (() -> Void)?

    // MARK: State
    private var isRecording = false
    private var recordingSeconds = 0
    private var recordingTimer: Timer?
    private var initialZoomFactor: CGFloat = 1.0
    private var zoomTimer: Timer?
    private var focusRingView: UIView?
    private weak var innerCircle: UIView?

    // MARK: UI
    private let recordButton  = UIButton(type: .custom)
    private let timerLabel    = UILabel()
    private let closeButton   = UIButton(type: .system)
    private let zoomLabel     = UILabel()

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
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isRecording { stopRecording() }
        captureSession?.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        if let conn = previewLayer?.connection { setPortraitOrientation(on: conn) }
    }

    // MARK: - Camera Setup

    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720

        // Video input
        guard let vDevice = AVCaptureDevice.default(for: .video),
              let vInput = try? AVCaptureDeviceInput(device: vDevice),
              captureSession.canAddInput(vInput) else { return }
        captureSession.addInput(vInput)
        videoDevice = vDevice

        // Audio input
        if let aDevice = AVCaptureDevice.default(for: .audio),
           let aInput = try? AVCaptureDeviceInput(device: aDevice),
           captureSession.canAddInput(aInput) {
            captureSession.addInput(aInput)
        }

        // Movie output
        movieOutput = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
            // Orient movie connection
            if let conn = movieOutput.connection(with: .video) {
                setPortraitOrientation(on: conn)
            }
        }
        captureSession.commitConfiguration()

        // Preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        if let conn = previewLayer.connection { setPortraitOrientation(on: conn) }
        view.layer.addSublayer(previewLayer)

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

        // ── Timer label ───────────────────────────────────────────────
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        timerLabel.textColor = .white
        timerLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        timerLabel.textAlignment = .center
        timerLabel.layer.cornerRadius = 10
        timerLabel.clipsToBounds = true
        timerLabel.alpha = 0
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timerLabel)

        // ── Record button (outer ring) ────────────────────────────────
        recordButton.backgroundColor = .clear
        recordButton.layer.borderColor = UIColor.white.cgColor
        recordButton.layer.borderWidth = 4
        recordButton.layer.cornerRadius = 36
        recordButton.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recordButton)

        // Inner red circle
        let inner = UIView()
        inner.backgroundColor = .systemRed
        inner.layer.cornerRadius = 26
        inner.isUserInteractionEnabled = false
        inner.translatesAutoresizingMaskIntoConstraints = false
        recordButton.addSubview(inner)
        innerCircle = inner

        NSLayoutConstraint.activate([
            inner.centerXAnchor.constraint(equalTo: recordButton.centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            inner.widthAnchor.constraint(equalToConstant: 52),
            inner.heightAnchor.constraint(equalToConstant: 52),
        ])

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
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),

            timerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 22),
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            timerLabel.heightAnchor.constraint(equalToConstant: 28),

            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            recordButton.widthAnchor.constraint(equalToConstant: 72),
            recordButton.heightAnchor.constraint(equalToConstant: 72),

            zoomLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -20),
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

    @objc func closeTapped() { onClose?() }

    @objc func recordTapped() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        if let conn = movieOutput.connection(with: .video) { setPortraitOrientation(on: conn) }
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        isRecording = true
        recordingSeconds = 0

        UIView.animate(withDuration: 0.2) { self.timerLabel.alpha = 1 }
        updateTimerLabel()

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recordingSeconds += 1
            self.updateTimerLabel()
        }

        animateInnerCircle(toStop: true)
    }

    private func stopRecording() {
        movieOutput.stopRecording()
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        UIView.animate(withDuration: 0.2) { self.timerLabel.alpha = 0 }
        animateInnerCircle(toStop: false)
    }

    private func updateTimerLabel() {
        let m = recordingSeconds / 60
        let s = recordingSeconds % 60
        timerLabel.text = String(format: " ⏺  %d:%02d ", m, s)
    }

    private func animateInnerCircle(toStop: Bool) {
        guard let inner = innerCircle else { return }
        UIView.animate(withDuration: 0.35,
                       delay: 0,
                       usingSpringWithDamping: 0.65,
                       initialSpringVelocity: 0.5,
                       options: []) {
            inner.layer.cornerRadius = toStop ? 6 : 26
            inner.transform = toStop ? CGAffineTransform(scaleX: 0.58, y: 0.58) : .identity
        }
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
        ring.layer.borderColor = UIColor.systemRed.cgColor
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
}

// MARK: - Recording Delegate

extension VideoCameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async {
            if let error {
                print("Video recording error: \(error.localizedDescription)")
                return
            }
            self.onRecordingFinished?(outputFileURL)
        }
    }
}
