//
//  RTPH264Reciever.swift
//  RTPViewer
//
//  Created by David Nadoba on 10.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import Foundation
import Network
import SwiftRTP
import BinaryKit
import Dispatch
import VideoToolbox

//struct VideoDecoder {
//    typealias Callback = () -> ()
//    fileprivate var session: VTDecompressionSession
//    var callback: Callback?
//    init(formatDescription: CMVideoFormatDescription) throws {
//        var session: VTDecompressionSession?
//        let callback = VTDecompressionOutputCallbackRecord(
//            decompressionOutputCallback: { (decompressionOutputRefCon, sourceFrameRefCon, status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration) in
//                guard status == kOSReturnSuccess else {
//                    print(OSStatusError(osStatus: status, description: "VTDecompressionOutputCallbackRecord"))
//                    return
//                }
//        },
//            decompressionOutputRefCon: nil)
//        let status = VTDecompressionSessionCreate(
//            allocator: nil, formatDescription: formatDescription,
//            decoderSpecification: nil,
//            imageBufferAttributes: nil,
//            outputCallback: callback, decompressionSessionOut: &session)
//        guard status == kOSReturnSuccess, let unwrapedSession = session else {
//            throw OSStatusError(osStatus: status, description: "failed to create \(VTDecompressionSession.self) from \(formatDescription)")
//        }
//        self.session = unwrapedSession
//    }
//    private func decompressionOutputCallback(imageBuffer: CVPixelBuffer?, presentationTimeStamp: CMTime, presentationDuration: CMTime) {
//
//    }
//}

final class RTPH264Reciever {
    typealias Callback = (CMSampleBuffer) -> ()
    var connection: NWConnection?
    let queue = DispatchQueue(label: "de.nadoba.\(RTPH264Reciever.self).udp")
    let listen: NWListener
    var callback: Callback?
    init(host: NWEndpoint.Host, port: NWEndpoint.Port) {
        let parameters = NWParameters.udp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: host, port: port)
        listen = try! NWListener(using: parameters)
        
//        connection.stateUpdateHandler = {
//            print($0)
//            if $0 == .ready {
//                self.scheduleReciveMessage(connection: self.connection)
//            }
//        }
//        connection.start(queue: queue)
//        queue.async {
//            self.scheduleReciveMessage(connection: self.connection)
//        }
        
        listen.newConnectionHandler = { connection in
            
            connection.start(queue: self.queue)
            self.scheduleReciveMessage(connection: connection)
            
        }
        listen.start(queue: queue)
    }
    
    func scheduleReciveMessage(connection: NWConnection) {
//        connection.receive(minimumIncompleteLength: 1, maximumLength: Int(UInt32.max)) { [weak self] (data, context, isComplete, error) in
//            guard let self = self else { return }
//            defer {
//                self.scheduleReciveMessage(connection: connection)
//            }
//            guard isComplete else { return }
//            if let error = error {
//                print(error)
//                return
//            }
//            guard let data = data else {
//                print("recive message is complete and no error but also no data")
//                return
//            }
//            self.didReciveData(data)
//        }
        connection.receiveMessage { [weak self] (data, context, isComplete, error) in
            guard let self = self else { return }
            defer {
                self.scheduleReciveMessage(connection: connection)
            }
            guard isComplete else {
                print("did recieve incomplete message")
                return
            }
            if let error = error {
                print(error)
                return
            }
            guard let data = data else {
                print("recive message is complete and no error but also no data")
                return
            }
            self.didReciveData(data)
        }
    }
    private func didReciveData(_ data: Data) {
        do {
            try parse(data)
        } catch {
            print(error)
        }
    }
    private var h264Parser = H264.NALNonInterleavedPacketParser<Data>()
    var prevSequenceNumber: UInt16?
    private func parse(_ data: Data) throws {
        var reader = BinaryReader(bytes: data)
        let header = try RTPHeader(reader: &reader)
        defer { prevSequenceNumber = header.sequenceNumber }
        if let prevSequenceNumber = prevSequenceNumber,
        prevSequenceNumber >= header.sequenceNumber && prevSequenceNumber != UInt16.max {
            print("packets in wrong order prevSequenceNumber: \(prevSequenceNumber) current: \(header.sequenceNumber)")
        }
        if let prevSequenceNumber = prevSequenceNumber,
            abs(Int(header.sequenceNumber) - Int(prevSequenceNumber)) != 1 {
            print("packet lost prevSequenceNumber: \(prevSequenceNumber) current: \(header.sequenceNumber)")
        }
        let nalUnits = try h264Parser.readPackage(from: &reader)
        if !nalUnits.isEmpty {
            didReciveNALUnits(nalUnits, header: header)
        }
    }
    
    private var sequenceParameterSet: H264.NALUnit<Data>?
    private var pictureParameterSet: H264.NALUnit<Data>?
    private var formatDescription: CMVideoFormatDescription?
    private func didReciveNALUnits(_ nalus: [H264.NALUnit<Data>], header: RTPHeader) {
        for nalu in nalus {
            self.didReciveNALUnit(nalu, header: header)
        }
        
    }
    private func didReciveNALUnit(_ nalu: H264.NALUnit<Data>, header: RTPHeader) {
        if nalu.header.type == .sequenceParameterSet {
            sequenceParameterSet = nalu
            formatDescription = nil
        }
        if nalu.header.type == .pictureParameterSet {
            pictureParameterSet = nalu
            formatDescription = nil
        }
        if formatDescription == nil,
            let sequenceParameterSet = self.sequenceParameterSet,
            let pictureParameterSet = self.pictureParameterSet {
            do {
                formatDescription = try CMVideoFormatDescriptionCreateForH264From(
                    sequenceParameterSet: sequenceParameterSet,
                    pictureParameterSet: pictureParameterSet
                )
            } catch {
                print(error)
            }
        }
        guard let formatDescription = formatDescription else {
            print("did recieve nalu of type \(nalu.header.type) before formatDescription is ready")
            return
        }
        if nalu.header.type.shouldSendToDecoder {
            print(nalu.header.type, nalu.payload.count)
            do {
                let buffer = try sampleBufferFromNalu(nalu, header: header, formatDescription: formatDescription)
                callback?(buffer)
            } catch {
                print(error)
            }
        }
    }
}

