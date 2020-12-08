//
//  SpeechPipeline.swift
//  Spokestack
//
//  Created by Cory D. Wiles on 10/2/18.
//  Copyright © 2020 Spokestack, Inc. All rights reserved.
//

import Foundation
import AVFoundation
import Dispatch

/**
 This is the primary client entry point to the Spokestack voice input system. It dynamically binds to configured components that implement the pipeline interfaces for reading audio frames and performing speech recognition tasks.
 
 The pipeline may be stopped/restarted any number of times during its lifecycle. While stopped, the pipeline consumes as few resources as possible. The pipeline runs asynchronously on a dedicated thread, so it does not block the caller when performing I/O and speech processing.
 
 When running, the pipeline communicates with the client via delegates that receive events.
 */
@objc public final class SpeechPipeline: NSObject {
    
    // MARK: Public (properties)
    
    /// Pipeline configuration parameters.
    @objc public private (set) var configuration: SpeechConfiguration
    /// Global state for the speech pipeline.
    @objc public let context: SpeechContext
    
    
    // MARK: Private (properties)
    
    /// A list of `SpeechProcessor` instances that process audio frames from `AudioController`.
    private var stages: [SpeechProcessor] = []
    private var isStarted = false
    
    // MARK: Initializers
    
    deinit {
        self.context.removeListeners()
        self.stages = []
    }
    
    /// Initializes a new speech pipeline instance. For use by clients wishing to pass 3rd-party stages to the spokestack pipeline.
    /// - Important: Most clients should use `SpeechPipelineBuilder` to initialize a new speech pipeline instance, not this initializer.
    /// - SeeAlso: SpeechPipelineBuilder
    /// - Parameter configuration: Configuration parameters for the speech pipeline.
    /// - Parameter listeners: Delegate implementations of `SpokestackDelegate` that receive speech pipeline events.
    /// - Parameter stages: `SpeechProcessor` instances process audio frames from `AudioController`.
    @objc public init(configuration: SpeechConfiguration, listeners: [SpokestackDelegate], stages: [SpeechProcessor], context: SpeechContext) {
        self.configuration = configuration
        self.context = context
        self.stages = stages
        AudioController.sharedInstance.configuration = configuration
        AudioController.sharedInstance.context = self.context
        AudioController.sharedInstance.stages = stages
        super.init()
        listeners.forEach { self.context.addListener($0) }
        self.context.dispatch { $0.didInit?() }
    }
    
    /// For use by `SpeechPipelineBuilder`
    /// - Parameters:
    /// - Parameter configuration: Configuration parameters for the speech pipeline.
    /// - Parameter listeners: Delegate implementations of `SpokestackDelegate` that receive speech pipeline events.
    /// - Parameter profile: The builder profile to use when configuring the pipeline.
    internal init(configuration: SpeechConfiguration, listeners: [SpokestackDelegate], profile: SpeechPipelineProfiles) {
        self.configuration = configuration
        self.context = SpeechContext(configuration)
        super.init()
        self.stages = profile.set.map { stage in
            switch stage {
            case .vad:
                return WebRTCVAD(configuration, context: self.context)
            case .appleWakeword:
                return AppleWakewordRecognizer(configuration, context: self.context)
            case .tfLiteWakeword:
                return TFLiteWakewordRecognizer(configuration, context: self.context)
            case .appleSpeech:
                return AppleSpeechRecognizer(configuration, context: self.context)
            case .vadTrigger:
                return VADTrigger(configuration, context: self.context)
            }
        }
        
        AudioController.sharedInstance.stages = self.stages
        AudioController.sharedInstance.configuration = configuration
        AudioController.sharedInstance.context = self.context
        listeners.forEach { self.context.addListener($0) }
        self.context.dispatch { $0.didInit?() }
    }
    
    /// MARK: Pipeline control
    
    /**
     Activates speech recognition. The pipeline remains active until the user stops talking or the activation timeout is reached.
     
     Activations have configurable minimum/maximum lengths. The minimum length prevents the activation from being aborted if the user pauses after saying the wakeword (which deactivates the VAD). The maximum activation length allows the activation to timeout if the user doesn't say anything after saying the wakeword.
     
     The wakeword detector can be used in a multi-turn dialogue system. In such an environment, the user is not expected to say the wakeword during each turn. Therefore, an application can manually activate the pipeline by calling `activate` (after a system turn), and the wakeword detector will apply its minimum/maximum activation lengths to control the duration of the activation.
    */
    @objc public func activate() -> Void {
        if !self.context.isActive {
            self.context.isSpeech = true
            self.context.isActive = true
            self.context.dispatch { $0.didActivate?() }
        }
    }
    
    /// Deactivates speech recognition.  The pipeline returns to awaiting either wakeword activation or an explicit `activate` call.
    /// - SeeAlso: `activate`
    @objc public func deactivate() -> Void {
        self.context.isActive = false
        self.context.isSpeech = false
        self.context.dispatch { $0.didDeactivate?() }
    }
    
