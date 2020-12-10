//
//  AppleWakewordRecognizer.swift
//  Spokestack
//
//  Created by Noel Weichbrodt on 2/4/19.
//  Copyright © 2020 Spokestack, Inc. All rights reserved.
//

import Foundation
import Speech

/**
This pipeline component uses the Apple `SFSpeech` API to stream audio samples for wakeword recognition.

 Once speech pipeline coordination via `startStreaming` is received, the recognizer begins streaming buffered frames to the Apple ASR API for recognition. Upon wakeword or wakephrase recognition, the pipeline activation event is triggered and the recognizer completes the API request and awaits another coordination event. Once speech pipeline coordination via `stopStreaming` is received, the recognizer completes the API request and awaits another coordination event.
*/
@objc public class AppleWakewordRecognizer: NSObject {
    
    // MARK: Public properties
    
    /// Configuration for the recognizer.
    @objc public var configuration: SpeechConfiguration

    /// Global state for the speech pipeline.
    @objc public var context: SpeechContext
    
    // MARK: Private properties
    
    private var phrases: Array<String> {
        return self.configuration.wakewords.components(separatedBy: ",")
    }
    private let speechRecognizer: SFSpeechRecognizer = SFSpeechRecognizer(locale: NSLocale.current)!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine: AVAudioEngine = AVAudioEngine()
    private var recognitionTaskRunning: Bool = false
    private var traceLevel: Trace.Level = Trace.Level.NONE
    private let startStopSema = DispatchSemaphore.init(value: 1)
    private var restartTimer: Timer?
    private var shouldBeStreaming: Bool = false

    // MARK: NSObject methods
    
    deinit {
        self.speechRecognizer.delegate = nil
    }
    
    /// Initializes a AppleWakewordRecognizer instance.
    ///
    /// A recognizer is initialized by, and receives `startStreaming` and `stopStreaming` events from, an instance of `SpeechPipeline`.
    ///
    /// The AppleWakewordRecognizer receives audio data frames to `process` from a tap into the system `AudioEngine`.
    /// - Parameters:
    ///   - configuration: Configuration for the recognizer.
    ///   - context: Global state for the speech pipeline.
    @objc public init(_ configuration: SpeechConfiguration, context: SpeechContext) {
        self.configuration = configuration
        self.context = context
        super.init()
        self.configure()
    }
    
    private func configure() {
        // Tracing
        self.traceLevel = self.configuration.tracing
    }
    
    // MARK: Private functions
    
