# Generates MUEW-icon-1024.png (then: base64 -w76 MUEW-icon-1024.png > MUEW-icon-1024.png.b64). Needs Pillow. The build uses the committed .b64, not this script.
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math
S=1024; SS=2
N=S*SS
def squircle_mask(n, inset, r):
    m=Image.new('L',(n,n),0); d=ImageDraw.Draw(m)
    d.rounded_rectangle([inset,inset,n-inset-1,n-inset-1],radius=r,fill=255); return m
inset=int(0.098*N); radius=int(0.225*N)
mask=squircle_mask(N,inset,radius)
# background vertical gradient
bg=Image.new('RGB',(N,N))
px=bg.load()
top=(0x18,0x20,0x2b); bot=(0x0a,0x0d,0x12)
for y in range(N):
    t=y/(N-1)
    c=tuple(int(top[i]*(1-t)+bot[i]*t) for i in range(3))
    for x in range(N): px[x,y]=c
# soft teal glow behind wave
glow=Image.new('RGB',(N,N),(0,0,0))
# wave path
def wave(x):
    u=(x-inset)/(N-2*inset)  # 0..1
    env=math.sin(math.pi*u)**0.8
    return env*(0.62*math.sin(2*math.pi*1.5*u+0.4)+0.38*math.sin(2*math.pi*3.5*u+1.1))
pts=[]
cy=N*0.5; amp=N*0.20
x0=inset+int(0.07*N); x1=N-inset-int(0.07*N)
for x in range(x0,x1+1,1):
    u=(x-x0)/(x1-x0)
    e=math.sin(math.pi*u)**0.7
    y=cy-amp*e*(0.75*math.sin(2*math.pi*1.5*u+0.35)+0.25*math.sin(2*math.pi*3.0*u+0.9))
    pts.append((x,y))
layer=Image.new('L',(N,N),0); d=ImageDraw.Draw(layer)
w=int(0.034*N)
for p in pts:
    d.ellipse([p[0]-w/2,p[1]-w/2,p[0]+w/2,p[1]+w/2],fill=255)
for p in (pts[0],pts[-1]):
    d.ellipse([p[0]-w//2,p[1]-w//2,p[0]+w//2,p[1]+w//2],fill=255)
g1=layer.filter(ImageFilter.GaussianBlur(N*0.030))
g2=layer.filter(ImageFilter.GaussianBlur(N*0.012))
teal=(0x5a,0xda,0xc8); lt=(0xa8,0xf5,0xe9); amber=(0xf2,0xab,0x55)
img=bg.copy()
img=Image.composite(Image.new('RGB',(N,N),teal),img,g1.point(lambda v:int(v*0.55)))
img=Image.composite(Image.new('RGB',(N,N),teal),img,g2.point(lambda v:int(v*0.8)))
# gradient on wave line: teal to light teal along x, amber accent dot at crest start
line_col=Image.new('RGB',(N,N),teal)
lp=line_col.load()
for x in range(N):
    t=min(max((x-x0)/(x1-x0),0),1)
    c=tuple(int(teal[i]*(1-t)+lt[i]*t) for i in range(3))
    for y in range(0,N,1): lp[x,y]=c
img=Image.composite(line_col,img,layer)
# amber playhead dot at the highest crest
best=min(pts,key=lambda p:p[1])
dd=ImageDraw.Draw(img)
rr=int(0.034*N)
halo=Image.new('L',(N,N),0); ImageDraw.Draw(halo).ellipse([best[0]-rr*2,best[1]-rr*2,best[0]+rr*2,best[1]+rr*2],fill=180)
halo=halo.filter(ImageFilter.GaussianBlur(rr*0.9))
img=Image.composite(Image.new('RGB',(N,N),amber),img,halo.point(lambda v:int(v*0.6)))
dd=ImageDraw.Draw(img); dd.ellipse([best[0]-rr,best[1]-rr,best[0]+rr,best[1]+rr],fill=amber)
# subtle inner border + top sheen
out=Image.new('RGBA',(N,N),(0,0,0,0)); out.paste(img,(0,0),mask)
border=Image.new('L',(N,N),0); bd=ImageDraw.Draw(border)
bd.rounded_rectangle([inset,inset,N-inset-1,N-inset-1],radius=radius,outline=255,width=int(0.004*N))
bc=Image.new('RGBA',(N,N),(255,255,255,26)); out=Image.composite(bc,out,border) if False else out
ov=Image.new('RGBA',(N,N),(255,255,255,0)); ov.putalpha(border.point(lambda v:int(v*0.10)))
out=Image.alpha_composite(out,ov)
out=out.resize((S,S),Image.LANCZOS)
out.save('MUEW-icon-1024.png', optimize=True)
