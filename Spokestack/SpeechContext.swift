//
//  SpeechContext.swift
//  Spokestack
//
//  Created by Cory D. Wiles on 10/1/18.
//  Copyright © 2020 Spokestack, Inc. All rights reserved.
//

import Foundation

/// This class maintains global state for the speech pipeline, allowing pipeline components to communicate information among themselves and event handlers.
@objc public class SpeechContext: NSObject {
    public var configuration: SpeechConfiguration
    /// Current speech transcript
    @objc public var transcript: String = ""
    /// Current speech recognition confidence: [0-1)
    @objc public var confidence: Float = 0.0
    /// Speech recognition active indicator
    @objc public var isActive: Bool = false
    /// Speech detected indicator
    @objc public var isSpeech: Bool = false
    /// An ordered set of `SpeechEventListener`s that are sent `SpeechPipeline` events.
    private var listeners: [SpeechEventListener] = []
    /// Current error in the pipeline
    internal var error: Error?
    /// Current trace in the pipeline
    internal var trace: String?
    
    /// Initializes a speech context instance using the specified speech pipeline configuration.
    /// - Parameter config: The speech pipeline configuration used by the speech context instance.
    @objc public init(_ config: SpeechConfiguration) {
        self.configuration = config
    }
    
    /// Adds the specified listener instance to the ordered set of listeners. The specified listener instance may only be added once; duplicates will be ignored. The specified listener will recieve speech pipeline events.
    ///
    /// - Parameter listener: The listener to add.
    @objc public func addListener(_ listener: SpeechEventListener) {
        if !self.listeners.contains(where: { l in
            return listener === l ? true : false
        }) {
            self.listeners.append(listener)
        }
    }
    
    /// Removes the specified listener by reference. The specified listener will no longer recieve speech pipeline events.
    /// - Parameter listener: The listener to remove.
    @objc public func removeListener(_ listener: SpeechEventListener) {
        for (i, l) in self.listeners.enumerated() {
            _ = listener === l ? self.listeners.remove(at: i) : nil
        }
    }
    
    /// Removes all listeners.
    @objc public func removeListeners() {
        self.listeners = []
    }

    @objc internal func dispatch(_ event: SpeechEvents) {
        switch event {
        case .initialize:
            self.listeners.forEach { listener in
                self.configuration.delegateDispatchQueue.async {
                    listener.didInit()
                }}
        case .start:
            self.listeners.forEach { listener in
                self.configuration.delegateDispatchQueue.async {
                    listener.didStart()
                }}
        case .stop:
            self.listeners.forEach { listener in
                self.configuration.delegateDispatchQueue.async {
                    listener.didStop()
                }}
        case .activate:
            self.listeners.forEach { listener in
                self.configuration.delegateDispatchQueue.async {
                    listener.didActivate()
                }}
        case .deactivate:
            self.listeners.forEach { listener in
                self.configuration.delegateDispatchQueue.async {
                    listener.didDeactivate()
                }}
        case .recognize:
            self.listeners.forEach { listener in
                self.configuration.delegateDispatchQueue.async {
                    listener.didRecognize(self)
                }}
        case .error:
            let e = (self.error != nil) ? self.error! : SpeechPipelineError.errorNotSet("A pipeline component attempted to send an error to SpeechContext's listeners without first setting the SpeechContext.error property.")
            self.listeners.forEach { listener in
                self.configuration.delegateDispatchQueue.async {
                    listener.failure(speechError: e)
                }}
            self.error = .none
        case .trace:
            if let t = self.trace {
                self.listeners.forEach { listener in
                    self.configuration.delegateDispatchQueue.async {
                        listener.didTrace(t)
                    }}
                self.trace = .none
            }
        case .timeout:
            self.listeners.forEach { listener in
                self.configuration.delegateDispatchQueue.async {
                    listener.didTimeout()
                }}
        }
    }
}
