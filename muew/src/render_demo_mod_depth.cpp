#include "synth.h"
#include "wav_writer.h"
#include <vector>
using namespace muew;
static void phrase(Synth& s,std::vector<float>& pcm){const int ns[]={40,40,47,52,43,50,55,47};for(int n:ns){s.noteOn(n,.92f);std::vector<float>b(13230*2);s.renderStereo(b.data(),13230);pcm.insert(pcm.end(),b.begin(),b.end());s.noteOff(n);std::vector<float>t(2205*2);s.renderStereo(t.data(),2205);pcm.insert(pcm.end(),t.begin(),t.end());}}
int main(){Synth s;s.init(44100);VoiceParams p;p.osc1Shape=2;p.osc2Shape=3;p.osc2Level=.3;p.osc2Detune=12.02;p.osc1WarpMode=(int)Oscillator::WarpMode::Sync;p.osc2WarpMode=(int)Oscillator::WarpMode::Fold;p.mseg1Seconds=.6;p.mseg1Loop=true;p.filterCutoff=700;p.filterReso=2.8;p.ampA=.005;p.ampD=.1;p.ampS=.72;p.ampR=.14;s.setParams(p,{{ModRoute::Source::MSEG1,ModRoute::Dest::Osc1Warp,.9},{ModRoute::Source::LFO2,ModRoute::Dest::Osc2Warp,.35},{ModRoute::Source::MSEG1,ModRoute::Dest::FilterCutoff,3.2},{ModRoute::Source::LFO1,ModRoute::Dest::FilterResonance,.5}});FXParams fx;fx.chorus={true,.35,4,12,.2};fx.delay={true,.21,.32,.22,.17};fx.reverb={true,.48,.55,.16};s.setFX(fx);std::vector<float>pcm;phrase(s,pcm);writeWav("out/MUEW-warp-MSEG-demo.wav",pcm,44100,2);}