    private func prepare() {
        Trace.trace(.DEBUG, message: "AppleWakewordRecognizer prepare()", config: nil, context: nil, caller: self)
        let bufferSize: Int = (self.configuration.sampleRate / 1000) * self.configuration.frameWidth
        self.audioEngine.inputNode.removeTap(onBus: 0) // a belt-and-suspenders approach to fixing https://github.com/wenkesj/react-native-voice/issues/46
        self.audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(bufferSize),
            format: nil)
        {[weak self] buffer, when in
            guard let strongSelf = self else {
                return
            }
            strongSelf.recognitionRequest?.append(buffer)
        }
        self.audioEngine.prepare()
        self.startRestartTimer()
    }
    
    private func startRestartTimer() {
        guard self.shouldBeStreaming else { return }
        DispatchQueue.main.async {
            self.restartTimer?.invalidate()
            self.restartTimer = Timer.scheduledTimer(timeInterval: TimeInterval(self.configuration.wakewordRequestTimeout) / 1000.0, target: self, selector: #selector(self.restartTimerFired), userInfo: nil, repeats: false)
        }
    }
    
    @objc private func restartTimerFired() {
        self.restartTimer?.invalidate()
        self.restartTimer = nil
        DispatchQueue.global(qos: .userInitiated).async {
            Trace.trace(.DEBUG, message: "AppleWakewordRecognizer restartTimerFired()", config: nil, context: nil, caller: self)
            if self.startStopSema.wait(timeout: .now() + 2) == .timedOut {
                Trace.trace(.DEBUG, message: "AppleWakewordRecognizer restartTimerFired() - ERROR, timed out on semaphore", config: nil, context: nil, caller: self)
                self.startRestartTimer() // startRecognition does it in normal case
                return
            }
            self.stopRecognition(hasSema: true)
            self.startRecognition(hasSema: true)
            self.startStopSema.signal()
        }
    }
    
    private func startRecognition(hasSema: Bool = false ) {
        do {
            defer {
                // Automatically restart wakeword task (configurable)
                self.startRestartTimer()
            }

            // audioSema first...
            if audioSema.wait(timeout: .now() + 2) == .timedOut {
                Trace.trace(.DEBUG, message: "AppleWakewordRecognizer startRecognition() - ERROR, timed out on audio semaphore", config: nil, context: nil, caller: self)
                return
            }
            defer { audioSema.signal() }

            // ... now ours
            if !hasSema {
                if self.startStopSema.wait(timeout: .now() + 2) == .timedOut {
                    Trace.trace(.DEBUG, message: "AppleWakewordRecognizer startRecognition() - ERROR, timed out on semaphore", config: nil, context: nil, caller: self)
                    return
                }
            }
            defer { if !hasSema { self.startStopSema.signal() } }
            
            guard self.shouldBeStreaming else {
                Trace.trace(.DEBUG, message: "AppleWakewordRecognizer startRecognition(), !shouldBeStreaming - NO-OP", config: nil, context: nil, caller: self)
                return
            }
            
            Trace.trace(.DEBUG, message: "AppleWakewordRecognizer startRecognition()", config: nil, context: nil, caller: self)
            try self.audioEngine.start()
            self.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            self.recognitionRequest?.shouldReportPartialResults = true
            try self.createRecognitionTask()
            self.recognitionTaskRunning = true
        } catch let error {
            self.context.dispatch { $0.failure(error: error) }
        }
    }
    
    private func stopRecognition(hasSema: Bool = false) {
        if !hasSema {
            if self.startStopSema.wait(timeout: .now() + 2) == .timedOut {
                Trace.trace(.DEBUG, message: "AppleWakewordRecognizer stopRecognition() - ERROR, timed out on semaphore", config: nil, context: nil, caller: self)
                return
            }
        }
        defer { if !hasSema { self.startStopSema.signal() } }
        Trace.trace(.DEBUG, message: "AppleWakewordRecognizer stopRecognition()", config: nil, context: nil, caller: self)
        self.restartTimer?.invalidate()
        self.restartTimer = nil
        self.recognitionTaskRunning = false
        self.recognitionTask?.finish()
        self.recognitionTask = nil
        self.recognitionRequest?.endAudio()
        self.recognitionRequest = nil
        self.audioEngine.pause()
    }
    
    private func createRecognitionTask() throws -> Void {
        guard let rr = self.recognitionRequest else {
            throw SpeechPipelineError.failure("Apple Wakeword's recognition request does not exist.")
        }
        self.recognitionTask = self.speechRecognizer.recognitionTask(
            with: rr,
            resultHandler: {[weak self] result, error in
                guard let strongSelf = self else {
                    // the callback has been orphaned by stopStreaming, so just end things here.
                    return
                }
                if let e = error {
                    if let nse: NSError = error as NSError? {
                        if nse.domain == "kAFAssistantErrorDomain" {
                            Trace.trace(Trace.Level.INFO, message: "wakeword resultHandler error code \(nse.code)", config: strongSelf.configuration, context: strongSelf.context, caller: strongSelf)
                            switch nse.code {
                            case 0..<200: // Apple retry error: https://developer.nuance.com/public/Help/DragonMobileSDKReference_iOS/Error-codes.html
                                break
                            case 203: // request timed out, retry
                                if strongSelf.startStopSema.wait(timeout: .now() + 2) == .timedOut {
                                    Trace.trace(.DEBUG, message: "AppleWakewordRecognizer 203 restart - ERROR, timed out on semaphore", config: nil, context: nil, caller: strongSelf)
                                    return
                                }
                                strongSelf.stopRecognition(hasSema: true)
                                strongSelf.startRecognition(hasSema: true)
                                strongSelf.startStopSema.signal()
                                break
                            case 209: // ¯\_(ツ)_/¯
                                break
                            case 216: // Apple internal error: https://stackoverflow.com/questions/53037789/sfspeechrecognizer-216-error-with-multiple-requests?noredirect=1&lq=1)
                                break
                            case 300..<603: // Apple retry error: https://developer.nuance.com/public/Help/DragonMobileSDKReference_iOS/Error-codes.html
                                break
                            default:
                                strongSelf.context.dispatch { $0.failure(error: e) }
                            }
                        }
                    } else {
                        strongSelf.context.dispatch { $0.failure(error: e) }
                    }
                }
                if let r = result {
                    Trace.trace(Trace.Level.DEBUG, message: "heard \(r.bestTranscription.formattedString)", config: strongSelf.configuration, context: strongSelf.context, caller: strongSelf)
                    let wakewordDetected: Bool =
                        !strongSelf.phrases
                            .filter({
                                r
                                    .bestTranscription
                                    .formattedString
                                    .lowercased()
                                    .contains($0.lowercased())})
                            .isEmpty
                    if wakewordDetected {
                        strongSelf.context.isActive = true
                        strongSelf.context.dispatch { $0.didActivate?() }
                    }
                }
        })
    }
}

