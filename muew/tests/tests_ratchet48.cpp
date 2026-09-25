#include "../src/preset.h"
#include "../src/synth.h"
#include <cstdio>
#include <cmath>
#include <vector>
using namespace muew;
static int bad=0;static void ck(bool a,const char*s){printf("%s %s\n",a?"ok:  ":"FAIL:",s);bad+=!a;}
static void tick(Synth& s){float x[2];s.renderStereo(x,1);}
int main(){
 Preset p, q;p.voice.arpOn=true;p.voice.arpPatOn=true;p.voice.arpPatLen=4;p.voice.arpPatRatchet[1]=3;
 auto text=p.serialize();ck(text.find("\narpr 1 3 1 1 ")!=std::string::npos&&text.find("\narpx ")!=std::string::npos,"append-only arpr line leaves arpx intact");
 ck(q.parse(text)&&q==p&&q.voice.arpPatRatchet[1]==3,"ratchet round-trips through preset");
 auto legacy=p;legacy.voice.arpPatRatchet[1]=1;auto old=legacy.serialize();
 ck(old.find("\narpr ")==std::string::npos,"all-one ratchets omit new line");
 Preset restored;ck(restored.parse(old)&&restored.voice.arpPatRatchet[1]==1,"old pattern defaults ratchet to one");
 Preset bounded;auto malformed=old+"arpr 0 99 2\n";
 ck(bounded.parse(malformed)&&bounded.voice.arpPatRatchet[0]==1&&bounded.voice.arpPatRatchet[1]==4&&bounded.voice.arpPatRatchet[2]==2&&bounded.voice.arpPatRatchet[3]==1,
    "ratchet counts clamp and truncated line retains defaults");
 VoiceParams v;v.arpOn=true;v.arpPatOn=true;v.arpPatLen=2;v.arpPatRatchet[0]=3;v.arpPatKind[1]=arp::StepRest;
 v.osc1Shape=0;v.osc2Level=0;v.ampA=.001;v.ampR=.005;v.arpGate=.5;
 Synth s;s.init(44100);s.setTempo(120);s.setParams(v,{});s.noteOn(60,.8f);
 std::vector<int> starts;int prior=-1;for(int t=0;t<11000;++t){tick(s);int note=s.arpSoundingNote();if(note==60&&prior!=60)starts.push_back(t);prior=note;}
 printf("free ratchet starts:");for(int t:starts)printf(" %d",t);puts("");
 ck(starts.size()==3&&starts[0]==0&&std::abs(starts[1]-1838)<=1&&std::abs(starts[2]-3675)<=1,"free clock retriggers three times inside one step, then REST");
 v.clockSync=true;v.arpPatKind[1]=arp::StepOn;v.arpSwing=.5;
 Synth h;h.init(44100);h.setTempo(120);h.setParams(v,{});h.noteOn(60,.8f);h.setTransport(0,true);
 starts.clear();prior=-1;for(int t=0;t<8400;++t){tick(h);int note=h.arpSoundingNote();if(note==60&&prior!=60)starts.push_back(t);prior=note;}
 printf("host ratchet starts:");for(int t:starts)printf(" %d",t);puts("");
 ck(starts.size()>=3&&starts[0]==0&&std::abs(starts[1]-2756)<=2&&std::abs(starts[2]-5513)<=2&&h.hostLocked(),
    "host grid with swing divides long step into three without moving grid boundary");
 v.arpPatKind[1]=arp::StepTie;v.arpPatRatchet[0]=4;
 Synth tied;tied.init(44100);tied.setParams(v,{});tied.noteOn(60,.8f);for(int i=0;i<8300;++i)tick(tied);
 ck(tied.arpSoundingNote()==60,"next TIE keeps previous note and suppresses ratchet");
 puts(bad?"RATCHET48 FAILED":"ALL RATCHET48 TESTS PASSED");return bad?1:0;
}
