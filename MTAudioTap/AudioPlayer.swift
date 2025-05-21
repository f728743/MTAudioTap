//
//  AudioPlayer.swift
//  MTAudioTap
//
//  Created by Alexey Vorobyov on 01.06.2025.
//

@preconcurrency import AVFoundation

enum PlayerError: Error {
    case failedToCreateTap
    case noAudioTrack
}

@MainActor
protocol AudioPlayerDelegate: AnyObject {
    func audioPlayer(_ player: AudioPlayer, didUpdateSpectrum spectrum: [[Float]])
    func audioPlayer(_ player: AudioPlayer, didChangeStatus status: AVPlayerItem.Status)
}

@MainActor
final class AudioPlayer {
    private let tapProcessor: AudioTapProcessor
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var tracksObserver: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?

    weak var delegate: AudioPlayerDelegate?

    init() {
        tapProcessor = AudioTapProcessor(sampleRate: 48000.0)
        tapProcessor.delegate = self
    }

    func play(url: URL) async throws {
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        guard let audioTrack = try await playerItem?.asset.loadTracks(withMediaType: .audio).first else {
            print("No audio track found.")
            throw PlayerError.noAudioTrack
        }

        tracksObserver = playerItem?.observe(\.tracks, options: [.new, .initial]) { [weak self] item, _ in
            guard let self, !item.tracks.isEmpty else { return }
            Task { @MainActor [weak self] in
                try await self?.installTap(playerItem: item, audioTrack: audioTrack)
            }
        }

        statusObservation = playerItem?.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            print("PlayerItem status changed: \(item.status.rawValue)")
            Task { @MainActor in
                self.delegate?.audioPlayer(self, didChangeStatus: item.status)
            }
            if item.status == .readyToPlay {
                Task { @MainActor in
                    self.player?.play()
                }
            } else if item.status == .failed {
                print("PlayerItem status failed: \(item.error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        player?.pause()
        playerItem?.audioMix = nil
        tracksObserver?.invalidate()
        statusObservation?.invalidate()
        playerItem = nil
        player = nil
    }

    private func installTap(playerItem: AVPlayerItem, audioTrack: AVAssetTrack) async throws {
        let createdTap = try tapProcessor.createTap()
        let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParams.audioTapProcessor = createdTap.takeRetainedValue()

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParams]
        playerItem.audioMix = audioMix
    }
}

extension AudioPlayer: AudioTapProcessorDelegate {
    nonisolated func audioTapProcessor(_: AudioTapProcessor, didUpdateSpectrum spectrum: [[Float]]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.audioPlayer(self, didUpdateSpectrum: spectrum)
        }
    }
}
