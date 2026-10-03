// 0.99.0 MIDI byte-stream parser for the standalone's hardware input.
// Mirrors the AU's controller map: mod wheel (CC1), sustain (CC64), all sound /
// notes off (CC120/123), channel and poly pressure, 14-bit pitch bend. Omni:
// every channel plays. A packet may hold several messages, use running status,
// or interleave realtime bytes; SysEx and anything else is skipped, and a
// message cut short is dropped.
#pragma once
#include <cstddef>
#include <cstdint>
#include <vector>

namespace muew {

struct MidiEvent {
    enum Kind { NoteOn, NoteOff, Wheel, Aftertouch, PolyAftertouch, Bend, Sustain, AllNotesOff } kind;
    int note = 0;
    float value = 0.0f; // velocity / controller 0..1 / bend -1..1
};

inline std::vector<MidiEvent> parseMidiBytes(const uint8_t* d, size_t n) {
    std::vector<MidiEvent> out;
    uint8_t status = 0; // running status
    int need = 0; int have = 0; uint8_t data[2] = {0, 0};
    bool inSysex = false;
    auto emit = [&] {
        const uint8_t type = status & 0xF0;
        if (type == 0x90 && data[1] > 0) out.push_back({MidiEvent::NoteOn, data[0] & 0x7F, (data[1] & 0x7F) / 127.0f});
        else if (type == 0x80 || type == 0x90) out.push_back({MidiEvent::NoteOff, data[0] & 0x7F, 0.0f});
        else if (type == 0xB0) {
            if (data[0] == 1) out.push_back({MidiEvent::Wheel, 0, (data[1] & 0x7F) / 127.0f});
            else if (data[0] == 64) out.push_back({MidiEvent::Sustain, 0, data[1] >= 64 ? 1.0f : 0.0f});
            else if (data[0] == 120 || data[0] == 123) out.push_back({MidiEvent::AllNotesOff, 0, 0.0f});
        } else if (type == 0xD0) out.push_back({MidiEvent::Aftertouch, 0, (data[0] & 0x7F) / 127.0f});
        else if (type == 0xA0) out.push_back({MidiEvent::PolyAftertouch, data[0] & 0x7F, (data[1] & 0x7F) / 127.0f});
        else if (type == 0xE0) {
            const int raw = ((data[1] & 0x7F) << 7) | (data[0] & 0x7F);
            out.push_back({MidiEvent::Bend, 0, raw >= 8192 ? (raw - 8192) / 8191.0f : (raw - 8192) / 8192.0f});
        }
    };
    for (size_t i = 0; i < n; ++i) {
        const uint8_t b = d[i];
        if (b >= 0xF8) continue; // realtime: never disturbs running status or a message in flight
        if (inSysex) { if (b == 0xF7) inSysex = false; if (b >= 0x80) { if (b != 0xF7) { inSysex = false; } else continue; } else continue; }
        if (b >= 0x80) {
            have = 0;
            if (b == 0xF0) { inSysex = true; status = 0; need = 0; continue; }
            if (b >= 0xF0) { status = 0; need = 0; continue; } // other system common: skipped
            status = b;
            const uint8_t t = b & 0xF0; need = (t == 0xC0 || t == 0xD0) ? 1 : 2;
            continue;
        }
        if (!status) continue; // stray data byte
        data[have++] = b;
        if (have == need) { emit(); have = 0; }
    }
    return out;
}

} // namespace muew
