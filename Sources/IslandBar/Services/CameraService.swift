@preconcurrency import AVFoundation
import Combine
import Foundation
import SwiftUI

final class CameraService: ObservableObject {
    enum State: Equatable {
        case idle
        case requesting
        case ready
        case denied
        case unavailable
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "local.islandbar.camera", qos: .userInitiated)
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            state = .requesting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.configureAndStart() } else { self.state = .denied }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndStart() {
        state = .requesting
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .medium
                guard let device = AVCaptureDevice.default(for: .video) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.state = .unavailable }
                    return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else {
                        self.session.commitConfiguration()
                        DispatchQueue.main.async { self.state = .unavailable }
                        return
                    }
                    self.session.addInput(input)
                    self.configured = true
                    self.session.commitConfiguration()
                } catch {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.state = .failed(error.localizedDescription) }
                    return
                }
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.state = .ready }
        }
    }
}

final class CameraPreviewNSView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView(session: session)
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.previewLayer.session = session
    }
}
