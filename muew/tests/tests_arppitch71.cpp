#include "../src/preset.h"
#include "../src/synth.h"
#include <cstdio>
#include <vector>
using namespace muew;
static int bad=0;static void ck(bool ok,const char*s){printf("%s %s\n",ok?"ok:":"FAIL:",s);bad+=!ok;}
static void tick(Synth&s,int n){float x[2];for(int i=0;i<n;++i)s.renderStereo(x,1);}
static std::vector<int> steps(VoiceParams v,bool host,int note=60){Synth s;s.init(44100);s.setTempo(120);s.setParams(v,{});s.noteOn(note,.8f);if(host)s.setTransport(0,true);std::vector<int> out;for(int i=0;i<4;++i){if(host)s.setTransport(i*.25,true);tick(s,1);out.push_back(s.arpSoundingNote());if(!host)tick(s,5512);}return out;}
int main(){
 Preset p,q;auto old=p.serialize();ck(old.find("\narps ")==std::string::npos,"zero offsets omit arps");
 p.voice.arpPatPitch[0]=7;p.voice.arpPatPitch[3]=-12;auto text=p.serialize();ck(text.find("\narps 7 0 0 -12 ")!=std::string::npos&&q.parse(text)&&q==p&&q.serialize()==text,"offsets round-trip without changing old lines");
 Preset legacy;ck(legacy.parse(old)&&legacy.voice.arpPatPitch[0]==0,"older presets default to neutral pitch");
 Preset bound;ck(bound.parse(old+"arps -40 40 5\n")&&bound.voice.arpPatPitch[0]==-12&&bound.voice.arpPatPitch[1]==12&&bound.voice.arpPatPitch[2]==5&&bound.voice.arpPatPitch[3]==0,"malformed and short line clamps and preserves missing defaults");
 VoiceParams v;v.arpOn=true;v.arpPatOn=true;v.arpPatLen=4;v.arpGate=1;v.clockSync=true;v.arpPatPitch[0]=7;v.arpPatPitch[1]=-5;v.arpPatKind[2]=arp::StepTie;v.arpPatKind[3]=arp::StepRest;
 auto free=steps(v,false),host=steps(v,true);
 ck(free==std::vector<int>({67,55,55,-1}),"free clock shifts ON pitch; TIE holds and REST mutes");
 printf("host steps: %d %d %d %d\n",host[0],host[1],host[2],host[3]);
 ck(host==free,"locked host beat grid retains shifted pitch and TIE/REST semantics");
 v.arpPatPitch[0]=0;v.arpPatPitch[1]=0;auto neutral=steps(v,false);ck(neutral==std::vector<int>({60,60,60,-1}),"neutral offsets preserve old arp notes");
 v.arpPatKind[1]=arp::StepRest;v.arpPatKind[2]=arp::StepOn;v.arpPatKind[3]=arp::StepOn;v.arpPatPitch[0]=12;v.arpPatPitch[1]=-12;v.arpPatPitch[2]=-12;v.arpPatPitch[3]=12;
 ck(steps(v,false,120)==std::vector<int>({127,-1,108,127}),"high MIDI pitch clamps, REST never plays despite offset");
 auto low=steps(v,true,4);printf("low host: %d %d %d %d\n",low[0],low[1],low[2],low[3]);
 ck(low==std::vector<int>({16,-1,0,16}),"low MIDI pitch clamps under host lock");
 v.arpPatKind[1]=arp::StepOn;v.arpPatPitch[0]=7;v.arpPatPitch[1]=0;v.arpPatOctave[0]=1;v.arpPatRatchet[0]=3;v.arpPatKind[2]=arp::StepRest;
 Synth r;r.init(44100);r.setTempo(120);r.setParams(v,{});r.noteOn(60,.8f);
 tick(r,1840);ck(r.arpSoundingNote()==79,"ratchet repeats semitone plus octave-shifted note");
 Synth rh;rh.init(44100);rh.setTempo(120);rh.setParams(v,{});rh.noteOn(60,.8f);rh.setTransport(0,true);
 tick(rh,1840);ck(rh.arpSoundingNote()==79&&rh.hostLocked(),"host ratchet repeats the shifted note");
 auto before=p.serialize();p.voice.arpPatPitch[0]=0;p.voice.arpPatPitch[3]=0;ck(p.serialize()==old&&before!=old,"RESET 0 restores byte-identical old state");
 puts(bad?"ARPPITCH71 FAILED":"ALL ARPPITCH71 TESTS PASSED");return bad?1:0;
}
