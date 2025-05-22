//
//  MediaPlayerViewModel.swift
//  MTAudioTap
//
//  Created by Alexey Vorobyov on 21.05.2025.
//

import AVFoundation
import Foundation
import Observation

@Observable
final class MediaPlayerViewModel {
    var player: AVPlayer?
    var playerItem: AVPlayerItem!
    var audioStreamBasicDescription: AudioStreamBasicDescription? // To store ASBD

    private let analyzer: RealtimeAnalyzer

    class TapCookie {
        weak var content: MediaPlayerViewModel?

        init(content: MediaPlayerViewModel) {
            self.content = content
        }

        deinit {
            print("TapCookie deinit")
        }
    }

    let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
        tapStorageOut.pointee = clientInfo
    }

    let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
        print("finalize \(tap)\n")
        Unmanaged<TapCookie>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
    }

    // Corrected tapProcess
    let tapProcess: MTAudioProcessingTapProcessCallback =
    { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
        var status = MTAudioProcessingTapGetSourceAudio(
            tap,
            numberFrames,
            bufferListInOut,
            flagsOut,
            nil,
            numberFramesOut
        )

        if noErr != status {
            print("Error getting source audio: \(status)\n")
            // If MTAudioProcessingTapGetSourceAudio fails, bufferListInOut might not be populated
            // or might be in an indeterminate state. Depending on the error,
            // you might want to return early here.
            // For example, if status indicates a severe error, further processing is likely futile.
            return
        }

        let cookie = Unmanaged<TapCookie>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        guard let viewModel = cookie.content else {
            print("Tap callback: cookie content (MediaPlayerViewModel) was deallocated!")
            return
        }

        guard let asbd = viewModel.audioStreamBasicDescription else {
            print("Tap callback: ASBD not found in ViewModel!")
            return
        }

        // The `bufferListInOut` pointer itself is non-optional here.
        // We pass it directly to the conversion function.
        if let pcmBuffer = convertAudioBufferListToPCMBuffer(
            audioBufferList: bufferListInOut, // Pass directly
            asbd: asbd,
            frameCount: AVAudioFrameCount(numberFrames)
        ) {
            // Call analyse. Consider dispatching if analysis is heavy.
            // DispatchQueue.main.async { // If analyse updates UI
            viewModel.analyse(buffer: pcmBuffer)
            // }
        } else {
            print("Tap callback: Failed to convert AudioBufferList to AVAudioPCMBuffer.")
        }
    }

    var tracksObserver: NSKeyValueObservation?
    var statusObservation: NSKeyValueObservation?

    var isPlaying: Bool = false

    let bufferSize: Int = 2048
    var spectra: [[Float]] = []

    init() {
        analyzer = RealtimeAnalyzer(fftSize: bufferSize)
    }

    func play() {
        isPlaying = true
        doPlay()
    }
}

private extension MediaPlayerViewModel {
    func analyse(buffer: AVAudioPCMBuffer) {
        buffer.frameLength = AVAudioFrameCount(bufferSize)
        let spectra = analyzer.analyse(with: buffer)
        DispatchQueue.main.async {
            self.spectra = spectra
        }
    }

    func doPlay() {
        let path = "https://raw.githubusercontent.com/tmp-acc/" +
            "GTA-V-Radio-Stations/master/common/adverts/ad082_alcoholia.m4a"
        let url = URL(string: path)!

        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        tracksObserver = playerItem.observe(\AVPlayerItem.tracks, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            NSLog("PlayerItem tracks changed: \(item.tracks)")
            // Ensure tracks are loaded before installing tap
            if !item.tracks.isEmpty {
                // Check if tap is already installed or if ASBD is already set to avoid redundant setup
                if audioStreamBasicDescription == nil {
                    installTap(playerItem: item)
                }
            }
        }

        statusObservation = playerItem.observe(
            \AVPlayerItem.status, options: [.new, .initial]
        ) { [weak self] object, _ in
            guard let self else { return }
            NSLog("PlayerItem status changed: \(object.status.rawValue)")
            if object.status == .readyToPlay {
                player?.play()

                // For testing finalize and cookie deallocation
                // DispatchQueue.main.asyncAfter(deadline: .now() + 15) { // Increased time
                //     print("\"deallocating\" tap by resetting playerItem and player")
                //     self.tracksObserver?.invalidate()
                //     self.statusObservation?.invalidate()
                //     self.playerItem?.audioMix = nil // Explicitly remove audioMix to help release tap
                //     self.playerItem = nil
                //     self.player = nil
                //     self.audioStreamBasicDescription = nil // Reset ASBD
                //     print("Player and playerItem set to nil.")
                // }
            } else if object.status == .failed {
                NSLog("PlayerItem status failed: \(object.error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

    func installTap(playerItem: AVPlayerItem) {
        guard let audioTrack = playerItem.asset.tracks(withMediaType: .audio).first else {
            print("No audio track found.")
            return
        }

        // Extract ASBD from the audio track's format descriptions
        guard let formatDescriptions = audioTrack.formatDescriptions as? [CMFormatDescription],
              let formatDesc = formatDescriptions.first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
        else {
            print("Could not get AudioStreamBasicDescription from track.")
            return
        }
        audioStreamBasicDescription = asbd // Store ASBD

        let cookie = TapCookie(content: self)

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(cookie).toOpaque()),
            init: tapInit,
            finalize: tapFinalize,
            prepare: nil,
            unprepare: nil,
            process: tapProcess // tapProcess is now a property of the class instance
        )

        var tap: Unmanaged<MTAudioProcessingTap>?
        let err = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects, // Or kMTAudioProcessingTapCreationFlag_PreEffects
            &tap
        )

        guard err == noErr, let createdTap = tap else {
            print("Failed to create audio processing tap. Error: \(err)")
            Unmanaged.passUnretained(cookie).release() // Manually release cookie if tap creation failed after retain
            audioStreamBasicDescription = nil // Reset ASBD if tap creation fails
            return
        }

        let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParams.audioTapProcessor = createdTap.takeRetainedValue()

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParams]

        playerItem.audioMix = audioMix
        print("Audio tap installed successfully on track: \(audioTrack.description)")
    }
}
