//
// AudioSpectrum02
// A demo project for blog: https://juejin.im/post/5c1bbec66fb9a049cb18b64c
// Created by: potato04 on 2019/1/30
//

import Accelerate
import AVFoundation
import Foundation

class RealtimeAnalyzer {
    struct Band {
        let lowerFrequency: Float
        let upperFrequency: Float
    }
    
    public var frequencyBands: Int = 60 // Number of frequency bands
    public var startFrequency: Float = 100 // Starting frequency
    public var endFrequency: Float = 18000 // Ending frequency

    private let fftSize: Int
    private var currentSampleRate: Double
    
    // Pre-allocated bufferы
    private var aWeights: [Float]
    private var processingSamples: [Float]
    private var hannWindow: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var amplitudes: [Float]
    private var weightedAmplitudes: [Float]
    private var spectrum: [Float]
    private var spectrumBuffer = [[Float]]()
    private var bands: [Band]
    private var bandIndices: [(startIndex: Int, endIndex: Int)]
    
    private lazy var fftSetup = vDSP_create_fftsetup(
        vDSP_Length(Int(round(log2(Double(fftSize))))), FFTRadix(kFFTRadix2)
    )
    
        
    public var spectrumSmooth: Float = 0.5 {
        didSet {
            spectrumSmooth = max(0.0, spectrumSmooth)
            spectrumSmooth = min(1.0, spectrumSmooth)
        }
    }
    
