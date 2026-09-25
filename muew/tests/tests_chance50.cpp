#include "../src/preset.h"
#include "../src/synth.h"
#include <cstdio>
#include <vector>
#include <string>
using namespace muew;
static int bad=0;
static void ck(bool ok,const char* msg){printf("%s %s\n",ok?"ok:":"FAIL:",msg);bad+=!ok;}
static void tick(Synth& s,int n){float x[2];for(int i=0;i<n;++i)s.renderStereo(x,1);}
static std::vector<int> cycle(VoiceParams v,bool host,double start=0){
 Synth s;s.init(44100);s.setTempo(120);s.setParams(v,{});s.noteOn(60,.8f);
 if(host)s.setTransport(start,true);
 std::vector<int> result;
 for(int i=0;i<32;++i){
  if(host){s.setTransport(start+i*.25,true);tick(s,1);}else tick(s,i?5513:1);
  result.push_back(s.arpSoundingNote());
 }
 return result;
}
int main(){
 Preset p,q;p.voice.arpOn=true;p.voice.arpPatOn=true;p.voice.arpPatLen=4;p.voice.arpPatChance[0]=75;p.voice.arpPatChance[1]=50;p.voice.arpPatChance[2]=25;p.voice.arpChanceLive=true;
 auto t=p.serialize();ck(t.find("\narpc 1 75 50 25 100 ")!=std::string::npos&&t.find("\narpx ")!=std::string::npos,"chance serializes as optional append-only line");
 ck(q.parse(t)&&q==p,"chance and LIVE round-trip");
 p.voice.arpChanceLive=false;for(int& x:p.voice.arpPatChance)x=100;
 auto old=p.serialize();ck(old.find("\narpc ")==std::string::npos,"old all-100 pattern remains byte-identical");
 Preset legacy;ck(legacy.parse(old)&&legacy.voice.arpPatChance[0]==100&&!legacy.voice.arpChanceLive,"old pattern loads full chance and fixed mode");
 Preset bounded;ck(bounded.parse(old+"arpc 1 -8 48 74 99 120\n")&&bounded.voice.arpChanceLive&&bounded.voice.arpPatChance[0]==25&&bounded.voice.arpPatChance[1]==25&&bounded.voice.arpPatChance[2]==50&&bounded.voice.arpPatChance[3]==75&&bounded.voice.arpPatChance[4]==100&&bounded.voice.arpPatChance[5]==100,"malformed chance clamps to four UI choices and short line preserves defaults");
 VoiceParams v;v.arpOn=true;v.arpPatOn=true;v.arpPatLen=4;v.arpGate=1;v.arpPatChance[0]=50;v.arpPatChance[1]=75;v.arpPatChance[2]=25;
 auto a=cycle(v,false),b=cycle(v,false);ck(a==b,"fixed free pattern repeats on restart");
 auto h=cycle(v,true),rewind=cycle(v,true);ck(h==rewind,"fixed host pattern repeats on rewind");
 auto seek=cycle(v,true,4);bool same=true;for(int i=0;i<16;++i)same &= seek[i]==h[i+16];ck(same,"host seek computes same per-cycle result as uninterrupted playback");
 v.clockSync=true;v.arpPatLen=2;v.arpPatChance[0]=25;v.arpPatChance[1]=100;v.arpPatKind[1]=arp::StepTie;v.arpPatRatchet[0]=4;v.arpPatOctave[0]=1;
 auto paired=cycle(v,true);bool skipTie=false,hitTie=false;
 for(int i=0;i<32;i+=2){if(paired[i]<0&&paired[i+1]<0)skipTie=true;if(paired[i]==72&&paired[i+1]==72)hitTie=true;}
 ck(skipTie&&hitTie,"skipped ON leaves following TIE silent; played ON holds shifted pitch through TIE");
 v.arpPatKind[1]=arp::StepRest;auto rest=cycle(v,true);bool rests=true;for(int i=1;i<32;i+=2)rests &= rest[i]<0;ck(rests,"REST stays silent after played or skipped chance step");
 v.arpChanceLive=true;auto live=cycle(v,false);auto live2=cycle(v,false);ck(live==live2,"LIVE starts from a stable initial seed for reproducible sessions");
 // Same cell's successive passes consume the LIVE stream and vary over time.
 bool varied=false;for(int i=4;i<32;i+=4) varied |= live[i]!=live[0];ck(varied,"LIVE varies the same step across repeated cycles");
 puts(bad?"CHANCE50 FAILED":"ALL CHANCE50 TESTS PASSED");return bad?1:0;
}
