"""Classify Lift's exercise library into animation motions. Re-runnable.
Output: inventory.csv (one row per library exercise) + motions.csv (one row per unique motion)."""
import json, re, csv, collections, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, '../../Packages/LiftKit/Sources/LiftCore/Resources/exercise-library.json')
d = json.load(open(LIB)); ex = d['exercises']
common = {i for v in d['common'].values() for i in v}

# (regex on lowercase name, family, base movement, camera, loop seconds, cues)
R = [
 (r'pull[- ]?ups?\b|chin[- ]?ups?|muscle[- ]?up|rope climb|body-up|dead hang|scap pull|one handed hang|incline bench pull', 'vertical-pull', 'Pull-up', '3/4 front', 3.2, 'Start from a dead hang, shoulders set; Pull chest toward the bar, elbows down and back; Lower under control to full hang'),
 (r'^(?!.*(chest|bench|leg|tricep|calf|floor|incline|decline|jammer|neck press)).*(seated|standing).*press|bradford|press behind neck|behind.the.neck press', 'vertical-push', 'Overhead press', 'side', 3.2, 'Ribs down, glutes tight, no lumbar arch; Wrists stacked over elbows; Press to lockout over the mid-foot / shoulders'),
 # ---- non-lifting (tier C) first so 'stretch' wins over 'chest'
 (r'smr|foam roll|lacrosse', 'mobility', 'Self-massage (SMR)', 'side', 4, ''),
 (r'stretch|circles|rotations?$|rock-?backs|dislocates|world.s greatest|ankle on the knee|upward stretch|leg grab|cat |child|pigeon|cobra|hug|scorpion|mountain climb(?!er)|hip opener|spinal twist|knee to chest|wall slides|ankle rocks|arm crossovers|swing(s)? -? ?arm|looking at ceiling|on your side quad|iron cross|90/90|neck|cat-cow|downward|inchworm|hip flexor|capsule|lying glute|lying hamstring|lying prone quad|groin|locust|claw|balance|elbows back|one arm against wall|hip flexion with band|kneeling arm drill|chest squeeze', 'mobility', 'Stretch / mobility', '3/4', 6, ''),
 (r'treadmill|bicycl|elliptical|rowing, stationary|stair|jog|walking, |run|sprint|skip|jump rope|air bike|rope jump|recumbent|battl|battle rope|trail running|step mill', 'conditioning', 'Cardio / conditioning', 'side', 2, ''),
 (r'jump|bound|hop|burpee|slam|chest pass|wall ball|chest push|heavy bag|butt kick|high knees|carioca|march in place|linear|jammer|judo|box skip|plyo|clap|depth|power stairs|split jump|star jump|tuck jump|frog', 'plyometric', 'Plyometric', 'side', 2, ''),
 (r'atlas|yoke|keg|log lift|tire|farmer|carry|sled|drag|axle|car |conan|chain handle|sandbag|suitcase|rickshaw|crucifix|fingertip|walk(?!ing lunge)|prowler|bear crawl|backward drag', 'strongman', 'Carry / sled / strongman', 'side', 3, ''),
 (r'clean|snatch|jerk|high pull|push press|thruster|split jerk|hang pull|muscle snatch|power stairs', 'olympic', 'Olympic / power lift', 'side', 3, 'Bar close to body; Hips drive, then arms; Stable catch'),
 # ---- pulls (vertical)
 (r'pulldown|pull-down|lat pull|straight-arm|pullover', 'vertical-pull', None, '3/4 front', 3.2, ''),
 # ---- hinge
 (r'romanian|rdl|stiff[- ]leg|stiff legs|good ?morning|pull through|hip hinge', 'hinge', 'Romanian deadlift / good morning', 'side', 3.6, 'Soft knees, hips push back; Bar or weights slide along the legs; Flat back, stop at hamstring stretch'),
 (r'deadlift|rack pull|deficit pull', 'hinge', 'Deadlift', 'side', 3.6, 'Bar over mid-foot, flat back; Push the floor away, hips and shoulders rise together; Stand tall, no lean back'),
 (r'hip thrust|glute bridge|hip raise|butt lift|bridge', 'hinge', 'Hip thrust / glute bridge', 'side', 3.0, 'Chin tucked, ribs down; Drive through heels to full hip extension; Shins vertical at the top'),
 (r'back extension|hyperextension|reverse hyper|glute.ham|superman', 'hinge', 'Back extension', 'side', 3.0, 'Hinge at the hips; Rise to a straight line, no over-arch; Lower under control'),
 (r'kettlebell swing|swing|pull-through|pass between|figure 8|hip lift with band', 'hinge', 'Kettlebell swing', 'side', 2.0, 'Hike the bell back, hips snap forward; Arms float, no shoulder lift; Plank at the top'),
 # ---- squat / lunge / leg machines
 (r'leg press', 'squat', 'Leg press', 'side', 3.4, 'Feet mid-plate, knees track toes; Lower until hips stay down; Press without locking knees hard'),
 (r'hack squat|v-squat|belt squat|pendulum', 'squat', 'Machine squat', 'side', 3.4, ''),
 (r'split squat|bulgarian|lunge|step-?ups?|step up|step-down|curtsy|skater', 'lunge', None, 'side', 3.6, 'Torso tall, front knee over mid-foot; Back knee drops straight down; Drive through the front heel'),
 (r'squat|wall sit|sissy|pistol', 'squat', None, 'side', 3.6, 'Brace, knees track over toes; Hips down to at least parallel, chest up; Stand by pushing the floor away'),
 (r'leg extension|knee extension', 'leg-machine', 'Leg extension', 'side', 3.0, 'Pad on lower shin, back against pad; Straighten fully, squeeze quads; Lower slowly'),
 (r'leg curl|hamstring curl|nordic|glute-ham', 'leg-machine', 'Leg curl', 'side', 3.0, 'Knees in line with pivot; Curl heels toward glutes; Hips stay down'),
 (r'calf|tibialis|dorsiflexion|toe raise|donkey calf', 'calf', 'Calf raise', 'side', 2.4, 'Full stretch at the bottom; Rise onto the big toe; Pause at the top'),
 (r'adduct|abduct|clam|fire hydrant|hip circles|monster walk|lateral band walk|side-lying leg|hip abduction', 'hip', 'Hip ab/adduction', 'front', 3.0, ''),
 (r'kickback.*(glute|band)|glute kickback|donkey kick|cable hip extension|hip extension', 'hip', 'Glute kickback', 'side', 3.0, ''),
 # ---- horizontal push
 (r'push[- ]?ups?|press-?up|plank to push|drop push|otis', 'horizontal-push', 'Push-up', 'side', 2.8, 'Hands under shoulders, body one line; Lower chest to an inch off the floor, elbows ~45°; Press back to locked arms'),
 (r'^(?!.*(side plank|hip dip)).*(dips?\b|dip machine)', 'vertical-push', 'Dip', 'side', 3.0, 'Shoulders down, slight forward lean; Lower until upper arm is parallel; Press to lockout'),
 (r'fly|flye|crossover|pec deck|butterfly|svend', 'horizontal-push', 'Chest fly', '3/4 front', 3.2, 'Slight bend in the elbows, fixed; Open wide to a chest stretch; Hug back together over the chest'),
 (r'skull|lying triceps|french|tate', 'arms', 'Lying triceps extension', 'side', 2.8, ''),
 (r'close[- ]grip.*bench|jm press', 'horizontal-push', 'Bench press', 'side', 3.2, ''),
 (r'bench press|floor press|chest press|board press|incline press|decline press|guillotine|bradford|smith machine (incline|decline|flat)? ?bench|dumbbell press$|dumbbell bench|svend|squeeze press|hex press|pin press|incline dumbbell press|decline dumbbell press|incline barbell|decline barbell|machine press|smith press|chain press', 'horizontal-push', 'Bench press', 'side', 3.2, 'Shoulder blades back and down, feet planted; Lower to mid-chest, forearms vertical; Press up and slightly back to lockout'),
 # ---- vertical push
 (r'shoulder press|overhead press|military|arnold|push press|landmine press|z press|handstand|pike|kettlebell press|seesaw press|bent press|see-saw|anti-gravity|dumbbell press|kettlebell military|kettlebell seated press|para press|cable shoulder|overhead.*press|press overhead|behind.the.neck press|bottoms.up press|windmill', 'vertical-push', 'Overhead press', 'side', 3.2, 'Ribs down, glutes tight, no lumbar arch; Wrists stacked over elbows; Press to lockout over the mid-foot / shoulders'),
 (r'lateral raise|side lateral|deltoid raise|lateral|y-?raise|l-?raise|cuban', 'shoulder-iso', 'Lateral raise', 'front', 2.8, 'Slight elbow bend; Lift out to shoulder height, lead with elbows; Lower slowly, no swing'),
 (r'dumbbell raise$|front raise|front plate raise|front.*raise|shoulder raise', 'shoulder-iso', 'Front raise', 'side', 2.8, ''),
 (r'rear delt|reverse fly|reverse flye|face pull|pull apart|band pull|back fly|external rotation|internal rotation|rotator|w-raise|t-raise|scaption|prone .*raise', 'shoulder-iso', 'Rear delt / rotator cuff', '3/4', 2.8, ''),
 (r'upright row', 'shoulder-iso', 'Upright row', 'front', 2.8, ''),
 (r'shrug', 'shoulder-iso', 'Shrug', 'front', 2.4, 'Arms long; Shoulders straight up to ears; Pause, lower fully'),
 # ---- rows
 (r'row|renegade', 'horizontal-pull', 'Row', 'side', 3.0, 'Flat back, neck neutral; Pull elbows back past the torso; Squeeze shoulder blades, lower to a full stretch'),
 # ---- arms
 (r'curl', 'arms', 'Curl', 'side', 2.8, 'Elbows pinned at the sides; Curl without swinging; Full extension at the bottom'),
 (r'tricep|triceps|kickback|pushdown|push-down|extension|jm press', 'arms', 'Triceps extension', 'side', 2.8, 'Upper arm still; Extend to lockout; Control the stretch'),
 (r'pronation|supination|wrist|forearm|finger|grip|roller|plate pinch', 'arms', 'Wrist / grip', 'side', 2.4, ''),
 # ---- core
 (r'crunch|sit[- ]?ups?|elbow to knee|heel taps|leg lift|pull-in|cocoons|butt-ups|isometric wipers|groiners|knee across|v-?up|jackknife|toe touch|heel touch|leg raise|knee raise|knee tuck|flutter|scissor|hollow|dead bug|bicycle|toes[- ]to[- ]bar|turkish|straight raises on incline|suspended fallout|stomach vacuum|l-sit|windshield|russian twist|oblique|side bend|woodchop|wood chop|pallof|rollout|ab roller|ab wheel|plank|bird dog|mountain climber|landmine 180|rotation|twist|halo|around the worlds|pirate|cable lift|cross over - with bands|hanging|dragon flag|bear plank|bottoms up|tuck', 'core', 'Core', 'side', 2.8, ''),
]
SUBBASE = [  # refine base for some families
 ('vertical-pull', r'muscle[- ]?up', 'Muscle-up', 'False grip, explosive pull to hips; Lean over the bar fast; Press out to support'),
 ('vertical-pull', r'dead hang|one handed hang', 'Dead hang', 'Shoulders active, not shrugged; Ribs down; Breathe and hold'),
 ('vertical-pull', r'scap', 'Scapular pull-up', 'Arms stay straight; Pull shoulders down and back; Lower to full hang'),
 ('vertical-pull', r'rope climb', 'Rope climb', ''),
 ('vertical-pull', r'incline bench pull', 'Row', ''),
 ('vertical-push', r'arnold', 'Arnold press', 'Start palms facing you at the chin; Rotate palms forward as you press; Reverse on the way down'),
 ('vertical-push', r'windmill', 'Kettlebell windmill', ''),
 ('vertical-push', r'landmine', 'Landmine press', ''),
 ('vertical-push', r'bent press', 'Bent press', ''),
 ('vertical-push', r'pike|handstand', 'Pike / handstand push-up', ''),
 ('vertical-push', r'bradford|behind', 'Behind-the-neck / Bradford press', ''),
 ('vertical-push', r'dip', 'Dip', None),
 ('vertical-pull', r'straight-arm|pullover', 'Straight-arm pulldown / pullover', ''),
 ('vertical-pull', r'pulldown|pull-down|lat pull', 'Lat pulldown', 'Lean back slightly, chest up; Pull the bar to upper chest, elbows down; Let arms straighten fully'),
 ('vertical-pull', r'chin', 'Chin-up', 'Underhand grip, dead hang; Chin over the bar, chest up; Lower under control'),
 ('vertical-pull', r'muscle-?up', 'Muscle-up', ''),
 ('vertical-pull', r'rope climb', 'Rope climb', ''),
 ('lunge', r'step-?ups?|step up', 'Step-up', ''),
 ('lunge', r'split squat|bulgarian', 'Split squat', ''),
 ('lunge', r'lunge|curtsy|skater', 'Lunge', ''),
 ('squat', r'front squat|goblet|zercher', 'Front-loaded squat', 'Elbows up, torso upright; Sit between the hips; Drive up keeping chest tall'),
 ('squat', r'wall sit', 'Wall sit', ''),
 ('squat', r'sissy|pistol', 'Single-leg / sissy squat', ''),
 ('squat', r'.', 'Back squat', None),
]
def norm(s): return re.sub(r'[^a-z0-9 ]', ' ', s.lower())
def position(n, v):
    p = []
    for k in ['seated', 'standing', 'incline', 'decline', 'lying', 'kneeling', 'bent over', 'prone', 'supine', 'half-kneeling', 'hanging', 'floor']:
        if k in n or k in v: p.append(k)
    return ', '.join(dict.fromkeys(p))
