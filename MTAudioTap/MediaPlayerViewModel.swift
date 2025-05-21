//
//  MediaPlayerViewModel.swift
//  MTAudioTap
//
//  Created by Alexey Vorobyov on 21.05.2025.
//

import AVFoundation
import Observation

@MainActor @Observable
final class MediaPlayerViewModel {
    private let audioPlayer: AudioPlayer
    var isPlaying: Bool = false
    var spectra: [[Float]] = [.init(repeating: 0, count: 5)]
    var preDateTime: Date?

    init() {
        audioPlayer = AudioPlayer()
        audioPlayer.delegate = self
    }

    func play() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isPlaying = true
            let baseUrl = "https://raw.githubusercontent.com/tmp-acc/GTA-V-Radio-Stations/master/"
            let paths = [
                "radio_18_90s_rock/black_grease.m4a",
                "common/adverts/ad082_alcoholia.m4a"
            ]
            let urls = paths.compactMap { URL(string: baseUrl + $0) }
            try await audioPlayer.play(url: urls[0])
        }
    }

    func pause() {
        audioPlayer.pause()
        isPlaying = false
    }

    func stop() {
        audioPlayer.stop()
        isPlaying = false
        spectra = []
    }
}

extension MediaPlayerViewModel: AudioPlayerDelegate {
    func audioPlayer(_: AudioPlayer, didUpdateSpectrum spectrum: [[Float]]) {
        spectra = spectrum
    }

    func audioPlayer(_: AudioPlayer, didChangeStatus status: AVPlayerItem.Status) {
        if status == .failed {
            isPlaying = false
        }
    }
}
