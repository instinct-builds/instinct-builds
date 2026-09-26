#include "../src/preset.h"
#include "../src/synth.h"
#include <cmath>
#include <cstdio>
#include <string>
using namespace muew;
static int bad=0;static void ck(bool yes,const char* s){printf("%s %s\n",yes?"ok:  ":"FAIL:",s);bad+=!yes;}
static void tick(Synth& s,int n){float x[2];for(int i=0;i<n;++i)s.renderStereo(x,1);}
static VoiceParams setup(){VoiceParams v;v.arpOn=true;v.arpPatOn=true;v.arpPatLen=2;v.arpPatKind[1]=arp::StepRest;v.arpGate=.5;v.osc1Shape=0;v.osc2Level=0;v.ampA=.001;v.ampR=.005;return v;}
static int gateEnd(VoiceParams v,bool host){Synth s;s.init(44100);s.setTempo(120);s.setParams(v,{});s.noteOn(60,.8f);if(host)s.setTransport(0,true);int first=-1;for(int i=0;i<6000;++i){tick(s,1);if(s.arpSoundingNote()<0){first=i;break;}}return first;}
int main(){
 Preset p;auto old=p.serialize();ck(old.find("\narpg ")==std::string::npos,"default preset omits step gates");
 p.voice.arpPatGate[0]=75;p.voice.arpPatGate[3]=100;auto text=p.serialize();Preset q;
 ck(text.find("\narpg 75 0 0 100 ")!=std::string::npos&&q.parse(text)&&q==p&&q.serialize()==text,
    "append-only arpg line survives state round-trip");
 Preset legacy;ck(legacy.parse(old)&&legacy.voice.arpPatGate[0]==0,"older state inherits global gate");
 Preset bound;ck(bound.parse(old+"arpg 1 900 -4 35\n")&&bound.voice.arpPatGate[0]==5&&bound.voice.arpPatGate[1]==100&&bound.voice.arpPatGate[2]==5&&bound.voice.arpPatGate[3]==35&&bound.voice.arpPatGate[4]==0,
    "short and out-of-range line clamps but keeps missing cells inherited");
 auto v=setup();int base=gateEnd(v,false),baseHost=gateEnd(v,true);
 ck(std::abs(base-2756)<=3&&std::abs(baseHost-2756)<=3,"legacy global gate in free and locked timing");
 v.arpPatGate[0]=75;int longer=gateEnd(v,false),longerHost=gateEnd(v,true);
 ck(std::abs(longer-4134)<=3&&std::abs(longerHost-4134)<=3,"75% ON step extends gate under both clocks");
 v.arpPatGate[0]=5;ck(gateEnd(v,false)<base/5&&gateEnd(v,true)<baseHost/5,"5% step shortens both clocks");
 v.arpPatGate[0]=100;ck(std::abs(gateEnd(v,false)-5513)<=3&&std::abs(gateEnd(v,true)-5513)<=3,"100% ON step holds until following REST boundary");
 v.arpPatGate[0]=75;v.arpPatKind[1]=arp::StepTie;
 Synth tied;tied.init(44100);tied.setParams(v,{});tied.noteOn(60,.8f);tick(tied,5513+4000);
 ck(tied.arpSoundingNote()==60,"TIE holds ON note into following step");
 tick(tied,300);ck(tied.arpSoundingNote()<0,"terminal TIE releases at originating ON's override");
 v.arpPatKind[1]=arp::StepRest;v.arpPatRatchet[0]=3;v.arpPatGate[0]=25;
 Synth rat;rat.init(44100);rat.setParams(v,{});rat.noteOn(60,.8f);
 tick(rat,500);bool gap1=rat.arpSoundingNote()<0;tick(rat,1400);bool strike2=rat.arpSoundingNote()==60;
 tick(rat,450);bool gap2=rat.arpSoundingNote()<0;ck(gap1&&strike2&&gap2,"three ratchets use overridden gate on each subhit");
 v.clockSync=true;Synth hr;hr.init(44100);hr.setParams(v,{});hr.noteOn(60,.8f);hr.setTransport(0,true);
 tick(hr,700);bool hgap1=hr.arpSoundingNote()<0;tick(hr,1300);bool hstrike2=hr.arpSoundingNote()==60;
 ck(hgap1&&hstrike2,"host-locked ratchets use the step override");
 v=setup();v.arpPatGate[1]=75;
 ck(gateEnd(v,false)==base,"REST gate value has no effect on the preceding ON step");
 puts(bad?"ARPGATE70 FAILED":"ALL ARPGATE70 TESTS PASSED");return bad?1:0;
}
