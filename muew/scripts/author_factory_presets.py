#!/usr/bin/env python3
"""Authoring source for the MUEW factory bank. Writes presets/*.muew and
presets/bank.txt; run scripts/embed_factory_bank.py afterwards. Run from muew/."""
import os
def g(x): return '%g' % x
DEFPTS=[(0,0),(0.15,1),(0.55,-0.3),(1,0)]
FXOFF=dict(chorus=(0,0.6,6,15,0.35),delay=(0,0.28,0.42,0.35,0.22),reverb=(0,0.55,0.45,0.28))
def write(slug,name,cat,tags,o1,o2,det,lvl,cut,res,fm,amp,mod,l1r,l1s,routes,chorus,delay,reverb,
          l2=(0.35,1),w1=(0,0),w2=(0,0),mseg=(1,0,DEFPTS)):
    L=["muew-preset 2","name "+name,"category "+cat,"author MUEW Factory","tags "+" ".join(tags),
       "osc1Shape %d"%o1,"osc2Shape %d"%o2,"osc2Detune "+g(det),"osc2Level "+g(lvl),
       "filterCutoff "+g(cut),"filterReso "+g(res),"filterMode %d"%fm,
       "amp "+" ".join(map(g,amp)),"mod "+" ".join(map(g,mod)),"lfo1Rate "+g(l1r),"lfo1Shape %d"%l1s,
       "lfo2 %s %d"%(g(l2[0]),l2[1]),"warp1 %d %s"%(w1[0],g(w1[1])),"warp2 %d %s"%(w2[0],g(w2[1])),
       "mseg %s %d %d"%(g(mseg[0]),mseg[1],len(mseg[2]))+"".join(" %s %s"%(g(t),g(v)) for t,v in mseg[2]),
       "routes %d"%len(routes)]
    L+=["route %d %d %s"%(s,d,g(a)) for s,d,a in routes]
    L.append("chorus %d "%chorus[0]+" ".join(map(g,chorus[1:])))
    L.append("delay %d "%delay[0]+" ".join(map(g,delay[1:])))
    L.append("reverb %d "%reverb[0]+" ".join(map(g,reverb[1:])))
    open("presets/%s.muew"%slug,"w").write("\n".join(L)+"\n")
    return slug
