//
//  ViewController.swift
//  RTP iOS
//
//  Created by David Nadoba on 20.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import UIKit
import AVFoundation

final class CaptureSession: NSObject {
    enum Error: Swift.Error {
        case couldNoGetCaptureDevice
    }
    let session = AVCaptureSession()
    let output = AVCaptureVideoDataOutput()
    let sampleQueue = DispatchQueue(label: "de.nadoba.\(CaptureSession.self)", qos: .userInteractive)
    override init() {
        super.init()
        output.setSampleBufferDelegate(self, queue: sampleQueue)
    }
    func setup() throws {
        guard let cameraDevice = AVCaptureDevice.default(for: .video) else {
            throw Error.couldNoGetCaptureDevice
        }
        let camerInput = try AVCaptureDeviceInput(device: cameraDevice)
        
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        session.addInput(camerInput)
        session.addOutput(output)
        session.sessionPreset = .high
    }
    func start() {
        session.startRunning()
    }
}

extension CaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("did drop sample buffer")
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
    }
}

class ViewController: UIViewController {
    let captureSession = CaptureSession()
    override func viewDidLoad() {
        super.viewDidLoad()
        captureSession.start()
    }


}

