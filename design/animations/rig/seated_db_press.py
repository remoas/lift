"""Lift movement-loop rig v0: procedural faceless mannequin + seated dumbbell overhead press.
Run: blender -b -P seated_db_press.py -- <theme light|dark> <outdir> [frame_start frame_end] [samples]
Renders RGBA PNGs with a shadow catcher; compose onto the theme background with ffmpeg."""
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix, Quaternion

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
THEME = argv[0] if argv else 'light'
OUT = argv[1] if len(argv) > 1 else '/tmp/lift_frames'
F0 = int(argv[2]) if len(argv) > 2 else 1
F1 = int(argv[3]) if len(argv) > 3 else 96
SAMPLES = int(argv[4]) if len(argv) > 4 else 48

def srgb(h):
    h = h.lstrip('#'); c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c) + (1,)

PAL = {  # albedo per theme; tuned so the lit figure reads ~#BDB8B0 on #F4F3F1 (light) and ~#7D7A75 on #161618 (dark)
 'light': dict(body='#C9C4BC', prop='#4A4844', bench='#E2DFDA', ember='#C2410C', world=0.35, key=140),
 'dark':  dict(body='#8A8680', prop='#B5B1AA', bench='#38373A', ember='#FF8A3D', world=0.12, key=120),
}[THEME]

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

def mat(name, hexc, rough=0.62, emit=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = srgb(hexc); b.inputs['Roughness'].default_value = rough
    b.inputs['Specular IOR Level'].default_value = 0.25
    if emit:
        b.inputs['Emission Color'].default_value = srgb(hexc); b.inputs['Emission Strength'].default_value = emit
    return m
M_BODY = mat('body', PAL['body']); M_PROP = mat('prop', PAL['prop'], 0.45); M_BENCH = mat('bench', PAL['bench'], 0.8)
M_EMBER = mat('ember', PAL['ember'], 0.55)

# ---------- skeleton (rest pose = bottom of the press) ----------
S = 1.0
J = dict(
 pelvis=(0.00, 0, 0.56), chest=(-0.035, 0, 1.03), neck=(-0.03, 0, 1.08), head=(-0.01, 0, 1.30),
)
for s, y in (('L', 1), ('R', -1)):
    J['shoulder' + s] = (-0.04, 0.185 * y, 1.02)
    J['elbow' + s] = (0.05, 0.405 * y, 0.84)
    J['grip' + s] = (0.05, 0.405 * y, 1.14)
    J['hip' + s] = (0.02, 0.10 * y, 0.555)
    J['knee' + s] = (0.47, 0.13 * y, 0.525)
    J['ankle' + s] = (0.50, 0.15 * y, 0.09)
    J['toe' + s] = (0.66, 0.165 * y, 0.03)
V = {k: Vector(v) for k, v in J.items()}

arm_data = bpy.data.armatures.new('rig'); rig = bpy.data.objects.new('rig', arm_data)
sc.collection.objects.link(rig); bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
eb = arm_data.edit_bones
def bone(name, h, t, parent=None, connect=False):
    b = eb.new(name); b.head = V[h] if isinstance(h, str) else Vector(h); b.tail = V[t] if isinstance(t, str) else Vector(t)
    if parent: b.parent = eb[parent]; b.use_connect = connect
    return b
bone('pelvis', 'pelvis', (0, 0, 0.66))
bone('spine', (0, 0, 0.66), 'chest', 'pelvis', True)
bone('neck', 'chest', 'neck', 'spine', True)
bone('head', 'neck', 'head', 'neck', True)
for s in 'LR':
    bone('clav' + s, 'chest', 'shoulder' + s, 'spine')
    bone('upper' + s, 'shoulder' + s, 'elbow' + s, 'clav' + s, True)
    bone('fore' + s, 'elbow' + s, 'grip' + s, 'upper' + s, True)
    bone('thigh' + s, 'hip' + s, 'knee' + s, 'pelvis')
    bone('shin' + s, 'knee' + s, 'ankle' + s, 'thigh' + s, True)
    bone('foot' + s, 'ankle' + s, 'toe' + s, 'shin' + s, True)
bpy.ops.object.mode_set(mode='OBJECT')

# ---------- body parts: smooth ellipsoids rigidly bound to one bone each ----------
parts = []
def ellipsoid(name, center, radii, bone_name, material=M_BODY, axis_to=None, seg=48, rings=32):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me); sc.collection.objects.link(ob)
    rot = Matrix.Identity(4)
    if axis_to is not None:
        rot = Vector((0, 0, 1)).rotation_difference(axis_to.normalized()).to_matrix().to_4x4()
    me.transform(Matrix.Translation(Vector(center)) @ rot @ Matrix.Diagonal(Vector(radii)).to_4x4())
    for p in me.polygons: p.use_smooth = True
    me.materials.append(material)
    vg = ob.vertex_groups.new(name=bone_name); vg.add(range(len(me.vertices)), 1.0, 'REPLACE')
    md = ob.modifiers.new('arm', 'ARMATURE'); md.object = rig
    parts.append(ob); return ob
