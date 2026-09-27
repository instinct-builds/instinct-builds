#include "../src/arp_pattern_actions.h"
#include "../src/preset.h"
#include <cstdio>
using namespace muew;
static int bad=0;static void ck(bool b,const char*s){printf("%s %s\n",b?"ok:":"FAIL:",s);bad+=!b;}
int main(){
 VoiceParams v;v.arpPatLen=4;
 for(int i=0;i<16;++i){v.arpPatKind[i]=i%3;v.arpPatVel[i]=60+i;v.arpPatRatchet[i]=i%4+1;v.arpPatOctave[i]=i%3-1;v.arpPatChance[i]=25*(i%4+1);v.arpPatGate[i]=i?20+i:0;v.arpPatPitch[i]=i-8;}
 auto original=arp::snapshot(v);arp::Actions a;
 ck(a.copiedSourceStep()==0&&a.undoDepth()==0,"empty clipboard has no source or undo");
 ck(a.copy(v,1)&&a.canPaste()&&a.copiedSourceStep()==2,"COPY captures REST with all hidden fields");
 ck(a.paste(v,2)&&arp::readStep(v,2)==original.steps[1]&&a.undoDepth()==1&&a.copiedSourceStep()==2,"PASTE replaces the seven-field tuple");
 ck(a.rotate(v,1)&&arp::readStep(v,0)==original.steps[3]&&arp::readStep(v,3)==original.steps[1],"rotate right wraps whole tuples");
 bool outside=true;auto shifted=arp::snapshot(v);for(int i=4;i<16;++i)outside&=shifted.steps[i]==original.steps[i];ck(outside,"rotate preserves cells outside LEN");
 ck(a.rotate(v,-1)&&arp::readStep(v,2)==original.steps[1],"rotate left reverses right rotation");
 ck(a.undo(v)&&arp::readStep(v,0)==original.steps[3],"first UNDO reverses latest action");
 ck(a.undo(v)&&arp::readStep(v,0)==original.steps[0],"second UNDO reverses first rotation");
 ck(a.undo(v)&&arp::snapshot(v).steps==original.steps&&a.undoDepth()==0,"third UNDO restores all fields before paste");
 ck(!a.undo(v)&&!a.paste(v,7)&&!a.copy(v,8),"empty history, out-of-LEN paste and copy do nothing");
 a.copy(v,2);ck(a.copiedSourceStep()==3,"second COPY updates source label");ck(a.paste(v,0)&&arp::readStep(v,0)==original.steps[2],"COPY of TIE carries stored data");
 a.clear();ck(!a.canPaste()&&a.copiedSourceStep()==0&&a.undoDepth()==0&&!a.paste(v,1)&&!a.undo(v),"preset switch clears clipboard and history");
 v.arpPatLen=1;ck(a.copy(v,0)&&a.copiedSourceStep()==1,"one-step pattern labels source step 1");
 a.clear();v.arpPatLen=16;ck(a.copy(v,15)&&a.copiedSourceStep()==16,"sixteen-step pattern labels source step 16");
 a.clear();
 Preset p,q;p.voice=v;auto text=p.serialize();ck(q.parse(text)&&q==p,"copy/rotate state remains in existing preset fields");
 puts(bad?"ARPACTIONS72 FAILED":"ALL ARPACTIONS72 TESTS PASSED");return bad?1:0;
}