extension H264.NALUnitType {
    var shouldSendToDecoder: Bool {
        return self.isSinglePacket && self != .pictureParameterSet && self != .sequenceParameterSet && rawValue != 6
    }
}

import CoreMedia

struct OSStatusError: Error {
    var osStatus: OSStatus
    var description: String = "none"
}
func CMVideoFormatDescriptionCreateForH264From(sequenceParameterSet: H264.NALUnit<Data>, pictureParameterSet: H264.NALUnit<Data>) throws -> CMVideoFormatDescription? {
    try sequenceParameterSet.bytes.withUnsafeBytes { (sequenceParameterPointer: UnsafeRawBufferPointer) in
        try pictureParameterSet.bytes.withUnsafeBytes { (pictureParameterPointers: UnsafeRawBufferPointer) in
            let parameterBuffers = [
                sequenceParameterPointer,
                pictureParameterPointers,
            ]
            let parameters = parameterBuffers.map({ $0.baseAddress!.assumingMemoryBound(to: UInt8.self) })
            let paramterSizes = parameterBuffers.map(\.count)
            var formatDescription: CMFormatDescription?

            let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: nil,
                parameterSetCount: parameters.count,
                parameterSetPointers: parameters,
                parameterSetSizes: paramterSizes,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &formatDescription)
            guard status == kOSReturnSuccess, let unwrapedFormatDescription = formatDescription else {
                throw OSStatusError(osStatus: status)
            }
            return unwrapedFormatDescription
        }
    }
}

private func freeBlock(_ refCon: UnsafeMutableRawPointer?, doomedMemoryBlock: UnsafeMutableRawPointer, sizeInBytes: Int) -> Void {
    let unmanagedData = Unmanaged<NSData>.fromOpaque(refCon!)
    unmanagedData.release()
}

