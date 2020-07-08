//
//  AppleSpeechRecognizerTest.swift
//  SpokestackTests
//
//  Created by Noel Weichbrodt on 9/16/19.
//  Copyright © 2020 Spokestack, Inc. All rights reserved.
//

import Foundation
import XCTest
import Spokestack
import AVFoundation

class AppleSpeechRecognizerTest: XCTestCase {

    /// startStreaming
    func testStartStopStreaming() {
        let context = SpeechContext()
        let configuration = SpeechConfiguration()
        let asr = AppleSpeechRecognizer(configuration, context: context)
        let delegate = AppleSpeechRecognizerTestDelegate()
        context.listeners = [delegate]
        context.isActive = true
        context.isSpeech = true
        asr.context = context
        asr.startStreaming()
        XCTAssert(context.isActive)
        XCTAssertFalse(delegate.didError)
        asr.stopStreaming()
        // asr does not set active
        XCTAssertFalse(context.isActive)
        XCTAssertFalse(delegate.didError)
    }
    
    func testProcess() {
        let context = SpeechContext()
        let configuration = SpeechConfiguration()
        let asr = AppleSpeechRecognizer(configuration, context: context)
        let delegate = AppleSpeechRecognizerTestDelegate()
        context.listeners = [delegate]
        context.isActive = true
        context.isSpeech = true
        context.stageInstances = [asr]
        asr.context = context
        asr.startStreaming()
        
        asr.process(Frame.silence(frameWidth: 10, sampleRate: 8000))
        asr.stopStreaming()
        // asr does not set active
        XCTAssertFalse(context.isActive)
        XCTAssertFalse(delegate.didError)
    }
}

class AppleSpeechRecognizerTestDelegate: SpeechEventListener {
    /// Spy pattern for the system under test.
    /// asyncExpectation lets the caller's test know when the delegate has been called.
    var didError: Bool = false
    var didDidTimeout: Bool = false
    var deactivated: Bool = false
    var didRecognize: Bool = false
    var asyncExpectation: XCTestExpectation?
    
    func reset() {
        self.didError = false
        self.didDidTimeout = false
        self.deactivated = false
        self.didRecognize = false
        self.didRecognize = false
        asyncExpectation = .none
    }
    
    func didRecognize(_ result: SpeechContext) {
        print(result)
        self.didRecognize = true
    }
    
    func failure(speechError: Error) {
        print(speechError)
        guard let _ = asyncExpectation else {
            XCTFail("AppleSpeechRecognizerTestDelegate was not setup correctly. Missing XCTExpectation reference")
            return
        }
        self.didError = true
        self.asyncExpectation?.fulfill()
    }
    
    func didTimeout() {
        self.didDidTimeout = true
    }
    
    func didActivate() {}

    func didDeactivate() {
        self.deactivated = true
    }
    
    func didStop() {}
    
    func didStart() {}
    
    func didInit() {}
    
    func setupFailed(_ error: String) {}
    
    func didTrace(_ trace: String) {
        print(trace)
    }
}
