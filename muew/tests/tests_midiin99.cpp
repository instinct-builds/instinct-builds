// 0.99.0 standalone MIDI input parser.
#include "../src/midi_in.h"
#include <cmath>
#include <cstdio>
#include <vector>
using namespace muew;
static int failures = 0;
static void ck(bool ok, const char* msg) { printf("%s %s\n", ok ? "ok:" : "FAIL:", msg); failures += !ok; }
static std::vector<MidiEvent> P(std::initializer_list<uint8_t> b) { std::vector<uint8_t> v(b); return parseMidiBytes(v.data(), v.size()); }
int main() {
    auto e = P({0x90, 60, 127});
    ck(e.size() == 1 && e[0].kind == MidiEvent::NoteOn && e[0].note == 60 && e[0].value == 1.0f, "note on carries note and velocity 0..1");
    e = P({0x90, 60, 0});
    ck(e.size() == 1 && e[0].kind == MidiEvent::NoteOff && e[0].note == 60, "note on with velocity 0 is a note off");
    e = P({0x83, 72, 40});
    ck(e.size() == 1 && e[0].kind == MidiEvent::NoteOff && e[0].note == 72, "note off on any channel (omni)");
    e = P({0x9F, 36, 64});
    ck(e.size() == 1 && e[0].kind == MidiEvent::NoteOn && e[0].note == 36, "note on from channel 16 plays too");
    e = P({0xB0, 1, 127, 0xB0, 1, 0});
    ck(e.size() == 2 && e[0].kind == MidiEvent::Wheel && e[0].value == 1.0f && e[1].value == 0.0f, "mod wheel CC1 0..1, two messages in one packet");
    e = P({0xB0, 64, 127, 0xB0, 64, 63});
    ck(e.size() == 2 && e[0].kind == MidiEvent::Sustain && e[0].value == 1.0f && e[1].value == 0.0f, "sustain CC64 is on at 64 and above");
    e = P({0xB0, 123, 0, 0xB0, 120, 0});
    ck(e.size() == 2 && e[0].kind == MidiEvent::AllNotesOff && e[1].kind == MidiEvent::AllNotesOff, "CC123 and CC120 are all notes off");
    e = P({0xB0, 7, 100, 0xB0, 74, 20});
    ck(e.empty(), "other controllers are ignored");
    e = P({0xD0, 127});
    ck(e.size() == 1 && e[0].kind == MidiEvent::Aftertouch && e[0].value == 1.0f, "channel pressure takes one data byte");
    e = P({0xA0, 64, 127});
    ck(e.size() == 1 && e[0].kind == MidiEvent::PolyAftertouch && e[0].note == 64 && e[0].value == 1.0f, "poly pressure carries its note");
    e = P({0xE0, 0, 64});
    ck(e.size() == 1 && e[0].kind == MidiEvent::Bend && e[0].value == 0.0f, "pitch bend 8192 is center");
    e = P({0xE0, 127, 127, 0xE0, 0, 0});
    ck(e.size() == 2 && std::fabs(e[0].value - 1.0f) < 1e-6f && e[1].value == -1.0f, "pitch bend spans -1 to +1");
    e = P({0x90, 60, 100, 62, 90, 64, 80});
    ck(e.size() == 3 && e[1].note == 62 && e[2].note == 64 && e[2].kind == MidiEvent::NoteOn, "running status keeps playing notes");
    e = P({0xC0, 5});
    ck(e.size() == 1 && e[0].kind == MidiEvent::Program && e[0].note == 5, "program change carries its number (0.102.0)");
    e = P({0xC3, 127, 0x90, 60, 90});
    ck(e.size() == 2 && e[0].kind == MidiEvent::Program && e[0].note == 127 && e[1].kind == MidiEvent::NoteOn, "program change from any channel, then a note");
    e = P({0xC0});
    ck(e.empty(), "a program change with no number is dropped");
    e = P({0x90, 60, 0xF8, 100});
    ck(e.size() == 1 && e[0].kind == MidiEvent::NoteOn && e[0].note == 60 && std::fabs(e[0].value - 100 / 127.0f) < 1e-6f, "a realtime byte inside a message does not break it");
    e = P({0xF0, 0x7E, 0x00, 0x09, 0x01, 0xF7, 0x90, 60, 100});
    ck(e.size() == 1 && e[0].kind == MidiEvent::NoteOn, "SysEx is skipped and the next message still parses");
    e = P({0x90, 60});
    ck(e.empty(), "a message cut short is dropped, never half-played");
    e = P({60, 100, 0x90, 61, 90});
    ck(e.size() == 1 && e[0].note == 61, "stray data bytes before any status are ignored");
    e = P({0xFE, 0xF8});
    ck(e.empty(), "active sensing and clock do nothing");
    printf("%s\n", failures ? "MIDI IN 99 FAILED" : "ALL MIDI IN 99 TESTS PASSED"); return failures ? 1 : 0;
}
