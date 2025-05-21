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

    // looks like you can't stop an audio tap synchronously, so it's possible for your clientInfo/tapStorage
    // refCon/cookie object to go out of scope while the tap process callback is still being called.
    // As a solution wrap your object of interest as a weak reference that can be guarded against
    // inside an object (cookie) whose scope we do control.
    class TapCookie {
        weak var content: AnyObject?

        init(content: AnyObject) {
            self.content = content
        }

        deinit {
            print("TapCookie deinit") // should appear after finalize
        }
    }

    let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
        // Make tap storage the same as clientInfo. I guess you might want them to be different.
        tapStorageOut.pointee = clientInfo
    }

    let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
        print("finalize \(tap)\n")

        // release cookie
        Unmanaged<TapCookie>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
    }

    let tapProcess: MTAudioProcessingTapProcessCallback =
    { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
        print("callback \(tap), \(numberFrames), \(flags), \(bufferListInOut), \(numberFramesOut), \(flagsOut)")

        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            numberFrames,
            bufferListInOut,
            flagsOut,
            nil,
            numberFramesOut
        )
        if noErr != status {
            print("get audio: \(status)\n")
        }

        let cookie = Unmanaged<TapCookie>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
        guard let cookieContent = cookie.content else {
            print("Tap callback: cookie content was deallocated!")
            return
        }

//        let appDelegateSelf = cookieContent as! AppDelegate
//        print("cookie content \(appDelegateSelf)")
    }

    var tracksObserver: NSKeyValueObservation?
    var statusObservation: NSKeyValueObservation?

    var isPlaying: Bool = false

    func play() {
        isPlaying = true
        doit()
    }
}

private extension MediaPlayerViewModel {
    func doit() {
        // some remote resources work. maybe those with ContentLength?
        let path = "https://raw.githubusercontent.com/tmp-acc/" +
        "GTA-V-Radio-Stations/master/common/adverts/ad082_alcoholia.m4a"
        // let s = "http://live-radio01.mediahubaustralia.com/2LRW/mp3/"    // doesn't work any more
        let url = URL(string: path)!
        //        let url = Bundle.main.url(forResource: "foo", withExtension: "m4a")!     // local resource works

        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        tracksObserver = playerItem.observe(\AVPlayerItem.tracks) { [unowned self] item, _ in
            NSLog("tracks change \(item.tracks)")
            NSLog("asset tracks (btw) \(item.asset.tracks)")
            installTap(playerItem: playerItem)
        }

        statusObservation = playerItem.observe(\AVPlayerItem.status) { [unowned self] object, _ in
            NSLog("playerItem status change \(object.status.rawValue)")
            if object.status == .readyToPlay {
                player?.play()

                // indirectly stop and dealloc tap to test finalize and cookie code.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    print("\"deallocating\" tap")
                    self.playerItem = nil
                    self.player = nil
                }
            }
        }
    }

    // assumes tracks are loaded
    func installTap(playerItem: AVPlayerItem) {
        let cookie = TapCookie(content: self)

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(cookie).toOpaque()),
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
        assert(noErr == err)

        // let audioTrack = playerItem.tracks.first!.assetTrack!
        let audioTrack = playerItem.asset.tracks(withMediaType: AVMediaType.audio).first!
        let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParams.audioTapProcessor = tap?.takeRetainedValue()

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParams]

        playerItem.audioMix = audioMix
    }
}
