#include "../src/preset.h"
#include "../src/synth.h"
#include <cstdio>
#include <cmath>
#include <string>
using namespace muew;
static int bad=0;
static void ck(bool b,const char* msg){printf("%s %s\n",b?"ok:":"FAIL:",msg);bad+=!b;}
static void tick(Synth& s,int n){float x[2];for(int i=0;i<n;++i)s.renderStereo(x,1);}
int main(){
 Preset p,q;p.voice.arpOn=true;p.voice.arpPatOn=true;p.voice.arpPatLen=3;p.voice.arpPatOctave[0]=1;p.voice.arpPatOctave[2]=-1;p.voice.arpPatRatchet[0]=3;
 const auto text=p.serialize();ck(text.find("\narpo 1 0 -1 ")!=std::string::npos&&text.find("\narpr 3 1 1 ")!=std::string::npos&&text.find("\narpx ")!=std::string::npos,"append-only octave and ratchet lines");
 ck(q.parse(text)&&q==p,"octave preset round-trip");
 p.voice.arpPatOctave[0]=0;p.voice.arpPatOctave[2]=0;const auto old=p.serialize();ck(old.find("\narpo ")==std::string::npos,"zero octave leaves old serialization unchanged");
 Preset legacy;ck(legacy.parse(old)&&legacy.voice.arpPatOctave[0]==0&&legacy.voice.arpPatOctave[2]==0,"old pattern loads neutral octave");
 Preset bounded;ck(bounded.parse(old+"arpo 88 -19 1\n")&&bounded.voice.arpPatOctave[0]==1&&bounded.voice.arpPatOctave[1]==-1&&bounded.voice.arpPatOctave[2]==1&&bounded.voice.arpPatOctave[3]==0,"clamps shifts and preserves defaults on short line");
 VoiceParams v;v.arpOn=true;v.arpPatOn=true;v.arpPatLen=4;v.arpPatOctave[0]=1;v.arpPatOctave[1]=-1;v.arpPatOctave[2]=1;v.arpPatKind[2]=arp::StepTie;v.arpPatKind[3]=arp::StepRest;v.arpGate=1;v.arpPatRatchet[1]=3;
 Synth s;s.init(44100);s.setTempo(120);s.setParams(v,{});s.noteOn(60,.8f);
 ck((tick(s,1),s.arpSoundingNote()==72),"ON first step shifts selected pitch up");
 tick(s,5513);ck(s.arpSoundingNote()==48,"next ON shifts selected pitch down");
 tick(s,5513);ck(s.arpSoundingNote()==48,"TIE ignores its own shift and holds prior note");
 tick(s,5513);ck(s.arpSoundingNote()==-1,"REST remains silent");
 Synth h;v.clockSync=true;v.arpSwing=.5;h.init(44100);h.setTempo(120);h.setParams(v,{});h.noteOn(60,.8f);h.setTransport(0,true);tick(h,1);ck(h.arpSoundingNote()==72&&h.hostLocked(),"host grid selects shifted note");
 tick(h,8269);ck(h.arpSoundingNote()==48,"host swing boundary selects next shifted note");
 VoiceParams rapid=v;rapid.clockSync=false;rapid.arpSwing=0;rapid.arpPatLen=2;rapid.arpPatKind[0]=arp::StepOn;rapid.arpPatKind[1]=arp::StepRest;
 rapid.arpPatOctave[0]=1;rapid.arpPatRatchet[0]=3;rapid.arpGate=.4;
 Synth r;r.init(44100);r.setTempo(120);r.setParams(rapid,{});r.noteOn(60,.8f);
 int count=0,prev=-1;bool onlyShifted=true;
 for(int i=0;i<5513;++i){tick(r,1);int n=r.arpSoundingNote();if(n>=0&&prev<0)++count;if(n>=0&&n!=72)onlyShifted=false;prev=n;}
 ck(count==3&&onlyShifted,"all three gated retriggers keep the shifted pitch");
 VoiceParams edge=v;edge.clockSync=false;edge.arpPatLen=1;edge.arpPatOctave[0]=1;Synth hi;hi.init(44100);hi.setParams(edge,{});hi.noteOn(120,.8f);tick(hi,1);ck(hi.arpSoundingNote()==127,"upper MIDI edge clamps");
 edge.arpPatOctave[0]=-1;Synth lo;lo.init(44100);lo.setParams(edge,{});lo.noteOn(5,.8f);tick(lo,1);ck(lo.arpSoundingNote()==0,"lower MIDI edge clamps");
 puts(bad?"OCTAVE49 FAILED":"ALL OCTAVE49 TESTS PASSED");return bad?1:0;
}
