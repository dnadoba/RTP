//
//  ViewController.swift
//  RTPViewer
//
//  Created by David Nadoba on 09.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import Cocoa
import Network
import AVFoundation

class VideoView: NSView {
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    override func makeBackingLayer() -> CALayer {
        AVSampleBufferDisplayLayer()
    }
}

class ViewController: NSViewController {
    var reciever: RTPH264Reciever?
    var videoView: VideoView { view as! VideoView }
    override func viewDidLoad() {
        super.viewDidLoad()
        reciever = RTPH264Reciever(host: "127.0.0.1", port: 1234)
        //reciever = RTPH264Reciever(host: "224.0.0.1", port: 1234)
        reciever?.callback = { buffer in
            DispatchQueue.main.async {
                self.videoView.displayLayer.enqueue(buffer)
            }
        }
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    deinit {
        print("deinit \(ViewController.self)")
    }
}

