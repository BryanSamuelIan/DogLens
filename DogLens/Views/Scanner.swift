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
    var onCapture: ((UIImage?) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }
    
    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            return
        }
        
        photoOutput = AVCapturePhotoOutput()
        if (captureSession.canAddOutput(photoOutput)) {
            captureSession.addOutput(photoOutput)
        } else {
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    func setupUI() {
        let captureButton = UIButton(frame: CGRect(x: (view.frame.width - 70) / 2, y: view.frame.height - 120, width: 70, height: 70))
        captureButton.layer.cornerRadius = 35
        captureButton.backgroundColor = .white
        captureButton.layer.borderWidth = 5
        captureButton.layer.borderColor = UIColor.orange.cgColor
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(captureButton)
        
        let closeButton = UIButton(frame: CGRect(x: 20, y: 50, width: 40, height: 40))
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeCamera), for: .touchUpInside)
        view.addSubview(closeButton)
    }
    
    @objc func capturePhoto() {
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