    init(fftSize: Int) {
        currentSampleRate = 44100.0
        self.fftSize = fftSize
        aWeights = Self.createFrequencyWeights(fftSize: fftSize, sampleRate: currentSampleRate)
        processingSamples = .init(repeating: 0.0, count: fftSize)
        hannWindow = .init(repeating: 0, count: fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        realp = .init(repeating: 0.0, count: fftSize / 2)
        imagp = .init(repeating: 0.0, count: fftSize / 2)
        amplitudes = .init(repeating: 0.0, count: fftSize / 2)
        weightedAmplitudes = .init(repeating: 0.0, count: fftSize / 2)
        spectrum = .init(repeating: 0.0, count: frequencyBands)
        bands = Self.createBands(
            frequencyBands: frequencyBands,
            startFrequency: startFrequency,
            endFrequency: endFrequency
        )
        
        bandIndices = Self.createBandIndices(
            fftSize: fftSize,
            sampleRate: currentSampleRate,
            bands: bands
        )
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    func analyse(
        bufferList: UnsafeMutablePointer<AudioBufferList>,
        sampleRate: Double
    ) -> [[Float]] {
        let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
        let channelCount = Int(ablPointer.count)
        
        if currentSampleRate != sampleRate {
            aWeights = Self.createFrequencyWeights(fftSize: fftSize, sampleRate: sampleRate)
            bandIndices = Self.createBandIndices(
                fftSize: fftSize,
                sampleRate: currentSampleRate,
                bands: bands
            )
            currentSampleRate = sampleRate
        }
        
        if spectrumBuffer.count != channelCount {
            spectrumBuffer = .init(repeating: [Float](repeating: 0, count: bands.count), count: channelCount)
        }
        
        for i in 0 ..< channelCount {
            let buffer = ablPointer[i]
            guard let data = buffer.mData, buffer.mNumberChannels == 1 else { continue }
            let channelBuf = processingSamples.withUnsafeMutableBufferPointer { $0 }
            let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard frameCount > fftSize else { continue }
            memcpy(channelBuf.baseAddress, data, fftSize * MemoryLayout<Float>.size)
            let channel = channelBuf.baseAddress!
            
            // Compute FFT and store results in amplitudes
            fftChannel(channel, output: &amplitudes)
            
            // Compute weighted amplitudes using vDSP_vmul
            vDSP_vmul(
                amplitudes, 1,
                aWeights, 1,
                &weightedAmplitudes, 1,
                vDSP_Length(fftSize / 2)
            )
            
            // Compute max amplitude for each frequency band
            for (j, indices) in bandIndices.enumerated() {
                findMaxAmplitude(
                    for: indices,
                    in: weightedAmplitudes,
                    output: &spectrum[j]
                )
            }
            
            // Scale spectrum amplitudes by 5
            vDSP_vsmul(
                spectrum, 1,
                [5.0], &spectrum, 1,
                vDSP_Length(frequencyBands)
            )
            
            let spectrum = highlightWaveform(spectrum: spectrum)
            
            // Apply smoothing to spectrum buffer
            let zipped = zip(spectrumBuffer[i], spectrum)
            spectrumBuffer[i] = zipped.map { $0.0 * spectrumSmooth + $0.1 * (1 - spectrumSmooth) }
        }
        return spectrumBuffer
    }
}
    
private extension RealtimeAnalyzer {
    // swiftlint: disable shorthand_operator
    func fftChannel(_ channel: UnsafeMutablePointer<Float>, output amplitudes: inout [Float]) {
        vDSP_vmul(channel, 1, hannWindow, 1, channel, 1, vDSP_Length(fftSize))

        // Pack real numbers into complex numbers (fftInOut)
        // required by FFT, which serves as both input and output
        let realptr = realp.withUnsafeMutableBufferPointer { $0 }
        let imagptr = imagp.withUnsafeMutableBufferPointer { $0 }
        var fftInOut = DSPSplitComplex(realp: realptr.baseAddress!, imagp: imagptr.baseAddress!)

        channel.withMemoryRebound(to: DSPComplex.self, capacity: fftSize) { typeConvertedTransferBuffer in
            vDSP_ctoz(typeConvertedTransferBuffer, 2, &fftInOut, 1, vDSP_Length(fftSize / 2))
        }

        // Perform FFT
        vDSP_fft_zrip(fftSetup!, &fftInOut, 1, vDSP_Length(round(log2(Double(fftSize)))), FFTDirection(FFT_FORWARD))

        // Adjust FFT results and calculate amplitudes
        fftInOut.imagp[0] = 0
        let fftNormFactor = Float(1.0 / Float(fftSize))
        vDSP_vsmul(fftInOut.realp, 1, [fftNormFactor], fftInOut.realp, 1, vDSP_Length(fftSize / 2))
        vDSP_vsmul(fftInOut.imagp, 1, [fftNormFactor], fftInOut.imagp, 1, vDSP_Length(fftSize / 2))
        vDSP_zvabs(&fftInOut, 1, &amplitudes, 1, vDSP_Length(fftSize / 2))
        amplitudes[0] = amplitudes[0] / 2 // DC component amplitude needs to be divided by 2
    }
    // swiftlint: enable shorthand_operator

    func findMaxAmplitude(
        for indices: (startIndex: Int, endIndex: Int),
        in amplitudes: [Float],
        output maxAmplitude: inout Float
    ) {
        // Find maximum amplitude in the specified frequency band
        amplitudes.withUnsafeBufferPointer { buffer in
            vDSP_maxv(
                buffer.baseAddress! + indices.startIndex,
                1,
                &maxAmplitude,
                vDSP_Length(indices.endIndex - indices.startIndex + 1)
            )
        }
    }

    func highlightWaveform(spectrum: [Float]) -> [Float] {
        // 1: Define weights array, the middle 5 represents the weight of the current element
        //   Can be modified freely, but the count must be odd
        let weights: [Float] = [1, 2, 3, 5, 3, 2, 1]
        let totalWeights = Float(weights.reduce(0, +))
        let startIndex = weights.count / 2
        // 2: The first few elements don't participate in calculation
        var averagedSpectrum = Array(spectrum[0 ..< startIndex])
        for i in startIndex ..< spectrum.count - startIndex {
            // 3: zip function: zip([a,b,c], [x,y,z]) -> [(a,x), (b,y), (c,z)]
            let zipped = zip(Array(spectrum[i - startIndex ... i + startIndex]), weights)
            let averaged = zipped.map { $0.0 * $0.1 }.reduce(0, +) / totalWeights
            averagedSpectrum.append(averaged)
        }
        // 4: The last few elements don't participate in calculation
        averagedSpectrum.append(contentsOf: Array(spectrum.suffix(startIndex)))
        return averagedSpectrum
    }
    
    static func createFrequencyWeights(fftSize: Int, sampleRate: Double) -> [Float] {
        guard fftSize > 0 else { return [] }
        let deltaF = Float(sampleRate) / Float(fftSize) // Шаг по частоте для одного бина FFT
        let bins = fftSize / 2 // Анализируем fftSize/2 частотных бинов (результат БПФ действительного сигнала)
        
        var f = (0 ..< bins).map { Float($0) * deltaF } // Частота для каждого бина
        f = f.map { $0 * $0 } // f^2
        
        let c1 = powf(12194.217, 2.0)
        let c2 = powf(20.598997, 2.0)
        let c3 = powf(107.65265, 2.0)
        let c4 = powf(737.86223, 2.0)
        
        let num = f.map { c1 * $0 * $0 } // c1 * f^4
        let den = f.map { ($0 + c2) * sqrtf(max(0, ($0 + c3) * ($0 + c4))) * ($0 + c1) }
        
        let weights = num.enumerated().map { index, element -> Float in
            guard den[index] != 0 else { return 0.0 }
            return 1.2589 * element / den[index]
        }
        return weights
    }
    
    static func createBandIndices(
        fftSize: Int,
        sampleRate: Double,
        bands: [Band]
    ) -> [(startIndex: Int, endIndex: Int)] {
        // Precompute band indices based on current sample rate
        let bandWidth = Float(sampleRate) / Float(fftSize)
        return bands.map {
            let startIndex = Int(round($0.lowerFrequency / bandWidth))
            let endIndex = min(Int(round($0.upperFrequency / bandWidth)), fftSize / 2 - 1)
            return (startIndex, endIndex)
        }
    }
    
    static func createBands(
        frequencyBands: Int,
        startFrequency: Float,
        endFrequency: Float
    ) -> [Band] {
        var bands: [Band] = []
        // 1: Determine the growth factor based on start/end frequencies and number of bands: 2^n
        let n = log2(endFrequency / startFrequency) / Float(frequencyBands)
        var nextBand: (lowerFrequency: Float, upperFrequency: Float) = (startFrequency, 0)
        for i in 1 ... frequencyBands {
            // 2: The upper frequency of a band is 2^n times the lower frequency
            let highFrequency = nextBand.lowerFrequency * powf(2, n)
            nextBand.upperFrequency = i == frequencyBands ? endFrequency : highFrequency
            bands.append(
                Band(lowerFrequency: nextBand.lowerFrequency, upperFrequency: nextBand.upperFrequency)
            )
            nextBand.lowerFrequency = highFrequency
        }
        return bands
    }
}
