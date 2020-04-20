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

final class RTPH264Sender {
    private let queue = DispatchQueue(label: "de.nadoba.\(RTPH264Sender.self)")
    private let item: AVPlayerItem
    private let player: AVPlayer
    private let timer: RepeatingTimer
    private let encoder: VideoEncoder
    private let output: AVPlayerItemVideoOutput
    private let frameDuration: CMTime
    private let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1234), using: .udp)
    private var rtpSerialzer: RTPSerialzer
    private var h264Serialzer: H264.NALNonInterleavedPacketSerializer<Data>
    
    init() {
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
        
        rtpSerialzer = .init(maxSizeOfPacket: connection.maximumDatagramSize, synchronisationSource: RTPSynchronizationSource(rawValue: .random(in: UInt32.min...UInt32.max)))
        h264Serialzer = .init(maxSizeOfNalu: rtpSerialzer.maxSizeOfPayload)
        
        encoder = try! VideoEncoder(
            width: Int(size.width),
            height: Int(size.height),
            codec: .h264,
            encoderSpecification: [
                kVTCompressionPropertyKey_AllowFrameReordering: false,
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true,
                kVTCompressionPropertyKey_RealTime: true,
            ],
            imageBufferAttributes: nil)
        
        encoder.callback = { [weak self] buffer, flags in
            self?.sendBuffer(buffer)
        }
        
        timer.eventHandler = { [weak self] in
            self?.eventHandler()
        }
        
        connection.start(queue: queue)
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
        do {
            try encoder.encodeFrame(imageBuffer: buffer, presentationTimeStamp: displayTime, duration: frameDuration, frameProperties: [:
                //kVTEncodeFrameOptionKey_ForceKeyFrame: true,
            ])
        } catch {
            print(error, #file, #line)
        }
    }
    
    
    private func sendBuffer(_ sampleBuffer: CMSampleBuffer) {
        let nalus = sampleBuffer.convertToH264NALUnitsAndAddPPSAndSPSIfNeeded(dataType: Data.self)
        
        let timestamp = UInt32(sampleBuffer.presentationTimeStamp.convertScale(90_000, method: .default).value)
        sendNalus(nalus, timestamp: timestamp)
    }
    private func sendNalus(_ nalus: [H264.NALUnit<Data>], timestamp: UInt32) {
        guard connection.maximumDatagramSize > 0 else { return }
        rtpSerialzer.maxSizeOfPacket = 9216
        h264Serialzer.maxSizeOfNaluPacket = rtpSerialzer.maxSizeOfPayload
        do {
            let packets = try h264Serialzer.serialize(nalus, timestamp: timestamp, lastNALUsForGivenTimestamp: true)
            connection.batch {
                for packet in packets {
                    do {
                        let data: Data = try rtpSerialzer.serialze(packet)
                        connection.send(content: data, completion: .idempotent)
                    } catch {
                        print(error, #file, #line)
                    }
                }
            }
        } catch {
            print(error, #file, #line)
        }
    }
}

extension CMSampleBuffer {
    func convertToH264NALUnitsAndAddPPSAndSPSIfNeeded<D>(dataType: D.Type = D.self) -> [H264.NALUnit<D>] where D: MutableDataProtocol, D.Index == Int {
        var nalus = self.convertToH264NALUnits(dataType: D.self)
        if nalus.contains(where: { $0.header.type == H264.NALUnitType.instantaneousDecodingRefreshCodedSlice }),
            let formatDescription = self.formatDescription {
            let parameterSet = formatDescription.h264ParameterSets(dataType: D.self)
            nalus.insert(contentsOf: parameterSet, at: 0)
        }
        return nalus
    }
    func convertToH264NALUnits<D>(dataType: D.Type = D.self) -> [H264.NALUnit<D>] where D: MutableDataProtocol, D.Index == Int {
        var nalus = [H264.NALUnit<D>]()
        CMSampleBufferCallBlockForEachSample(self) { (buffer, count) -> OSStatus in
            if let dataBuffer = buffer.dataBuffer, let formatDescription = formatDescription  {
                do {
                    let newNalus = try dataBuffer.withContiguousStorage { storage -> [H264.NALUnit<D>] in
                        let storage = storage.bindMemory(to: UInt8.self)
                        var reader = BinaryReader(bytes: storage)
                        var newNalus = [H264.NALUnit<D>]()
                        let nalUnitHeaderLength = formatDescription.nalUnitHeaderLength
                        while !reader.isEmpty {
                            let length = try reader.readInteger(byteCount: Int(nalUnitHeaderLength), type: UInt64.self)
                            let header = try H264.NALUnitHeader(from: &reader)
                            let payload = D(try reader.readBytes(Int(length) - 1))
                            newNalus.append(H264.NALUnit<D>(header: header, payload: payload))
                        }
                        return newNalus
                    }
                    nalus.append(contentsOf: newNalus)
                } catch {
                    print(error, #file, #line)
                }
            }
            return kOSReturnSuccess
        }
        return nalus
    }
}

extension CMFormatDescription {
    var nalUnitHeaderLength: Int32 {
        var nalUnitHeaderLength: Int32 = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(self, parameterSetIndex: -1, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: nil, nalUnitHeaderLengthOut: &nalUnitHeaderLength)
        return nalUnitHeaderLength
    }
    func h264ParameterSets<D>(dataType: D.Type = D.self) -> [H264.NALUnit<D>] where D: MutableDataProtocol, D.Index == Int {
        var nalus = [H264.NALUnit<D>]()
        var count = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(self, parameterSetIndex: -1, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
        for index in 0..<count {
            do {
                var pointerOut: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(self, parameterSetIndex: index, parameterSetPointerOut: &pointerOut, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                if let pointerOut = pointerOut {
                    let data = D(UnsafeBufferPointer(start: pointerOut, count: size))
                    var reader = BinaryReader(bytes: data)
                    let nalu = H264.NALUnit(header: try .init(from: &reader), payload: D(try reader.readRemainingBytes()))
                    nalus.append(nalu)
                } else {
                    print("could not get H264ParameterSet")
                }
            } catch {
                print(error, #file, #line)
            }
        }
        return nalus
    }
}
