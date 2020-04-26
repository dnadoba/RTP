//
//  ViewController.swift
//  RTP iOS
//
//  Created by David Nadoba on 20.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import UIKit
import AVFoundation
import RTPAVKit
import Network

extension AVCaptureSession {
    func configure<Result>(_ configure: (AVCaptureSession) throws -> Result) rethrows -> Result {
        self.beginConfiguration()
        defer { self.commitConfiguration() }
        return try configure(self)
    }
}

extension AVCaptureDevice {
    func configure<Result>(_ configure: (AVCaptureDevice) throws -> Result) throws -> Result {
        try self.lockForConfiguration()
        defer { self.unlockForConfiguration() }
        return try configure(self)
    }
}

extension CMTime {
    init(frameRate: Double) {
        self.init(value: 10000, timescale: Int32(frameRate * 10000))
    }
}

final class CaptureSession {
    enum Error: Swift.Error {
        case couldNoGetCaptureDevice
        case couldNotFindRequestedFormat
    }
    let session = AVCaptureSession()
    private(set) var activeInput: AVCaptureDeviceInput?
    
    func setup() throws {
        
    }
    
    func setCamera(_ camera: Camera.ID, format: CameraFormat, frameRate: Double) throws {
        
        guard let camera = AVCaptureDevice(uniqueID: camera) else {
            throw Error.couldNoGetCaptureDevice
        }
        
        guard let format = camera.formats.first(where: { CameraFormat($0) == format }) else {
            throw Error.couldNotFindRequestedFormat
        }
    
        try camera.configure {
            $0.activeFormat = format
            $0.activeVideoMaxFrameDuration = CMTime(frameRate: max(frameRate/2, 15))
            $0.activeVideoMinFrameDuration = CMTime(frameRate: frameRate)
        }
        
        // switch active camera if needed
        try setActiveInputIfNeeded(camera)
    }
    private func setActiveInputIfNeeded(_ device: AVCaptureDevice) throws{
        if device != activeInput?.device {
            let camerInput = try AVCaptureDeviceInput(device: device)
            
            session.configure {
                if let oldInput = activeInput {
                    $0.removeInput(oldInput)
                }
                activeInput = nil
                $0.addInput(camerInput)
                $0.sessionPreset = .inputPriority
            }
            self.activeInput = camerInput
        }
    }
    func start() throws {
        session.startRunning()
    }
}

final class VideoSessionController: NSObject {
    let output = AVCaptureVideoDataOutput()
    let sampleQueue = DispatchQueue(label: "de.nadoba.\(CaptureSession.self)", qos: .userInteractive)
    private let sender: RTPH264Sender
    let captureSession: CaptureSession = .init()
    init(endpoint: NWEndpoint) {
        sender = RTPH264Sender(endpoint: endpoint, targetQueue: sampleQueue)
        super.init()
        captureSession.session.configure {
            $0.addOutput(output)
        }
        
        output.setSampleBufferDelegate(self, queue: sampleQueue)
    }
    
    func setCamera(_ camera: Camera.ID, format: CameraFormat, frameRate: Double) throws {
        try captureSession.setCamera(camera, format: format, frameRate: frameRate)
    }
    
    func setup() throws {
        try captureSession.setup()
    }
    func start() throws {
        try captureSession.start()
    }
}

extension VideoSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("did drop sample buffer")
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let presentationTime = sampleBuffer.presentationTimeStamp
        guard let image = sampleBuffer.imageBuffer else { return }
        sender.encodeAndSendFrame(image, presentationTimeStamp: presentationTime, frameDuration: .invalid)
    }
}

class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { self.layer as! AVCaptureVideoPreviewLayer }
}
extension UIInterfaceOrientation {
    var av: AVCaptureVideoOrientation {
        switch self {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }
}

import Combine


class ViewController: UIViewController {
    private static let settingsSegueId = "Open Settings"
    
    let videoController = VideoSessionController(endpoint: .hostPort(host: "192.168.188.29", port: 1234))
    let settingsViewModel = CameraSettingsViewModel()
    @IBOutlet private weak var preview: PreviewView!
    private var settingsViewModelCancelable: AnyCancellable?
    override func viewDidLoad() {
        super.viewDidLoad()
        preview.previewLayer.session = videoController.captureSession.session
        
        settingsViewModelCancelable = settingsViewModel.$selectedCamera
            .combineLatest(settingsViewModel.$selectedFormat, settingsViewModel.$preferedFrameRate)
            .debounce(for: .milliseconds(1), scheduler: RunLoop.main)
            .sink(receiveValue: { [weak self] camera, format, _ in
                
                guard let camera = camera, let format = format, let frameRate = self?.settingsViewModel.effectiveFrameRate else { return }
                do {
                    try self?.videoController.setCamera(camera, format: format, frameRate: frameRate)
                } catch {
                    print(error)
                }
            })
            
        do {
            try videoController.setup()
            try videoController.start()
        } catch {
            print(error, #file, #line)
        }
    }
    override func viewWillAppear(_ animated: Bool) {
        updateVideoOrientation()
        super.viewWillAppear(animated)
    }
    private func updateVideoOrientation() {
        // UIApplication.shared.statusBarOrientation is deprecated but I could not find an alternativ
        // UIDevice.current.orientation does not work as expected on startup
        preview.previewLayer.connection?.videoOrientation = UIApplication.shared.statusBarOrientation.av
    }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: { (context) -> Void in
            self.updateVideoOrientation()
        })
        super.viewWillTransition(to: size, with: coordinator)
    }
    @IBSegueAction func settingsSegue(_ coder: NSCoder) -> UIViewController? {
        return CameraSelectionViewController(coder: coder, viewModel: settingsViewModel)
    }
    @IBAction func openSettings(_ sender: Any) {
        self.performSegue(withIdentifier: Self.settingsSegueId, sender: sender)
    }
}