// MARK: SpeechProcessor implementation

extension AppleWakewordRecognizer: SpeechProcessor {
    
    /// Triggered by the speech pipeline, instructing the recognizer to begin streaming and processing audio.
    @objc public func startStreaming() {
        // audio sema first...
        if audioSema.wait(timeout: .now() + 2) == .timedOut {
            Trace.trace(.DEBUG, message: "AppleWakewordRecognizer startStreaming() - ERROR, timed out on audio semaphore", config: nil, context: nil, caller: self)
            return
        }
        defer { audioSema.signal() }

        // ... now ours
        if self.startStopSema.wait(timeout: .now() + 2) == .timedOut {
            Trace.trace(.DEBUG, message: "AppleWakewordRecognizer startStreaming() - ERROR, timed out on semaphore", config: nil, context: nil, caller: self)
            return
        }
        defer { self.startStopSema.signal() }

        Trace.trace(.DEBUG, message: "AppleWakewordRecognizer startStreaming()", config: nil, context: nil, caller: self)
        self.shouldBeStreaming = true
        self.prepare()
    }
    
    /// Triggered by the speech pipeline, instructing the recognizer to stop streaming audio and complete processing.
    @objc public func stopStreaming() {
        // audio sema first...
        if audioSema.wait(timeout: .now() + 2) == .timedOut {
            Trace.trace(.DEBUG, message: "AppleWakewordRecognizer stopStreaming() - ERROR, timed out on audio semaphore", config: nil, context: nil, caller: self)
            return
        }
        defer { audioSema.signal() }

        // ... now ours
        if self.startStopSema.wait(timeout: .now() + 2) == .timedOut {
            Trace.trace(.DEBUG, message: "AppleWakewordRecognizer stopStreaming() - ERROR, timed out on semaphore", config: nil, context: nil, caller: self)
            return
        }
        defer { self.startStopSema.signal() }

        Trace.trace(.DEBUG, message: "AppleWakewordRecognizer stopStreaming()", config: nil, context: nil, caller: self)
        self.shouldBeStreaming = false
        self.stopRecognition(hasSema: true)
        self.audioEngine.stop()
        self.audioEngine.inputNode.removeTap(onBus: 0)
    }
    
    /// Receives a frame of audio samples for processing. Interface between the `SpeechProcessor` and `AudioController` components. Processes audio in an async thread.
    /// - Note: Processes audio in an async thread.
    /// - Remark: The Apple Wakeword Recognizer hooks up directly to its own audio tap for processing audio frames. When the `AudioController` calls this `process`, it checks to see if the pipeline has detected speech, and if so kicks off its own VAD and wakeword recognizer independently of any other components in the speech pipeline.
    /// - Parameter frame: Frame of audio samples.
    @objc public func process(_ frame: Data) -> Void {
        if !self.recognitionTaskRunning && self.context.isSpeech && !self.context.isActive {
            self.startRecognition()
        } else if context.isActive {
            self.stopRecognition()
        }
    }
}