def limb(name, a, b, r0, r1, bone_name, material=M_BODY):
    pa, pb = V[a] if isinstance(a, str) else Vector(a), V[b] if isinstance(b, str) else Vector(b)
    d = pb - pa; L = d.length
    # tapered capsule: build as ellipsoid then taper by moving verts
    ob = ellipsoid(name, (pa + pb) / 2, (1, 1, 1), bone_name, material)
    me = ob.data; rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
    c = (pa + pb) / 2
    for v in me.vertices:
        loc = v.co - c  # unit sphere around c
        z = loc.z; t = (z + 1) / 2; r = r0 + (r1 - r0) * t
        v.co = c + rot @ Vector((loc.x * r, loc.y * r, z * (L / 2 + (r0 + r1) / 4)))
    return ob

ellipsoid('pelvisM', (0.0, 0, 0.62), (0.115, 0.155, 0.10), 'pelvis')
ellipsoid('waist', (-0.015, 0, 0.75), (0.095, 0.13, 0.11), 'spine')
ellipsoid('chestM', (-0.035, 0, 0.91), (0.115, 0.175, 0.15), 'spine')
limb('neckM', 'chest', (-0.025, 0, 1.13), 0.042, 0.04, 'neck')
ellipsoid('headM', (-0.01, 0, 1.215), (0.092, 0.08, 0.112), 'head', axis_to=Vector((0.12, 0, 1)))
for s in 'LR':
    y = 1 if s == 'L' else -1
    ellipsoid('delt' + s, V['shoulder' + s], (0.058, 0.058, 0.058), 'upper' + s, M_EMBER)
    limb('upperM' + s, 'shoulder' + s, 'elbow' + s, 0.05, 0.04, 'upper' + s)
    ellipsoid('elbowJ' + s, V['elbow' + s], (0.04, 0.04, 0.04), 'upper' + s)
    limb('foreM' + s, 'elbow' + s, V['grip' + s] - Vector((0, 0, 0.05)), 0.04, 0.032, 'fore' + s)
    ellipsoid('hand' + s, V['grip' + s] - Vector((0, 0, 0.005)), (0.036, 0.03, 0.05), 'fore' + s)
    limb('thighM' + s, 'hip' + s, 'knee' + s, 0.08, 0.055, 'thigh' + s)
    ellipsoid('kneeJ' + s, V['knee' + s], (0.052, 0.052, 0.052), 'thigh' + s)
    limb('shinM' + s, 'knee' + s, 'ankle' + s, 0.05, 0.035, 'shin' + s)
    limb('footM' + s, (0.45, 0.15 * y, 0.04), (0.67, 0.165 * y, 0.03), 0.035, 0.03, 'foot' + s)
    # dumbbell, handle along Y through the grip (palms forward)
    g = V['grip' + s]
    limb('handle' + s, g - Vector((0, 0.075, 0)), g + Vector((0, 0.075, 0)), 0.015, 0.015, 'fore' + s, M_PROP)
    for k in (-1, 1):
        bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.06, radius2=0.06, depth=0.065)
        me = bpy.data.meshes.new('head'); bm.to_mesh(me); bm.free()
        ob = bpy.data.objects.new('dbhead' + s + str(k), me); sc.collection.objects.link(ob)
        me.transform(Matrix.Translation(g + Vector((0, k * 0.105, 0))) @ Matrix.Rotation(math.radians(90), 4, 'X') @ Matrix.Rotation(math.radians(30), 4, 'Z'))
        me.materials.append(M_PROP)
        bv = ob.modifiers.new('bevel', 'BEVEL'); bv.width = 0.008; bv.segments = 3
        vg = ob.vertex_groups.new(name='fore' + s); vg.add(range(len(me.vertices)), 1.0, 'REPLACE')
        md = ob.modifiers.new('arm', 'ARMATURE'); md.object = rig

# ---------- bench (upright, ~5° recline) ----------
def box(name, center, size, rot_y=0.0, material=M_BENCH, bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center); ob = bpy.context.object; ob.name = name
    ob.scale = size; ob.rotation_euler = (0, math.radians(rot_y), 0)
    bv = ob.modifiers.new('bevel', 'BEVEL'); bv.width = bevel; bv.segments = 4
    ob.data.materials.append(material); bpy.ops.object.shade_smooth()
    return ob