    /// Starts  the speech pipeline.
    ///
    /// The pipeline starts in a deactivated state, awaiting either a triggered activation from a wakeword or VAD, or an explicit call to `activate`.
    @objc public func start() -> Void {
        if !self.isStarted {
            // notify stages to start
            self.stages.forEach { stage in
                stage.startStreaming()
            }
            
            // begin streaming audio to the stages via `process`
            AudioController.sharedInstance.startStreaming()
            
            // notify listeners of start
            self.context.dispatch { $0.didStart?() }
            
            // repeated calls to start are idempotent
            self.isStarted = true
        }
    }
    
    /// Stops the speech pipeline.
    ///
    /// All pipeline activity is stopped, and the pipeline cannot be activated until it is `start`ed again.
    @objc public func stop() -> Void {
        if self.isStarted {
            self.stages.forEach({ stage in
                stage.stopStreaming()
            })
            AudioController.sharedInstance.stopStreaming()
            self.context.dispatch { $0.didStop?() }
            self.isStarted = false
        }
    }
}

/**
    Convenience initializer for building a `SpeechPipeline` instance using a pre-configured profile. A pipeline profile encapsulates a series of configuration values tuned for a specific task.
 
    Profiles are not authoritative; they act just like calling a series of methods on a `SpeechPipelineBuilder`, and any configuration properties they set can be overridden by subsequent calls.
 
    - Example:
     ```
     // assume that self implements the SpeechEventListener protocol
     let pipeline = SpeechPipelineBuilder()
         .addListener(self)
         .setDelegateDispatchQueue(DispatchQueue.main)
         .useProfile(.tfLiteWakewordAppleSpeech)
         .setProperty("tracing", Trace.Level.PERF)
         .setProperty("detectModelPath", detectPath)
         .setProperty("encodeModelPath", encodePath)
         .setProperty("filterModelPath", filterPath)
         .build()
     pipeline.start()
     ```
 */
@objc public class SpeechPipelineBuilder: NSObject {
    private var config = SpeechConfiguration()
    private var listeners: [SpokestackDelegate] = []
    private var profile: SpeechPipelineProfiles?
    
    /// Applies configuration from `SpeechPipelineProfiles` to the current builder, returning the modified builder.
    /// - Parameter profile: Name of the profile to apply.
    /// - Returns: An updated instance of `SpeechPipelineBuilder` for call chaining.
    @objc public func useProfile(_ profile: SpeechPipelineProfiles) -> SpeechPipelineBuilder {
        self.profile = profile
        return self
    }
    
    /// Sets a `SpeechConfiguration` configuration value.
    /// - SeeAlso: `SpeechConfiguration`
    /// - Parameters:
    ///   - key: Configuration property name
    ///   - value: Configuration property value
    /// - Note: "tracing" key must have a value of `Trace.Level`, eg `Trace.Level.DEBUG`.
    /// - Returns: An updated instance of `SpeechPipelineBuilder` for call chaining.
    @objc public func setProperty(_ key: String, _ value: Any) -> SpeechPipelineBuilder {
        switch key {
        case "tracing":
            guard let t = value as? Trace.Level else {
                break
            }
            self.config.setValue(t.rawValue, forKey: key)
        default:
            self.config.setValue(value, forKey: key)
        }
        return self
    }
    
    /// Replaces the default speech configuration with the specified configuration.
    ///
    /// - Warning: All preceeding `setProperty` calls will be erased by setting the configuration explicitly.
    /// - Parameter config: An instance of SpeechConfiguration that the pipeline will use.
    @objc public func setConfiguration(_ config: SpeechConfiguration) -> SpeechPipelineBuilder {
        self.config = config
        return self
    }
    
    /// Delegate events will be sent using the specified dispatch queue.
    /// - SeeAlso: `SpeechConfiguration`
    /// - Parameter queue: A `DispatchQueue` instance
    /// - Returns: An updated instance of `SpeechPipelineBuilder` for call chaining.
    @objc public func setDelegateDispatchQueue(_ queue: DispatchQueue) -> SpeechPipelineBuilder {
        self.config.delegateDispatchQueue = queue
        return self
    }
    
    /// Delegate events will be sent to the specified listener.
    /// - Parameter listener: A `SpeechEventListener` instance.
    /// - Returns: An updated instance of `SpeechPipelineBuilder` for instace function  call chaining.
    @objc public func addListener(_ listener: SpokestackDelegate) -> SpeechPipelineBuilder {
        self.listeners.append(listener)
        return self
    }
    
    /// Build this configuration into a `SpeechPipeline` instance.
    /// - Returns: A `SpeechPipeline` instance.
    @objc public func build() throws -> SpeechPipeline {
        guard let p = self.profile else {
            throw SpeechPipelineError.incompleteBuilder("Please specify a profile to use before calling build().")
        }
        return SpeechPipeline(configuration: self.config, listeners: self.listeners, profile: p)
    }
}