# sources: 0 LFO1 1 ModEnv 2 Vel 3 LFO2 4 MSEG1 ; dests: 0 O1Pitch 1 O2Pitch 2 Cutoff 3 O2Level 4 Reso 5 O1Warp 6 O2Warp
# shapes: 0 sine 1 tri 2 saw 3 square 4 pulse25 ; warp: 1 sync 2 bend+ 3 bend- 4 pwm 5 quantize 6 fold
C,D,R=FXOFF['chorus'],FXOFF['delay'],FXOFF['reverb']
order=[]
# ---- legacy eight, same sound, now with metadata (AU numbers 0-7 unchanged)
order.append(write("airy-strings","Airy Strings","Pad",["strings","wide","slow"],2,2,0.12,0.55,4200,0.35,0,(1.8,1,0.8,2.2),(1.5,1,0.4,1.5),0.15,1,[(1,2,1),(0,3,0.15)],(1,0.35,7,14,0.32),D,(1,0.85,0.35,0.4)))
order.append(write("bright-lead","Bright Lead","Lead",["bright","mono-style","vibrato"],2,3,7,0.45,6000,0.8,0,(0.01,0.1,0.9,0.15),(0.01,0.25,0,0.1),5.5,0,[(1,2,2),(0,0,0.15),(2,2,1)],(0,0.6,6,15,0.35),(1,0.28,0.34,0.35,0.25),(1,0.4,0.5,0.2)))
order.append(write("init-saw","Init Saw","Lead",["init","basic"],2,3,7,0.5,8000,0.7,0,(0.005,0.15,0.8,0.3),(0.01,0.3,0,0.2),5,0,[(1,2,2),(0,1,0.05),(2,2,1)],C,D,R))
order.append(write("pluck","Pluck","Pluck",["short","bright"],2,4,0,0.4,5200,0.6,0,(0.001,0.35,0,0.12),(0.001,0.2,0,0.1),5,0,[(1,2,2.5),(2,2,0.6)],C,(1,0.22,0.28,0.3,0.18),(1,0.35,0.5,0.15)))
order.append(write("punchy-bass","Punchy Bass","Bass",["punchy","dry"],3,2,-12,0.6,900,0.9,0,(0.002,0.25,0.4,0.08),(0.005,0.15,0,0.05),2,0,[(1,2,1.2),(2,2,0.8)],C,D,R))
order.append(write("soft-keys","Soft Keys","Keys",["soft","mellow"],1,0,0.02,0.5,3500,0.3,0,(0.01,0.6,0.5,0.4),(0.01,0.3,0,0.2),4,0,[(2,2,0.8)],(1,0.4,3,10,0.18),D,(1,0.5,0.5,0.22)))
order.append(write("sub-bass","Sub Bass","Bass",["sub","clean","dry"],0,0,-12,0.4,400,0.2,0,(0.005,0.1,1,0.1),(0.01,0.3,0,0.2),5,0,[],C,D,R))
order.append(write("warm-pad","Warm Pad","Pad",["warm","wide","slow"],2,2,0.08,0.5,2400,0.4,0,(1.2,1.5,0.7,1.6),(0.8,1.2,0.3,1),0.2,0,[(1,2,1.5),(0,3,0.1)],(1,0.5,5,12,0.3),D,(1,0.75,0.4,0.35)))
# ---- new 0.3.0 bank
order.append(write("fold-growl","Fold Growl","Bass",["growl","fold","aggressive"],3,2,-12,0.45,1400,1.6,0,(0.003,0.3,0.7,0.12),(0.005,0.4,0.2,0.1),3,0,[(4,5,0.55),(1,2,1.4)],C,D,R,w1=(6,0.25),mseg=(0.5,1,[(0,0),(0.25,1),(0.5,0.1),(0.75,0.8),(1,0)])))
order.append(write("reese-drift","Reese Drift","Bass",["reese","detuned","dark"],2,2,0.15,0.9,700,1.2,0,(0.01,0.2,0.9,0.2),(0.01,0.3,0,0.2),0.3,1,[(3,2,1.2),(0,6,0.2)],C,D,R,l2=(0.12,0),w2=(3,0.3)))
order.append(write("sync-bite","Sync Bite","Bass",["sync","plucky","mid"],2,4,-12,0.35,1800,1.1,0,(0.001,0.28,0.5,0.1),(0.001,0.22,0,0.1),4,0,[(1,5,0.8),(1,2,1.8),(2,2,0.5)],C,D,R,w1=(1,0.1)))
order.append(write("rubber-sub","Rubber Sub","Bass",["sub","round","bend"],0,1,-12,0.3,650,0.5,0,(0.002,0.18,0.85,0.1),(0.001,0.12,0,0.05),5,0,[(1,5,0.6),(1,2,0.8)],C,D,R,w1=(2,0.1)))
order.append(write("glass-sync-lead","Glass Sync Lead","Lead",["sync","vibrato","bright"],2,0,12,0.3,7000,0.9,0,(0.01,0.2,0.85,0.25),(0.05,0.8,0.3,0.3),5.2,0,[(1,5,0.5),(0,0,0.12),(0,1,0.12)],C,(1,0.33,0.25,0.3,0.2),(1,0.45,0.45,0.18),w1=(1,0.35)))
order.append(write("hollow-fifths","Hollow Fifths","Lead",["fifths","hollow","bandpass"],3,3,7,0.6,1500,1.8,1,(0.02,0.3,0.8,0.3),(0.02,0.5,0.2,0.3),4.5,0,[(1,2,1.5),(0,0,0.1)],C,(1,0.36,0.48,0.4,0.25),(1,0.5,0.4,0.2)))
order.append(write("acid-squelch","Acid Squelch","Lead",["acid","resonant","squelch"],2,3,0,0.2,500,6,0,(0.002,0.2,0.6,0.08),(0.001,0.25,0,0.1),5,0,[(1,2,3.5),(2,2,0.8)],C,(1,0.24,0.36,0.3,0.15),R))
order.append(write("pwm-solo","PWM Solo","Lead",["pwm","vintage","warm"],3,3,0.1,0.5,3200,0.8,0,(0.02,0.2,0.85,0.25),(0.02,0.4,0.3,0.2),5,0,[(3,5,0.35),(3,6,-0.35),(1,2,1)],(1,0.5,4,12,0.25),D,(1,0.45,0.5,0.18),l2=(0.9,1),w1=(4,0.4),w2=(4,0.6)))
order.append(write("night-bloom","Night Bloom","Pad",["evolving","mseg","dark"],2,1,0.07,0.55,1800,0.6,0,(1.4,1.5,0.8,2.2),(1,1,0.5,1.5),0.2,0,[(4,5,0.5),(4,2,1.3),(0,3,0.12)],(1,0.3,6,14,0.3),(1,0.45,0.6,0.35,0.2),(1,0.88,0.35,0.42),w1=(3,0.2),mseg=(4,1,[(0,0),(0.3,1),(0.6,0.2),(0.85,0.7),(1,0)])))
order.append(write("vector-choir","Vector Choir","Pad",["choir","vocal","wide"],1,2,0.05,0.4,1100,0.9,1,(0.9,1,0.85,1.8),(0.8,1,0.5,1),0.25,1,[(3,5,0.3),(0,2,0.4)],(1,0.4,8,16,0.4),D,(1,0.8,0.4,0.38),l2=(0.18,0),w1=(3,0.45)))
order.append(write("frozen-lake","Frozen Lake","Pad",["airy","glassy","cold"],0,1,12.03,0.35,6500,0.4,0,(1.3,1,0.9,3),(1,1,0.5,1),0.1,0,[(3,6,0.4),(3,2,0.4)],(1,0.25,5,12,0.3),(1,0.5,0.66,0.45,0.25),(1,0.93,0.3,0.45),l2=(0.07,0),w2=(6,0.3)))
order.append(write("tidal-wash","Tidal Wash","Pad",["sweep","slow","wide"],2,3,-0.1,0.45,1200,1.1,0,(1.6,1.5,0.85,2.5),(1,1,0.5,1),0.2,0,[(3,2,2),(0,3,0.15)],(1,0.3,6,14,0.3),(1,0.55,0.7,0.4,0.25),(1,0.82,0.45,0.38),l2=(0.06,1)))
order.append(write("prism-keys","Prism Keys","Keys",["digital","quantized","bright"],2,1,12,0.35,4500,0.6,0,(0.005,0.7,0.35,0.5),(0.005,0.6,0,0.3),5,0,[(1,5,-0.4),(2,2,1)],(1,0.35,3,10,0.2),(1,0.3,0.45,0.25,0.15),(1,0.5,0.5,0.22),w1=(5,0.55)))
order.append(write("velvet-ep","Velvet EP","Keys",["electric-piano","soft","velocity"],0,1,0,0.35,2800,0.4,0,(0.003,1.2,0.3,0.6),(0.003,0.8,0,0.4),4.5,0,[(2,2,1.5),(1,6,0.4)],(1,0.8,2.5,8,0.25),D,(1,0.45,0.55,0.18),w2=(6,0.1)))
order.append(write("bell-tines","Bell Tines","Keys",["bell","metallic","bright"],0,0,19.02,0.45,8000,0.4,0,(0.001,1.8,0,1.4),(0.001,1.2,0,1),5,0,[(1,5,0.6),(1,6,0.3)],C,(1,0.37,0.5,0.3,0.2),(1,0.7,0.35,0.3),w1=(6,0.15),w2=(1,0.2)))
order.append(write("fold-pluck","Fold Pluck","Pluck",["fold","short","percussive"],1,0,12,0.3,4000,0.8,0,(0.001,0.3,0,0.2),(0.001,0.18,0,0.1),5,0,[(1,5,0.9),(1,2,1.5)],C,(1,0.25,0.37,0.3,0.2),(1,0.4,0.5,0.15),w1=(6,0)))
order.append(write("marimba-wood","Marimba Wood","Pluck",["mallet","wooden","short"],1,0,12,0.25,1400,1.6,0,(0.001,0.4,0,0.25),(0.001,0.1,0,0.1),5,0,[(1,2,1.2),(2,2,0.5)],C,D,(1,0.35,0.6,0.15)))
order.append(write("echo-pluck","Echo Pluck","Pluck",["delay","rhythmic","bright"],2,3,0.05,0.4,3800,0.7,0,(0.001,0.25,0,0.2),(0.001,0.2,0,0.1),5,0,[(1,2,2.2),(2,2,0.7)],(1,0.5,4,12,0.2),(1,0.375,0.25,0.5,0.35),(1,0.55,0.45,0.2)))
order.append(write("bent-circuit","Bent Circuit","Texture",["glitch","stepped","mseg"],3,2,-5,0.45,2400,1.5,0,(0.005,0.3,0.85,0.4),(0.01,0.3,0,0.2),5,0,[(4,5,0.7),(4,2,1.2),(3,6,0.3)],C,(1,0.18,0.27,0.45,0.3),(1,0.55,0.4,0.25),l2=(1.3,2),w1=(5,0.2),w2=(1,0.2),mseg=(0.75,1,[(0,-1),(0.2,-1),(0.21,0.6),(0.45,0.6),(0.46,-0.2),(0.7,-0.2),(0.71,1),(1,1)])))
order.append(write("chrome-motion","Chrome Motion","Texture",["rhythmic","gated","motion"],2,4,7,0.5,2000,1.3,0,(0.01,0.3,0.9,0.5),(0.01,0.3,0,0.2),5,0,[(4,3,0.5),(4,2,1.6),(0,5,0.1)],(1,0.4,5,12,0.3),(1,0.3,0.45,0.35,0.25),(1,0.6,0.4,0.25),w1=(3,0.3),mseg=(0.5,1,[(0,1),(0.12,-0.6),(0.25,1),(0.37,-0.6),(0.5,0.6),(0.62,-0.6),(0.75,1),(1,-0.6)])))
order.append(write("rising-tide","Rising Tide","FX",["riser","sweep","long"],2,2,0.2,0.6,300,2,0,(0.5,1,1,2),(0.01,0.3,0,0.2),0.5,0,[(4,2,4.5),(4,0,12),(4,1,12),(0,3,0.2)],(1,0.8,6,14,0.35),(1,0.4,0.55,0.4,0.25),(1,0.85,0.35,0.4),mseg=(6,0,[(0,0),(0.9,1),(1,1)])))
order.append(write("laser-drop","Laser Drop","FX",["drop","zap","pitch"],2,3,0,0.4,5000,2.5,0,(0.001,0.6,0,0.3),(0.001,0.4,0,0.2),5,0,[(4,0,24),(4,1,24),(4,2,1.5)],C,(1,0.2,0.3,0.4,0.25),(1,0.5,0.5,0.2),mseg=(0.4,0,[(0,1),(0.3,0.1),(1,-1)])))
open("presets/bank.txt","w").write("# MUEW factory bank order. Index = AU factory preset number.\n# Append only: reordering changes preset numbers saved in host projects.\n"+"\n".join(order)+"\n")
print(len(order))