public extension DispatchData {
    func toCMBlockBuffer() throws -> CMBlockBuffer {
        return try self.withUnsafeBytes {
            (pointer: UnsafePointer<UInt8>) -> CMBlockBuffer in
            
            let data = NSMutableData(bytes: pointer, length: count)
            
            var source = CMBlockBufferCustomBlockSource()
            source.refCon = Unmanaged.passRetained(data).toOpaque()
            source.FreeBlock = freeBlock
            
            
            var blockBuffer: CMBlockBuffer?
            
            let result = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,        // structureAllocator
                memoryBlock: data.mutableBytes,          // memoryBlock
                blockLength: data.length,                // blockLength
                blockAllocator: kCFAllocatorNull,           // blockAllocator
                customBlockSource: &source,                    // customBlockSource
                offsetToData: 0,                          // offsetToData
                dataLength: data.length,                // dataLength
                flags: 0,                          // flags
                blockBufferOut: &blockBuffer)               // newBBufOut
            if OSStatus(result) != kCMBlockBufferNoErr {
                throw OSStatusError(osStatus: result, description: "CMBlockBufferCreateWithMemoryBlock")
            }
            
            assert(CMBlockBufferGetDataLength(blockBuffer!) == data.length)
            return blockBuffer!
        }
    }
}

fileprivate let h264ClockRate: Int32 = 90_000

func sampleBufferFromNalu(_ nalu: H264.NALUnit<Data>, header: RTPHeader, formatDescription: CMFormatDescription) throws -> CMSampleBuffer {
    // Prepend the size of the data to the data as a 32-bit network endian uint. (keyword: "elementary stream")
    let offset = 0
    let size = UInt32((nalu.payload.count - offset) + 1)
    
    let prefix = size.toNetworkByteOrder.data + Data([nalu.header.byte])
    var data = prefix.withUnsafeBytes{ (header) in
        DispatchData(bytes: header)
    }
    assert(data.count == 5)
    nalu.payload.withUnsafeBytes { (payload) in
       
        let payload = UnsafeRawBufferPointer(start: payload.baseAddress!.advanced(by: offset), count: payload.count - offset)
        data.append(payload)
    }
    assert(data.count == size + 4)
    
    let blockBuffer = try data.toCMBlockBuffer()

    // So what about STAP???? From CMSampleBufferCreate "Behavior is undefined if samples in a CMSampleBuffer (or even in multiple buffers in the same stream) have the same presentationTimeStamp"

    // Computer the duration and time
    let duration = CMTime.invalid // CMTimeMake(3000, H264ClockRate) // TODO: 1/30th of a second. Making this up.

    let time = CMTime(value: Int64(header.timestamp), timescale: h264ClockRate)
    //let time = CMClockGetHostTimeClock().time
    // Inputs to CMSampleBufferCreate
    let timingInfo: [CMSampleTimingInfo] = [CMSampleTimingInfo(duration: duration, presentationTimeStamp: time, decodeTimeStamp: time)]
    let sampleSizes: [Int] = [CMBlockBufferGetDataLength(blockBuffer)]

    // Outputs from CMSampleBufferCreate
    var sampleBuffer: CMSampleBuffer?

    let result = CMSampleBufferCreate(
        allocator: kCFAllocatorDefault,            // allocator: CFAllocator?,
        dataBuffer: blockBuffer,                    // dataBuffer: CMBlockBuffer?,
        dataReady: true,                           // dataReady: Boolean,
        makeDataReadyCallback: nil,                            // makeDataReadyCallback: CMSampleBufferMakeDataReadyCallback?,
        refcon: nil,                            // makeDataReadyRefcon: UnsafeMutablePointer<Void>,
        formatDescription: formatDescription,              // formatDescription: CMFormatDescription?,
        sampleCount: 1,                              // numSamples: CMItemCount,
        sampleTimingEntryCount: timingInfo.count,               // numSampleTimingEntries: CMItemCount,
        sampleTimingArray: timingInfo,                     // sampleTimingArray: UnsafePointer<CMSampleTimingInfo>,
        sampleSizeEntryCount: sampleSizes.count,              // numSampleSizeEntries: CMItemCount,
        sampleSizeArray: sampleSizes,                    // sampleSizeArray: UnsafePointer<Int>,
        sampleBufferOut: &sampleBuffer                   // sBufOut: UnsafeMutablePointer<Unmanaged<CMSampleBuffer>?>
    )

    guard result == kOSReturnSuccess, let unwrapedSampleBuffer = sampleBuffer else {
        throw OSStatusError(osStatus: result, description: "CMSampleBufferCreate() failed")
    }
    
    CMSetAttachment(unwrapedSampleBuffer, key: kCMSampleAttachmentKey_DisplayImmediately, value: kCFBooleanTrue, attachmentMode: kCMAttachmentMode_ShouldPropagate)
    
    
    //CMSampleBufferSetDisplayImmediately(sampleBuffer)

    return unwrapedSampleBuffer
}