box('seat', (0.08, 0, 0.44), (0.46, 0.30, 0.07))
box('back', (-0.20, 0, 0.88), (0.06, 0.28, 0.70), rot_y=-5)
box('frame', (-0.02, 0, 0.21), (0.05, 0.05, 0.42), bevel=0.01)
box('foot', (-0.02, 0, 0.015), (0.55, 0.06, 0.03), bevel=0.01)
box('strut', (-0.16, 0, 0.42), (0.04, 0.04, 0.30), rot_y=-35, bevel=0.01)

# ---------- IK + motion ----------
fps = 30; sc.render.fps = fps; sc.frame_start = 1; sc.frame_end = 96
bpy.context.view_layer.objects.active = rig; bpy.ops.object.mode_set(mode='POSE')
targets = {}
for s in 'LR':
    y = 1 if s == 'L' else -1
    t = bpy.data.objects.new('ik' + s, None); sc.collection.objects.link(t); t.location = V['grip' + s]
    p = bpy.data.objects.new('pole' + s, None); sc.collection.objects.link(p); p.location = (0.20, 0.95 * y, 0.70)
    c = rig.pose.bones['fore' + s].constraints.new('IK'); c.target = t; c.pole_target = p; c.chain_count = 2
    c.pole_angle = math.radians(-90 if s == 'L' else -90)
    # keep the dumbbell handle level and the forearm the guide: hand follows forearm (rigid)
    targets[s] = t
bpy.ops.object.mode_set(mode='OBJECT')

BOT = {s: V['grip' + s] for s in 'LR'}
TOP = {'L': Vector((0.02, 0.25, 1.585)), 'R': Vector((0.02, -0.25, 1.585))}
def ease(t): return 0.5 - 0.5 * math.cos(math.pi * t)
# timeline (frames, 30 fps, 96 = 3.2 s): hold bottom 0-9, press 9-36 (0.9 s), hold top 36-45, lower 45-90 (1.5 s), settle 90-96
def progress(f):
    f = (f - 1) % 96
    if f < 9: return 0.0
    if f < 36: return ease((f - 9) / 27)
    if f < 45: return 1.0
    if f < 90: return 1 - ease((f - 45) / 45)
    return 0.0
def place(f):
    u = progress(f)
    for s in 'LR':
        a, b = BOT[s], TOP[s]
        # slight inward arc: hands travel up then in during the last third (natural DB press path)
        lat = a.y + (b.y - a.y) * (u ** 1.6)
        x = a.x + (b.x - a.x) * u
        z = a.z + (b.z - a.z) * u
        targets[s].location = (x, lat, z)
for f in range(1, 97):
    place(f)
    for s in 'LR': targets[s].keyframe_insert('location', frame=f)

# ---------- shadow catcher, camera, light, world ----------
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0)); floor = bpy.context.object; floor.is_shadow_catcher = True
cam_d = bpy.data.cameras.new('cam'); cam_d.type = 'ORTHO'; cam_d.ortho_scale = 2.45
cam = bpy.data.objects.new('cam', cam_d); sc.collection.objects.link(cam); sc.camera = cam
look = Vector((0.20, 0, 0.86)); yaw = math.radians(28); pitch = math.radians(6)
dirv = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
cam.location = look + dirv * 6
cam.rotation_euler = (-dirv).to_track_quat('-Z', 'Y').to_euler()
KEY = PAL['key']
def area(name, loc, energy, size, color=(1, 1, 1)):
    l = bpy.data.lights.new(name, 'AREA'); l.energy = energy; l.size = size; l.color = color
    o = bpy.data.objects.new(name, l); sc.collection.objects.link(o); o.location = loc
    o.rotation_euler = (look - Vector(loc)).to_track_quat('-Z', 'Y').to_euler(); return o
area('key', (1.6, -2.2, 2.8), KEY, 2.5, (1, 0.985, 0.96))
area('fill', (2.4, -0.4, 0.9), KEY * 0.22, 3.0)
area('rim', (-2.0, 1.0, 2.2), KEY * 0.35, 1.5)
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs['Strength'].default_value = PAL['world']

r = sc.render; r.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True; r.film_transparent = True
r.resolution_x, r.resolution_y, r.resolution_percentage = 1080, 720, 100
r.image_settings.file_format = 'PNG'; r.image_settings.color_mode = 'RGBA'
sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'
sc.cycles.max_bounces = 4
r.filepath = OUT.rstrip('/') + '/f_'
sc.frame_start, sc.frame_end = F0, F1
bpy.ops.wm.save_as_mainfile(filepath=OUT.rstrip('/') + '/../rig_%s.blend' % THEME) if False else None
bpy.ops.render.render(animation=True)
