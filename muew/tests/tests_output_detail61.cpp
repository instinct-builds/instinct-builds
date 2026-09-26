#include "../src/output_detail_display.h"
#include "../src/factory_bank.h"
#include "../src/au_params.h"
#include <cstdio>
#include <cmath>
using namespace muew;
static int bad=0;
static void ck(bool yes,const char* m){printf("%s %s\n",yes?"ok:":"FAIL:",m);bad+=!yes;}
int main(){
 OutputDetailDisplay d;
 d.update(.5f,.25f,0);
 ck(d.current[0]==.5f&&d.held[0]==.5f&&d.current[1]==.25f&&d.held[1]==.25f,"stereo block levels and holds are separate");
 ck(std::fabs(OutputDetailDisplay::dbfs(.5f)+6.020599913)<.0001&&std::fabs(OutputDetailDisplay::dbfs(1))<1e-9,"amplitude to dBFS reads correctly");
 ck(!std::isfinite(OutputDetailDisplay::dbfs(0))&&OutputDetailDisplay::dbfs(2)==0,"silence displays negative infinity and out-of-range caps at 0 dBFS");
 d.update(.1f,.7f,.1);
 ck(d.current[0]==.1f&&d.held[0]==.5f&&d.current[1]==.7f&&d.held[1]==.7f,"current changes while each channel holds its own peak");
 for(int i=0;i<8;++i)d.update(0,0,.1);
 ck(d.held[0]==.5f&&d.held[1]==.7f,"held peaks remain through the one-second window");
 for(int i=0;i<3;++i)d.update(0,0,.1);
 ck(d.held[0]==0&&d.held[1]==0,"held peaks clear after one second");
 d.update(NAN,INFINITY,NAN);ck(d.current[0]==0&&d.current[1]==0,"nonfinite integration input does not enter readout");
 d.update(.9f,.8f,0);d.clear();ck(d.held[0]==0&&d.held[1]==0,"clear resets both held peaks");
 bool bank=true;for(const auto& p:factoryPresets()) bank &= p.voice.noiseBurstSync==0;
 ck(bank&&factoryPresets().size()==108&&params::Count==40,"factory sounds and 40 AU IDs stable");
 printf("%s output detail61 tests\n",bad?"FAIL":"ALL PASSED");return bad?1:0;
}
