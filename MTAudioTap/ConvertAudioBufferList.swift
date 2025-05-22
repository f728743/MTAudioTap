//
//  ConvertAudioBufferList.swift
//  MTAudioTap
//
//  Created by Alexey Vorobyov on 21.05.2025.
//

import AVFoundation
import CoreAudio

// Важно: Эта функция предполагает, что 'frameCount' (количество аудиокадров) известно.
// В реальном сценарии это может быть количество кадров из AURenderCallback (inNumberFrames)
// или вычислено из mDataByteSize первого буфера и описания формата (ASBD).
// 'asbd' (AudioStreamBasicDescription) описывает формат данных в audioBufferList.

func convertAudioBufferListToPCMBuffer(
    audioBufferList: UnsafeMutablePointer<AudioBufferList>,
    asbd: AudioStreamBasicDescription, // Передаем копию, чтобы можно было взять указатель
    frameCount: AVAudioFrameCount // Количество аудиокадров (сэмплов на канал)
) -> AVAudioPCMBuffer? {
    // 1. Определите AVAudioFormat на основе AudioStreamBasicDescription
    //    AVAudioFormat(streamDescription:) ожидает UnsafePointer<AudioStreamBasicDescription>
//    var mutableAsbd = asbd
//    guard let format = AVAudioFormat(streamDescription: &mutableAsbd) else {
//        print("Не удалось создать AVAudioFormat из ASBD.")
//        return nil
//    }
//
    // Создание аудиоформата (пример для 44.1 kHz стерео)
    guard let format = AVAudioFormat(
        standardFormatWithSampleRate: asbd.mSampleRate,
        channels: asbd.mChannelsPerFrame
    ) else {
        print("Не удалось создать AVAudioFormat из ASBD.")
        return nil
    }

    // 2. Создайте AVAudioPCMBuffer
    //    frameCapacity должен быть достаточным для хранения всех семплов.
    guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        print("Не удалось создать AVAudioPCMBuffer.")
        return nil
    }
    // Устанавливаем фактическую длину буфера (количество валидных семплов на канал)
    pcmBuffer.frameLength = frameCount

    // 3. Получите доступ к буферам в AudioBufferList с помощью UnsafeAudioBufferListPointer
    //    Это правильный способ итерации по mBuffers.
    let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

    // 4. Скопируйте данные из AudioBufferList в AVAudioPCMBuffer
    if format.isInterleaved {
        // --- Случай с чередующимися данными (interleaved) ---
        // В этом случае ожидается, что AudioBufferList содержит один AudioBuffer,
        // в котором данные всех каналов идут последовательно (например, LRLRLR...).
        guard ablPointer.count == 1 else {
            print("Ошибка: Ожидался 1 буфер в AudioBufferList для interleaved-данных, получено \(ablPointer.count).")
            return nil
        }

        let sourceAudioBuffer = ablPointer[0] // Один буфер с чередующимися данными
        guard let sourceRawData = sourceAudioBuffer.mData else {
            print("mData для interleaved AudioBuffer равен nil.")
            return nil
        }

        // Общее количество элементов данных для копирования (например, Float, Int16)
        // для всех каналов в чередующемся буфере.
        let totalElementsToCopy = Int(frameCount) * Int(format.channelCount)

//         Проверка mDataByteSize (опционально, но рекомендуется):
//         let bytesPerElement = mutableAsbd.mBytesPerFrame / mutableAsbd.mChannelsPerFrame
//         if sourceAudioBuffer.mDataByteSize < totalElementsToCopy * Int(bytesPerElement) {
//             print("Ошибка: mDataByteSize (\(sourceAudioBuffer.mDataByteSize)) " +
//                   "слишком мал для копирования \(totalElementsToCopy) элементов.")
//             return nil
//         }

        switch format.commonFormat {
        case .pcmFormatFloat32:
            // Для interleaved, floatChannelData[0] указывает на начало буфера.
            guard let destChannelData = pcmBuffer.floatChannelData?[0] else {
                print("floatChannelData[0] в AVAudioPCMBuffer равен nil для interleaved float32.")
                return nil
            }
            let sourceTypedData = sourceRawData.assumingMemoryBound(to: Float.self)
            destChannelData.initialize(from: sourceTypedData, count: totalElementsToCopy)
        case .pcmFormatInt16:
            guard let destChannelData = pcmBuffer.int16ChannelData?[0] else {
                print("int16ChannelData[0] в AVAudioPCMBuffer равен nil для interleaved int16.")
                return nil
            }
            let sourceTypedData = sourceRawData.assumingMemoryBound(to: Int16.self)
            destChannelData.initialize(from: sourceTypedData, count: totalElementsToCopy)
        case .pcmFormatInt32:
            guard let destChannelData = pcmBuffer.int32ChannelData?[0] else {
                print("int32ChannelData[0] в AVAudioPCMBuffer равен nil для interleaved int32.")
                return nil
            }
            let sourceTypedData = sourceRawData.assumingMemoryBound(to: Int32.self)
            destChannelData.initialize(from: sourceTypedData, count: totalElementsToCopy)
        default:
            print("Неподдерживаемый AVAudioCommonFormat для interleaved: \(format.commonFormat).")
            return nil
        }
    } else {
        // --- Случай с не чередующимися данными (non-interleaved) ---
        // В этом случае AudioBufferList содержит по одному AudioBuffer на каждый канал.
        // Количество буферов в ablPointer должно совпадать с количеством каналов в pcmBuffer.
        let expectedChannelCount = Int(format.channelCount)
        guard ablPointer.count == expectedChannelCount else {
            print("Расхождение в количестве каналов: AudioBufferList (\(ablPointer.count)) " +
                "и AVAudioPCMBuffer (\(expectedChannelCount)) для non-interleaved.")
            return nil
        }

        for channelIndex in 0 ..< expectedChannelCount {
            let sourceAudioBuffer = ablPointer[channelIndex] // Буфер для текущего канала
            guard let sourceRawData = sourceAudioBuffer.mData else {
                print("mData для AudioBuffer канала \(channelIndex) равен nil.")
                // Можно пропустить этот канал или вернуть ошибку в зависимости от требований
                continue // или return nil, если это критично
            }

            // Проверка mDataByteSize для этого канала (опционально, но рекомендуется):
//             let bytesPerElement = ... (например, MemoryLayout<Float>.size)
//             if sourceAudioBuffer.mDataByteSize < Int(frameCount) * bytesPerElement {
//                print("Ошибка: mDataByteSize (\(sourceAudioBuffer.mDataByteSize)) для " +
//                      "канала \(channelIndex) слишком мал.")
//                continue // или return nil
//             }

            switch format.commonFormat {
            case .pcmFormatFloat32:
                // floatChannelData это UnsafePointer<UnsafeMutablePointer<Float>>?
                // destDataPointers[channelIndex] дает UnsafeMutablePointer<Float> для конкретного канала.
                guard let destDataPointers = pcmBuffer.floatChannelData else {
                    print("floatChannelData в AVAudioPCMBuffer равен nil для non-interleaved float32.")
                    return nil // Это не должно произойти, если pcmBuffer создан правильно
                }
                let destChannelData = destDataPointers[channelIndex]
                let sourceTypedData = sourceRawData.assumingMemoryBound(to: Float.self)
                destChannelData.initialize(from: sourceTypedData, count: Int(frameCount))
            case .pcmFormatInt16:
                guard let destDataPointers = pcmBuffer.int16ChannelData else {
                    print("int16ChannelData в AVAudioPCMBuffer равен nil для non-interleaved int16.")
                    return nil
                }
                let destChannelData = destDataPointers[channelIndex]
                let sourceTypedData = sourceRawData.assumingMemoryBound(to: Int16.self)
                destChannelData.initialize(from: sourceTypedData, count: Int(frameCount))
            case .pcmFormatInt32:
                guard let destDataPointers = pcmBuffer.int32ChannelData else {
                    print("int32ChannelData в AVAudioPCMBuffer равен nil для non-interleaved int32.")
                    return nil
                }
                let destChannelData = destDataPointers[channelIndex]
                let sourceTypedData = sourceRawData.assumingMemoryBound(to: Int32.self)
                destChannelData.initialize(from: sourceTypedData, count: Int(frameCount))
            default:
                print("Неподдерживаемый AVAudioCommonFormat для non-interleaved: " +
                    "\(format.commonFormat), канал \(channelIndex).")
                // Можно пропустить этот канал или вернуть ошибку
                continue // или return nil
            }
        }
    }
    return pcmBuffer
}