def grip(n, v):
    g = []
    for pat, lab in [(r'wide', 'wide'), (r'close|narrow|diamond', 'close'), (r'neutral|palms in|hammer|v-bar|parallel', 'neutral'),
                     (r'\bchin|underhand|reverse grip|supinated|palms-up', 'underhand'), (r'mixed', 'mixed'), (r'behind (the )?neck|behind the head', 'behind-neck'),
                     (r'single-arm|one-arm|one arm|single arm|alternat|unilateral', 'single-arm'), (r'single-leg|one-leg|one leg', 'single-leg'),
                     (r'rope', 'rope'), (r'towel', 'towel'), (r'archer|typewriter|commando', 'side-to-side'), (r'weighted', 'weighted'), (r'assisted', 'assisted'), (r'chest[- ]to[- ]bar', 'chest-to-bar'), (r'l-sit', 'L-sit')]:
        if re.search(pat, n) or re.search(pat, v): g.append(lab)
    return ', '.join(dict.fromkeys(g))
EQ = {'smith_machine': 'smith', 'ez_bar': 'EZ bar', 'trap_bar': 'trap bar', 'medicine_ball': 'med ball'}
rows = []
for e in ex:
    n = e['name'].lower(); v = e['variant'] or ''
    hit = None
    for pat, fam, base, cam, loop, cues in R:
        if re.search(pat, n):
            hit = [fam, base, cam, loop, cues]; break
    if not hit: hit = ['mobility', 'Misc drill / stretch', '3/4', 4, '']
    fam, base, cam, loop, cues = hit
    for f2, pat, b2, c2 in SUBBASE:
        if f2 == fam and (base is None or f2 in ('vertical-pull', 'vertical-push')) and re.search(pat, n):
            if c2 is None: break
            if fam == 'vertical-pull' and base == 'Pull-up' and b2 not in ('Chin-up', 'Muscle-up', 'Rope climb', 'Dead hang', 'Scapular pull-up'): continue
            base = b2; cues = c2 if c2 else cues; break
    if base is None: base = fam.title()
    if 'Back squat' == base and e['equipment'] in ('bodyweight', 'other', 'band'): base = 'Bodyweight squat'
    pos = position(n, v); gr = grip(n, v)
    eq = EQ.get(e['equipment'], e['equipment'])
    if fam in ('mobility', 'conditioning', 'plyometric', 'strongman'): tier = 'C'
    elif e['id'] in common: tier = 'A'
    elif fam in ('core', 'olympic', 'other') or e['equipment'] in ('other', 'band', 'medicine_ball', 'sled', 'plate'): tier = 'B'
    else: tier = 'A' if e['equipment'] in ('barbell', 'dumbbell', 'cable', 'machine', 'smith_machine', 'bodyweight', 'ez_bar', 'kettlebell', 'trap_bar') else 'B'
    # unique motion key: base + body position + grip pattern (equipment is a prop swap unless it changes the path)
    pathgrip = ', '.join(x for x in gr.split(', ') if x and x not in ('weighted',))
    path_eq = eq if eq in ('cable', 'machine', 'band') else ('free weight' if eq in ('barbell', 'dumbbell', 'kettlebell', 'smith', 'EZ bar', 'trap bar', 'plate', 'med ball') else eq)
    if fam in ('vertical-pull',) and eq in ('bodyweight', 'machine', 'band', 'other'): path_eq = 'bar'
    motion = '|'.join([base, pos or '-', pathgrip or '-', path_eq])
    rows.append(dict(id=e['id'], name=e['name'], aliases='; '.join(e['aliases']), family=fam, base=base, equipment=eq, position=pos, grip=gr,
                     variant=' · '.join(x for x in [eq, pos, gr] if x), cues=cues, camera=cam, loop_s=loop, tier=tier, motion=motion,
                     has_media=e.get('mediaRef', '') or '', source=e['source']))
