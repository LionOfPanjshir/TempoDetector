//
//  TempoDetector.swift
//  TempoDetector
//
//  Created by Andrew Higbee on 11/8/24.
//

import AVFoundation
import Accelerate

class TempoDetector: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var audioSession = AVAudioSession.sharedInstance()
    
    @Published var onsetStrengthSignal = [Float]()
    
    private var frameBuffer = [Float]()
    private let frameSize = 1024
    private let hopSize = 128
    private var sampleCounter = 0
    
    // Store the previous spectrum for spectral flux calculation
    private var previousSpectrum: [Float]?
    
    // Track recent flux values for rolling maximum normalization
    private var recentFluxValues: [Float] = []
    private let rollingWindowSize = 100  // Number of flux values to consider in rolling maximum
    
    // Target maximum for scaling
    private let targetMaxFlux: Float = 5.0
    
    init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session:", error)
        }
    }
    
    func startListening() {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudio(buffer: buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Audio engine couldn't start:", error)
        }
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        onsetStrengthSignal.removeAll()
        frameBuffer.removeAll()
        previousSpectrum = nil
        sampleCounter = 0
        recentFluxValues.removeAll()  // Reset recent flux values
    }
    
    private func processAudio(buffer: AVAudioPCMBuffer) {
        guard let audioData = buffer.floatChannelData?[0] else { return }
        
        let audioArray = Array(UnsafeBufferPointer(start: audioData, count: Int(buffer.frameLength)))
        frameBuffer.append(contentsOf: audioArray)
        
        while frameBuffer.count >= frameSize {
            let frame = Array(frameBuffer.prefix(frameSize))
            frameBuffer.removeFirst(hopSize)
            processFrame(frame)
        }
    }
    
    private func processFrame(_ frame: [Float]) {
        let logPowerSpectrum = calculateLogPowerSpectrum(frame)
        
        // Calculate spectral flux
        let flux = calculateSpectralFlux(logPowerSpectrum)
        
        // Update recent flux values and calculate rolling max
        recentFluxValues.append(flux)
        if recentFluxValues.count > rollingWindowSize {
            recentFluxValues.removeFirst()
        }
        
        let rollingMaxFlux = recentFluxValues.max() ?? 1.0  // Avoid division by zero
        
        // Scale flux to the target range 0–5
        let scaledFlux = (flux / rollingMaxFlux) * targetMaxFlux

        DispatchQueue.main.async { [weak self] in
            self?.onsetStrengthSignal.append(scaledFlux)
            print("Added scaled flux to OSS:", scaledFlux)
        }
        
        previousSpectrum = logPowerSpectrum  // Update the previous spectrum
    }
    
    private func calculateLogPowerSpectrum(_ frame: [Float]) -> [Float] {
        var windowedFrame = frame
        let window = vDSP.window(ofType: Float.self, usingSequence: .hamming, count: frameSize, isHalfWindow: false)
        vDSP_vmul(windowedFrame, 1, window, 1, &windowedFrame, 1, vDSP_Length(frameSize))
        
        var realPart = windowedFrame
        var imaginaryPart = [Float](repeating: 0.0, count: frameSize)
        var complexBuffer = DSPSplitComplex(realp: &realPart, imagp: &imaginaryPart)
        let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(frameSize))), FFTRadix(FFT_RADIX2))
        vDSP_fft_zip(fftSetup!, &complexBuffer, 1, vDSP_Length(log2(Float(frameSize))), FFTDirection(FFT_FORWARD))
        
        var magnitudes = [Float](repeating: 0.0, count: frameSize / 2)
        vDSP_zvmags(&complexBuffer, 1, &magnitudes, 1, vDSP_Length(frameSize / 2))
        
        var logPowerSpectrum = [Float](repeating: 0.0, count: frameSize / 2)
        var scalingFactor: Float = 1000.0
        var one: Float = 1.0
        vDSP_vsadd(magnitudes, 1, &one, &magnitudes, 1, vDSP_Length(magnitudes.count))
        vDSP_vdbcon(magnitudes, 1, &scalingFactor, &logPowerSpectrum, 1, vDSP_Length(magnitudes.count), 0)
        
        vDSP_destroy_fftsetup(fftSetup)
        
        return logPowerSpectrum
    }
    
    private func calculateSpectralFlux(_ currentSpectrum: [Float]) -> Float {
        guard let previousSpectrum = previousSpectrum else {
            return 0.0
        }
        
        var flux: Float = 0.0
        for (currentValue, previousValue) in zip(currentSpectrum, previousSpectrum) {
            let difference = currentValue - previousValue
            if difference > 0 {
                flux += difference
            }
        }
        
        return flux
    }
}
