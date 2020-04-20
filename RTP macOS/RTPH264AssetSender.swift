//
//  RTPH264Sender.swift
//  RTPViewer
//
//  Created by David Nadoba on 17.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import Foundation
import VideoToolbox
import SwiftRTP
import BinaryKit
import RTPAVKit

import AVFoundation
import Network

final class RTPH264AssetSender {
    private let queue = DispatchQueue(label: "de.nadoba.\(RTPH264AssetSender.self)")
    private let item: AVPlayerItem
    private let player: AVPlayer
    private let timer: RepeatingTimer
    private let output: AVPlayerItemVideoOutput
    private let frameDuration: CMTime
    private let sender: RTPH264Sender
    
    init(endpoint: NWEndpoint) {
        sender = RTPH264Sender(endpoint: endpoint, targetQueue: queue)
        let asset = AVAsset(url: Bundle.main.url(forResource: "SalesPerSecond(1)", withExtension: ".mov")!)
        let track = asset.tracks(withMediaCharacteristic: .visual).first!
        let frameRate = track.nominalFrameRate
        let size = track.naturalSize
        let duration = asset.duration.seconds
        frameDuration = CMTime(seconds: Double(1/frameRate), preferredTimescale: 60_000)
        
        output = AVPlayerItemVideoOutput()
        item = AVPlayerItem(asset: asset)
        item.add(output)
        
        
        player = AVPlayer(playerItem: item)
        
        timer = RepeatingTimer(refreshRate: Double(frameRate), queue: queue)
        
        sender.setupEncoderIfNeeded(width: Int(size.width), height: Int(size.height))
        
        timer.eventHandler = { [weak self] in
            self?.eventHandler()
        }
        
        let loopTimer = Timer.init(timeInterval: duration, repeats: true) { _ in
            self.player.pause()
            self.player.seek(to: .zero)
            self.player.play()
        }
        let startDelayTimer = Timer.init(timeInterval: 0.5, repeats: false) { _ in
            self.timer.resume()
            self.player.play()
            RunLoop.main.add(loopTimer, forMode: .common)
        }
        RunLoop.main.add(startDelayTimer, forMode: .common)
    }
    
    private func eventHandler() {
        var displayTime = CMTime()
        guard let buffer = output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: &displayTime) else {
            print("could not copy pixel buffer")
            return
        }
        sender.encodeAndSendFrame(buffer, presentationTimeStamp: displayTime, frameDuration: frameDuration)
    }
}
