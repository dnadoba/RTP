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

final class CaptureSession {
    enum Error: Swift.Error {
        case couldNoGetCaptureDevice
    }
    let session = AVCaptureSession()
    
    func setup() throws {
        guard let cameraDevice = AVCaptureDevice.default(for: .video) else {
            throw Error.couldNoGetCaptureDevice
        }
        let camerInput = try AVCaptureDeviceInput(device: cameraDevice)
        
        session.configure {
            $0.addInput(camerInput)
            $0.sessionPreset = .high
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


class ViewController: UIViewController {
    let videoController = VideoSessionController(endpoint: .hostPort(host: "192.168.188.29", port: 1234))
    var preview: PreviewView { self.view as! PreviewView }
    override func viewDidLoad() {
        super.viewDidLoad()
        preview.previewLayer.session = videoController.captureSession.session
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
        preview.previewLayer.connection?.videoOrientation = UIApplication.shared.statusBarOrientation.av
    }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: { (context) -> Void in
            self.updateVideoOrientation()
        })
        super.viewWillTransition(to: size, with: coordinator)
    }
}

