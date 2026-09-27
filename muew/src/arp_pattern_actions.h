#pragma once
// 0.72.0 editor-only operations. Never touch fields outside the active pattern.
#include "voice.h"
#include "arp.h"
#include <array>
#include <algorithm>
#include <vector>

namespace muew::arp {
struct StepData {
    int kind, velocity, ratchet, octave, chance, gate, pitch;
    bool operator==(const StepData& o) const {
        return kind==o.kind && velocity==o.velocity && ratchet==o.ratchet && octave==o.octave
            && chance==o.chance && gate==o.gate && pitch==o.pitch;
    }
};
inline StepData readStep(const VoiceParams& v, int i) {
    return {v.arpPatKind[i],v.arpPatVel[i],v.arpPatRatchet[i],v.arpPatOctave[i],
            v.arpPatChance[i],v.arpPatGate[i],v.arpPatPitch[i]};
}
inline void writeStep(VoiceParams& v,int i,const StepData& s) {
    v.arpPatKind[i]=s.kind;v.arpPatVel[i]=s.velocity;v.arpPatRatchet[i]=s.ratchet;
    v.arpPatOctave[i]=s.octave;v.arpPatChance[i]=s.chance;v.arpPatGate[i]=s.gate;v.arpPatPitch[i]=s.pitch;
}
struct PatternSnapshot { std::array<StepData,kPatSteps> steps; };
inline PatternSnapshot snapshot(const VoiceParams& v) {
    PatternSnapshot s;for(int i=0;i<kPatSteps;++i)s.steps[i]=readStep(v,i);return s;
}
inline void restore(VoiceParams& v,const PatternSnapshot& s) {
    for(int i=0;i<kPatSteps;++i)writeStep(v,i,s.steps[i]);
}
class Actions {
public:
    bool copy(const VoiceParams& v,int i) {
        if(i<0||i>=std::clamp(v.arpPatLen,1,kPatSteps))return false;
        copied_=readStep(v,i);hasCopy_=true;sourceStep_=i+1;return true;
    }
    bool paste(VoiceParams& v,int i) {
        if(!hasCopy_||i<0||i>=std::clamp(v.arpPatLen,1,kPatSteps)||readStep(v,i)==copied_)return false;
        remember(v);writeStep(v,i,copied_);return true;
    }
    bool rotate(VoiceParams& v,int direction) {
        int n=std::clamp(v.arpPatLen,1,kPatSteps);
        if(n<=1||direction==0)return false;
        auto prior=snapshot(v);
        bool different=false;
        for(int i=0;i<n;++i)different|=!(prior.steps[i]==prior.steps[(i+(direction>0?n-1:1))%n]);
        if(!different)return false;
        remember(v);
        for(int i=0;i<n;++i)writeStep(v,i,prior.steps[(i+(direction>0?n-1:1))%n]);
        return true;
    }
    bool undo(VoiceParams& v) {
        if(undo_.empty())return false;
        auto s=undo_.back();undo_.pop_back();restore(v,s);return true;
    }
    bool canPaste()const{return hasCopy_;}
    int undoDepth()const{return (int)undo_.size();}
    int copiedSourceStep()const{return hasCopy_?sourceStep_:0;}
    void clear(){undo_.clear();hasCopy_=false;sourceStep_=0;}
    void clearHistory(){undo_.clear();}
    void discardUndo(){if(!undo_.empty())undo_.pop_back();}
private:
    void remember(const VoiceParams& v){if(undo_.size()>=48)undo_.erase(undo_.begin());undo_.push_back(snapshot(v));}
    StepData copied_{};bool hasCopy_=false;int sourceStep_=0;std::vector<PatternSnapshot> undo_;
};
} // namespace muew::arp
