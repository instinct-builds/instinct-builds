// MUEWMidiInput.h - hardware MIDI input for the standalone (0.99.0).
// Connects every MIDI source, follows hot-plug, and hands parsed events to a
// handler. The handler runs on a CoreMIDI thread; the caller takes its own lock.
#pragma once
#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>
#include <set>
#include "midi_in.h"

@interface MUEWMidiInput : NSObject
- (instancetype)initWithHandler:(void (^)(const muew::MidiEvent&))handler;
- (void)refresh;                         // connect any source not yet connected
@property(nonatomic, readonly) BOOL available;      // CoreMIDI client and input port exist
@property(nonatomic, readonly) int connectedSources;
@end

@implementation MUEWMidiInput {
    MIDIClientRef client; MIDIPortRef port;
    std::set<SInt32> connected;
    void (^handler)(const muew::MidiEvent&);
}
- (instancetype)initWithHandler:(void (^)(const muew::MidiEvent&))h {
    if ((self = [super init])) {
        handler = [h copy]; client = 0; port = 0;
        __weak MUEWMidiInput* weak = self;
        if (MIDIClientCreateWithBlock(CFSTR("MUEW"), &client, ^(const MIDINotification* n) {
                if (n->messageID == kMIDIMsgSetupChanged) dispatch_async(dispatch_get_main_queue(), ^{ [weak refresh]; });
            }) != noErr) { client = 0; return self; }
        if (MIDIInputPortCreateWithBlock(client, CFSTR("MUEW input"), &port, ^(const MIDIPacketList* list, void*) {
                MUEWMidiInput* s = weak; if (!s) return;
                const MIDIPacket* p = &list->packet[0];
                for (UInt32 i = 0; i < list->numPackets; ++i) {
                    for (const auto& ev : muew::parseMidiBytes(p->data, p->length)) [s deliver:ev];
                    p = MIDIPacketNext(p);
                }
            }) != noErr) { port = 0; return self; }
        [self refresh];
    }
    return self;
}
- (void)deliver:(const muew::MidiEvent&)e { if (handler) handler(e); }
- (BOOL)available { return client != 0 && port != 0; }
- (int)connectedSources { return (int)connected.size(); }
- (void)refresh {
    if (!port) return;
    std::set<SInt32> present;
    for (ItemCount i = 0; i < MIDIGetNumberOfSources(); ++i) {
        MIDIEndpointRef src = MIDIGetSource(i);
        SInt32 uid = 0; MIDIObjectGetIntegerProperty(src, kMIDIPropertyUniqueID, &uid);
        present.insert(uid);
        if (!connected.count(uid) && MIDIPortConnectSource(port, src, NULL) == noErr) connected.insert(uid);
    }
    for (auto it = connected.begin(); it != connected.end();) it = present.count(*it) ? std::next(it) : connected.erase(it); // unplugged: reconnect on return
}
@end
