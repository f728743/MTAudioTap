//
//  AudioTapProcessor.swift
//  MTAudioTap
//
//  Created by Alexey Vorobyov on 01.06.2025.
//

@preconcurrency import AVFoundation

protocol AudioTapProcessorDelegate: AnyObject {
    func audioTapProcessor(_ analyzer: AudioTapProcessor, didUpdateSpectrum spectrum: [[Float]])
}

final class AudioTapProcessor {
    private let analyzer: SpectrumAnalyzer
    weak var delegate: AudioTapProcessorDelegate?

    init(sampleRate: Double = 48000.0) {
        analyzer = SpectrumAnalyzer(
            fftSize: 2048,
            sampleRate: sampleRate,
            mono: true
        )
        analyzer.delegate = self
    }

    private let tapProcess: MTAudioProcessingTapProcessCallback = { tap, frames, _, bufferList, framesOut, flagsOut in
        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            frames,
            bufferList,
            flagsOut,
            nil,
            framesOut
        )

        if status != noErr {
            print("Error getting source audio: \(status)")
            return
        }

        let tapContext = Unmanaged<AudioTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        guard let analyzer = tapContext.content else {
            print("Tap callback: tapContext content (SpectrumAnalyzer) was deallocated!")
            return
        }

        analyzer.analyse(bufferList: bufferList)
    }

    private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
        tapStorageOut.pointee = clientInfo
    }

    private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
        print("finalize \(tap)")
        Unmanaged<AudioTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
    }

    func createTap() throws -> Unmanaged<MTAudioProcessingTap> {
        let tapContext = AudioTapContext(content: analyzer)

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(tapContext).toOpaque()),
            init: tapInit,
            finalize: tapFinalize,
            prepare: nil,
            unprepare: nil,
            process: tapProcess
        )

        var tap: Unmanaged<MTAudioProcessingTap>?

        let err = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )

        guard err == noErr, let createdTap = tap else {
            print("Failed to create audio processing tap. Error: \(err)")
            Unmanaged.passUnretained(tapContext).release()
            throw PlayerError.failedToCreateTap
        }
        return createdTap
    }
}

extension AudioTapProcessor: SpectrumAnalyzerDelegate {
    func spectrumAnalyzer(_: SpectrumAnalyzer, didUpdateSpectrum spectrum: [[Float]]) {
        delegate?.audioTapProcessor(self, didUpdateSpectrum: spectrum)
    }
}

private class AudioTapContext {
    weak var content: SpectrumAnalyzer?

    init(content: SpectrumAnalyzer) {
        self.content = content
    }

    deinit {
        print("AudioTapContext deinit")
    }
}
