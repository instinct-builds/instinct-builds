#include "../src/route_meter_hold.h"
#include <cstdio>
#include <cmath>
using namespace muew;
static int fail=0;
static void ck(bool b,const char* m){printf("%s %s\n",b?"ok:":"FAIL:",m);fail+=!b;}
int main(){
 RouteMeterHold m;float vals[kMaxRoutes]{};vals[0]=.82f;vals[1]=-.6f;
 m.update(vals,kMaxRoutes,0);ck(m.value[0]==.82f&&m.value[1]==-.6f,"signed hits captured immediately");
 vals[0]=.1f;vals[1]=0;for(int i=0;i<4;++i)m.update(vals,kMaxRoutes,.04);
 ck(m.value[0]==.82f&&m.value[1]==-.6f,"short hits held through 160ms");
 m.update(vals,kMaxRoutes,.04);ck(m.value[0]<.82f&&m.value[0]>.7f&&m.value[1]<0,"both polarities start to decay after 180ms");
 for(int i=0;i<25;++i)m.update(vals,kMaxRoutes,.04);
 ck(m.value[0]>.09f&&m.value[0]<.2f&&m.value[1]<0,"weak live reading eventually replaces fading peak");
 vals[0]=-.95f;m.update(vals,kMaxRoutes,.03);ck(m.value[0]==-.95f,"stronger opposite polarity replaces hold immediately");
 m.clear();ck(m.value[0]==0&&m.value[1]==0,"route/state change clears old markers");
 vals[0]=.5f;m.update(vals,kMaxRoutes,.03);for(int i=0;i<20;++i)m.update(vals,kMaxRoutes,.03);
 ck(m.value[0]<=.505f&&m.value[0]>=.495f,"constant macro does not retrigger the hold age every poll");
 m.clear(); vals[0]=NAN;vals[1]=INFINITY;m.update(vals,kMaxRoutes,.04);ck(m.value[0]==0&&m.value[1]==0,"nonfinite integration values are ignored");
 vals[0]=.5f;m.update(vals,kMaxRoutes,.04);float prev=m.value[0];m.update(nullptr,0,1e9);
 ck(m.value[0]==prev,"long UI stall caps age and preserves the first hold window");
 m.update(nullptr,0,1e9);ck(m.value[0]<prev&&m.value[0]>.3f,"subsequent UI poll decays smoothly instead of erasing peak");
 printf("%s route meter hold56 tests\n",fail?"FAIL":"ALL PASSED");return fail?1:0;
}