# dedupe near-identical names (Bench Dip / Bench Dips)
def key(n): return re.sub(r's\b', '', norm(n)).replace(' ', '')
seen = {}
for r in rows:
    k = key(r['name']); r['duplicate_of'] = seen.get(k, ''); seen.setdefault(k, r['id'])
# motion ids
motions = collections.OrderedDict()
for r in sorted(rows, key=lambda r: (r['family'], r['base'], r['motion'])):
    m = motions.setdefault(r['motion'], dict(members=[], props=set(), tier='C', family=r['family'], base=r['base'], camera=r['camera'], loop=r['loop_s'], cues=r['cues']))
    m['members'].append(r['id']); m['props'].add(r['equipment']); m['tier'] = min(m['tier'], r['tier'])
for i, (k, m) in enumerate(motions.items()): m['mid'] = 'M%03d' % (i + 1)
for r in rows: r['motion_id'] = motions[r['motion']]['mid']
out = os.path.join(ROOT)
with open(os.path.join(out, 'inventory.csv'), 'w', newline='') as f:
    cols = ['id', 'name', 'aliases', 'tier', 'family', 'base', 'variant', 'equipment', 'position', 'grip', 'cues', 'camera', 'loop_s', 'motion_id', 'duplicate_of', 'has_media', 'source']
    w = csv.DictWriter(f, cols, extrasaction='ignore'); w.writeheader(); w.writerows(sorted(rows, key=lambda r: (r['tier'], r['family'], r['base'], r['name'])))
