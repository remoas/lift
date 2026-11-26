def L(h):
    h=h.lstrip('#');c=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    c=[x/12.92 if x<=0.04045 else ((x+0.055)/1.055)**2.4 for x in c]
    return 0.2126*c[0]+0.7152*c[1]+0.0722*c[2]
def cr(a,b):
    x,y=sorted([L(a),L(b)],reverse=True);return (x+0.05)/(y+0.05)
light=dict(bg='#FFFFFF',sunken='#F4F3F1',raised='#FFFFFF',accentSoft='#FCEDE5')
dark=dict(bg='#0B0B0C',sunken='#161618',raised='#1E1E21',accentSoft='#3A1E0E')
lt=dict(textPrimary='#141413',textSecondary='#5E5B57',textTertiary='#6F6C67',accent='#C2410C',success='#15803D',danger='#B91C1C',controlStroke='#8C8984')
dt=dict(textPrimary='#F5F4F1',textSecondary='#A6A39E',textTertiary='#8E8B86',accent='#FF8A3D',success='#4ADE80',danger='#F87171',controlStroke='#6E6B67')
for name,surf,tx in (('light',light,lt),('dark',dark,dt)):
    for t,c in tx.items():
        print(name,t,c,' '.join(f"{s}:{cr(c,sv):.2f}" for s,sv in surf.items()))
print('onAccent light',cr('#FFFFFF','#C2410C'),'dark',cr('#1A0B02','#FF8A3D'))
print('accentPressed',cr('#FFFFFF','#9A3412'))
