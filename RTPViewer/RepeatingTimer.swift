//
//  RepeatingTimer.swift
//  Lightning
//
//  Created by David Nadoba on 19.05.18.
//  Copyright © 2018 David Nadoba. All rights reserved.
//

import Foundation

protocol RepeatingTimerProtocol {
    var eventHandler: (() -> ())? { get set }
    func resume()
    func suspend()
}

final class RepeatingTimerMock: RepeatingTimerProtocol {
    var eventHandler: (() -> ())?
    func resume() {}
    func suspend() {}
    
    func callEventHandler() {
        eventHandler?()
    }
}


/// RepeatingTimer mimics the API of DispatchSourceTimer but in a way that prevents
/// crashes that occur from calling resume multiple times on a timer that is
/// already resumed (noted by https://github.com/SiftScience/sift-ios/issues/52
final class RepeatingTimer: RepeatingTimerProtocol {
    
    let timeInterval: DispatchTimeInterval
    let queue: DispatchQueue
    
    init(timeInterval: DispatchTimeInterval, queue: DispatchQueue) {
        self.timeInterval = timeInterval
        self.queue = queue
    }
    
    convenience init(refreshRate: Int, queue: DispatchQueue) {
        self.init(timeInterval: DispatchTimeInterval.nanoseconds(1_000_000_000/refreshRate), queue: queue)
    }
    convenience init(refreshRate: Double, queue: DispatchQueue) {
        self.init(timeInterval: DispatchTimeInterval.nanoseconds(Int(1_000_000_000/refreshRate)), queue: queue)
    }
    
    private lazy var timer: DispatchSourceTimer = {
        let t = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags.strict, queue: queue)
        t.schedule(deadline: .now() + timeInterval, repeating: timeInterval, leeway: DispatchTimeInterval.milliseconds(0))
        t.setEventHandler(handler: { [weak self] in
            self?.eventHandler?()
        })
        return t
    }()
    
    var eventHandler: (() -> Void)?
    
    private enum State {
        case suspended
        case resumed
    }
    
    private var state: State = .suspended
    
    deinit {
        timer.setEventHandler {}
        timer.cancel()
        /*
         If the timer is suspended, calling cancel without resuming
         triggers a crash. This is documented here https://forums.developer.apple.com/thread/15902
         */
        resume()
        eventHandler = nil
    }
    
    func resume() {
        if state == .resumed {
            return
        }
        state = .resumed
        timer.resume()
    }
    
    func suspend() {
        if state == .suspended {
            return
        }
        state = .suspended
        timer.suspend()
    }
}