with open(os.path.join(out, 'motions.csv'), 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['motion_id', 'tier', 'family', 'base', 'position', 'grip_path', 'path_equipment', 'prop_swaps', 'renders', 'exercises', 'camera', 'loop_s', 'cues', 'member_ids'])
    for k, m in motions.items():
        b, pos, gp, pe = k.split('|')
        w.writerow([m['mid'], m['tier'], m['family'], b, pos, gp, pe, '; '.join(sorted(m['props'])), len(m['props']), len(m['members']), m['camera'], m['loop'], m['cues'], ' '.join(m['members'])])
# stats
C = collections.Counter
print('exercises', len(rows), 'dupes', sum(1 for r in rows if r['duplicate_of']))
print('tiers', C(r['tier'] for r in rows))
print('families', C(r['family'] for r in rows).most_common())
print('unclassified', [r['name'] for r in rows if r['family'] == 'other'][:80])
uniq = [m for m in motions.values()]
print('motions', len(uniq), 'by tier', C(m['tier'] for m in uniq), 'renders', sum(len(m['props']) for m in uniq), 'renders A', sum(len(m['props']) for m in uniq if m['tier'] == 'A'))
print('bases', len({m['base'] for m in uniq}), 'bases A+B', len({m['base'] for m in uniq if m['tier'] != 'C'}))
