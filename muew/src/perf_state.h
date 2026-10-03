// 0.107.0 performance state the standalone shows in the editor (wheel, pressure,
// bend, last note, sustain), fed from parsed MIDI events and the computer
// keyboard. Written from the MIDI thread, read by the UI timer, so every field
// is atomic.
#pragma once
#include "midi_in.h"
#include "voice.h"
#include <atomic>
namespace muew {
class PerfTracker {
public:
    void apply(const MidiEvent& e) {
        switch (e.kind) {
        case MidiEvent::NoteOn: lastNote_ = e.note; break;
        case MidiEvent::Wheel: wheel_ = e.value; break;
        case MidiEvent::Aftertouch: aftertouch_ = e.value; break;
        case MidiEvent::Bend: bend_ = e.value; break;
        case MidiEvent::Sustain: sustain_ = e.value > 0.5f; break;
        case MidiEvent::AllNotesOff: sustain_ = false; break;
        default: break;
        }
    }
    void noteFromKeyboard(int n) { lastNote_ = n; }
    Performance snapshot() const { Performance p; p.wheel = wheel_.load(); p.aftertouch = aftertouch_.load(); p.bend = bend_.load(); return p; }
    int lastNote() const { return lastNote_.load(); }
    bool sustain() const { return sustain_.load(); }
private:
    std::atomic<float> wheel_{0}, aftertouch_{0}, bend_{0};
    std::atomic<int> lastNote_{-1};
    std::atomic<bool> sustain_{false};
};
} // namespace muew
