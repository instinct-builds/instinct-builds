// au_host_test.cpp - loads the installed MUEW AU like a host would, plays a
// note, and requires real audio out. Exits non-zero on any failure.
#include <AudioToolbox/AudioToolbox.h>
#include <cmath>
#include <cstdio>
#include <vector>

int main() {
    AudioComponentDescription desc{};
    desc.componentType = kAudioUnitType_MusicDevice;
    desc.componentSubType = 'Muew';
    desc.componentManufacturer = 'Inst';

    AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
    if (!comp) { printf("FAIL: component not registered\n"); return 1; }

    AudioUnit unit = nullptr;
    if (AudioComponentInstanceNew(comp, &unit) != noErr || !unit) {
        printf("FAIL: instance create\n"); return 1;
    }

    AudioStreamBasicDescription fmt{};
    fmt.mSampleRate = 44100.0;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagsNativeEndian;
    fmt.mBytesPerPacket = sizeof(float);
    fmt.mFramesPerPacket = 1;
    fmt.mBytesPerFrame = sizeof(float);
    fmt.mChannelsPerFrame = 2;
    fmt.mBitsPerChannel = 32;
    if (AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &fmt, sizeof(fmt)) != noErr) {
        printf("FAIL: set stream format\n"); return 1;
    }
    if (AudioUnitInitialize(unit) != noErr) { printf("FAIL: initialize\n"); return 1; }

    // A4 on
    if (MusicDeviceMIDIEvent(unit, 0x90, 69, 110, 0) != noErr) { printf("FAIL: note on\n"); return 1; }

    const UInt32 frames = 512;
    std::vector<float> left(frames), right(frames);
    AudioBufferList* bufs = (AudioBufferList*)malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer));
    bufs->mNumberBuffers = 2;
    bufs->mBuffers[0] = {2, frames * sizeof(float), left.data()};
    bufs->mBuffers[1] = {2, frames * sizeof(float), right.data()};

    double sumSq = 0.0;
    AudioUnitRenderActionFlags flags = 0;
    AudioTimeStamp ts{};
    for (int block = 0; block < 20; ++block) {
        OSStatus err = AudioUnitRender(unit, &flags, &ts, 0, frames, bufs);
        if (err != noErr) { printf("FAIL: render err %d\n", (int)err); return 1; }
        for (UInt32 i = 0; i < frames; ++i) sumSq += double(left[i]) * left[i] + double(right[i]) * right[i];
    }
    MusicDeviceMIDIEvent(unit, 0x80, 69, 0, 0);
    AudioUnitUninitialize(unit);
    AudioComponentInstanceDispose(unit);
    free(bufs);

    double rms = std::sqrt(sumSq / (20.0 * frames * 2.0));
    printf("note RMS: %.6f\n", rms);
    if (rms < 0.001) { printf("FAIL: silent output\n"); return 1; }
    printf("PASS: MUEW AU rendered audio\n");
    return 0;
}
