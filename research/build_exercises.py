#!/usr/bin/env python3
"""Build Lift v1 exercises.json from clearly licensed sources only."""

from __future__ import annotations

import json
import re
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

RAW = Path("/workspace/lift/research/raw")
OUT = Path("/workspace/lift/research/exercises.json")
REPORT = Path("/workspace/lift/research/NOTES.md")

ALLOWED_MUSCLES = {
    "upper_chest", "mid_chest", "lower_chest",
    "front_delts", "side_delts", "rear_delts",
    "lats", "traps", "rhomboids", "lower_back",
    "biceps", "triceps", "forearms",
    "quads", "hamstrings", "glutes", "adductors", "abductors", "calves",
    "abs", "obliques", "neck",
}

ALLOWED_EQUIPMENT = {
    "barbell", "dumbbell", "machine", "cable", "bodyweight",
    "medicine_ball", "sled", "kettlebell", "ez_bar", "trap_bar",
    "smith_machine", "band", "plate", "other",
}

# Equipment priority when an exercise lists several implements.
EQ_PRIORITY = [
    "sled", "smith_machine", "trap_bar", "ez_bar", "cable", "machine",
    "barbell", "dumbbell", "kettlebell", "medicine_ball", "band", "plate",
    "bodyweight", "other",
]

OEI_RAW = "https://raw.githubusercontent.com/hitmanrepo/open-exercise-illustrations/main/"
WFV_CDN = "https://cdn.jsdelivr.net/gh/namnq/workout-free-videos@v2.0.0/"

STOP_WORDS = {
    "the", "a", "an", "with", "and", "or", "of", "on", "for", "to", "in",
    "using", "use",
}


def slugify(name: str) -> str:
    s = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    s = s.lower()
    s = s.replace("&", " and ").replace("/", " ").replace("'", "").replace("’", "")
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def norm_name(name: str) -> str:
    s = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    s = s.lower()
    s = s.replace("&", " and ").replace("'", "").replace("’", "")
    s = re.sub(r"[^a-z0-9]+", " ", s)
    s = s.replace("pullups", "pull up").replace("pullup", "pull up")
    s = s.replace("chinups", "chin up").replace("chinup", "chin up")
    s = s.replace("pushups", "push up").replace("pushup", "push up")
    s = s.replace("dumbells", "dumbbell").replace("dumbell", "dumbbell")
    s = re.sub(r"\bbarbells\b", "barbell", s)
    s = re.sub(r"\bdumbbells\b", "dumbbell", s)
    s = re.sub(r"\bkettlebells\b", "kettlebell", s)
    s = re.sub(r"\bbands\b", "band", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def norm_key(name: str) -> str:
    """Aggressive key for matching variants of the same exercise."""
    s = norm_name(name)
    # drop filler words but keep grip/angle modifiers
    parts = [w for w in s.split() if w not in STOP_WORDS]
    return " ".join(parts)


MUSCLE_DIRECT = {
    "abdominals": "abs",
    "abs": "abs",
    "core": "abs",
    "obliques": "obliques",
    "obliquus externus abdominis": "obliques",
    "chest": "mid_chest",
    "pectorals": "mid_chest",
    "upper chest": "upper_chest",
    "lower chest": "lower_chest",
    "shoulders": "front_delts",
    "shoulder": "front_delts",
    "delts": "front_delts",
    "deltoids": "front_delts",
    "anterior deltoid": "front_delts",
    "front delts": "front_delts",
    "side delts": "side_delts",
    "lateral deltoid": "side_delts",
    "rear delts": "rear_delts",
    "posterior deltoid": "rear_delts",
    "lats": "lats",
    "latissimus dorsi": "lats",
    "traps": "traps",
    "trapezius": "traps",
    "middle back": "rhomboids",
    "upper back": "rhomboids",
    "upperback": "rhomboids",
    "back": "rhomboids",
    "rhomboids": "rhomboids",
    "lower back": "lower_back",
    "lowerback": "lower_back",
    "lower_back": "lower_back",
    "biceps": "biceps",
    "biceps brachii": "biceps",
    "brachialis": "biceps",
    "triceps": "triceps",
    "triceps brachii": "triceps",
    "forearms": "forearms",
    "forearm": "forearms",
    "quadriceps": "quads",
    "quads": "quads",
    "hamstrings": "hamstrings",
    "biceps femoris": "hamstrings",
    "glutes": "glutes",
    "gluteus maximus": "glutes",
    "adductors": "adductors",
    "abductors": "abductors",
    "calves": "calves",
    "gastrocnemius": "calves",
    "soleus": "calves",
    "neck": "neck",
}

# keys we recognise but cannot map onto the Lift muscle list
MUSCLE_SKIP = {
    "tibialis", "tibialis anterior", "hipflexors", "hip flexors",
    "itband", "it band", "palmar", "plantar",
}


def _canon_muscle_key(raw: str) -> str:
    s = raw.strip()
    s = re.sub(r"([a-z])([A-Z])", r"\1 \2", s)
    return s.lower().replace("_", " ").replace("-", " ")


def map_muscle(raw: str) -> str | None:
    if not raw:
        return None
    key = _canon_muscle_key(raw)
    key = re.sub(r"\s+", " ", key).strip()
    if key in MUSCLE_SKIP:
        return None
    if key in ("serratus", "serratus anterior"):
        return "mid_chest"
    return MUSCLE_DIRECT.get(key)


def refine_chest(muscles: list[str], name: str) -> list[str]:
    n = norm_name(name)
    out = []
    for m in muscles:
        if m == "mid_chest":
            if re.search(r"\bincline\b|low to high|low-to-high|upper chest", n):
                out.append("upper_chest")
            elif re.search(r"\bdecline\b|high to low|high-to-low|lower chest", n):
                out.append("lower_chest")
            else:
                out.append("mid_chest")
        else:
            out.append(m)
    return _uniq(out)


def refine_delts(muscles: list[str], name: str, role: str) -> list[str]:
    n = norm_name(name)
    out = []
    for m in muscles:
        if m != "front_delts":
            out.append(m)
            continue
        if re.search(r"rear delt|bent over lateral|reverse fly|reverse flye|face pull|rear deltoid|bent-over lateral", n):
            out.append("rear_delts")
        elif re.search(r"lateral raise|side raise|side lateral|side delt", n):
            out.append("side_delts")
        elif re.search(r"front raise|front delt|front deltoid", n):
            out.append("front_delts")
        elif re.search(r"upright row", n):
            out.append("side_delts")
        else:
            out.append("front_delts")
    return _uniq(out)


def _uniq(items: list[str]) -> list[str]:
    seen = set()
    out = []
    for x in items:
        if x and x not in seen and x in ALLOWED_MUSCLES:
            seen.add(x)
            out.append(x)
    return out


def map_muscles(raws, name: str) -> list[str]:
    if raws is None:
        raws = []
    if isinstance(raws, str):
        raws = [raws]
    mapped = [map_muscle(x) for x in raws]
    mapped = [m for m in mapped if m]
    mapped = refine_chest(mapped, name)
    mapped = refine_delts(mapped, name, "primary")
    return _uniq(mapped)


EQ_DIRECT = {
    "barbell": "barbell",
    "dumbbell": "dumbbell",
    "dumbbells": "dumbbell",
    "machine": "machine",
    "cable": "cable",
    "cable machine": "cable",
    "body only": "bodyweight",
    "bodyweight": "bodyweight",
    "body": "bodyweight",
    "none (bodyweight exercise)": "bodyweight",
    "medicine ball": "medicine_ball",
    "medicine-ball": "medicine_ball",
    "sled": "sled",
    "kettlebell": "kettlebell",
    "kettlebells": "kettlebell",
    "e-z curl bar": "ez_bar",
    "ez-bar": "ez_bar",
    "ez bar": "ez_bar",
    "sz-bar": "ez_bar",
    "trap-bar": "trap_bar",
    "trap bar": "trap_bar",
    "smith-machine": "smith_machine",
    "smith machine": "smith_machine",
    "bands": "band",
    "band": "band",
    "mini-band": "band",
    "resistance band": "band",
    "exercise band": "band",
    "plate": "plate",
    "weight plate": "plate",
    "pull-up-bar": "bodyweight",
    "pull-up bar": "bodyweight",
    "pullupbar": "bodyweight",
    "dipbars": "bodyweight",
    "dip bars": "bodyweight",
    "parallel-bars": "bodyweight",
    "parallel bars": "bodyweight",
    "captains-chair": "bodyweight",
    "roman-chair": "bodyweight",
    "ezbar": "ez_bar",
    "roller": "other",
    "foam-roller": "other",
    "lacrosse": "other",
    "bench": None,  # accessory
    "incline-bench": None,
    "decline-bench": None,
    "flat bench": None,
    "incline bench": None,
    "gym mat": None,
    "squat-rack": None,
    "step": None,
    "wall": None,
}


def infer_equipment_from_name(name: str) -> str | None:
    n = norm_name(name)
    rules = [
        (r"\bsled\b|prowler", "sled"),
        (r"\bsmith\b", "smith_machine"),
        (r"trap bar|hex bar", "trap_bar"),
        (r"\bez[ -]?bar\b|\be z bar\b|ez curl|e z curl", "ez_bar"),
        (r"medicine ball|med ball|\bwall ball\b", "medicine_ball"),
        (r"kettlebell", "kettlebell"),
        (r"\bcable\b|\bpulley\b", "cable"),
        (r"resistance band|\bband\b", "band"),
        (r"\bdumbbell\b", "dumbbell"),
        (r"\bbarbell\b", "barbell"),
        (r"\bmachine\b", "machine"),
        (r"plate pinch|plate raise|plate curl|plate twist|svend press|plate crunch|plate neck|olympic plate", "plate"),
        (r"\bprowler\b|(?<!band )\bdrag\b", "sled"),
        (r"\bchin\b|\bdip\b", "bodyweight"),
    ]
    for pat, eq in rules:
        if re.search(pat, n):
            return eq
    return None


def map_equipment(raws, name: str) -> str:
    if raws is None:
        raws = []
    if isinstance(raws, str):
        raws = [raws]
    found = []
    for r in raws:
        if not r:
            continue
        key = str(r).strip().lower()
        mapped = EQ_DIRECT.get(key, "other" if key not in ("other",) else None)
        if key == "other":
            continue
        if mapped:
            found.append(mapped)
    inferred = infer_equipment_from_name(name)
    if inferred:
        found.insert(0, inferred)
    # bodyweight default if nothing else and name looks unweighted
    found = [e for e in found if e in ALLOWED_EQUIPMENT]
    if not found:
        n = norm_name(name)
        if re.search(
            r"push up|pull up|chin up|\bchin\b|\bdip\b|plank|sit up|crunch|"
            r"lunge|burpee|mountain climber|bodyweight|air squat|bear crawl|"
            r"bird dog|cat cow|child.s pose|clamshell|jumping jack|box jump|"
            r"butt kick|high knees|arm circle|ankle circle|hollow hold|"
            r"dead bug|glute bridge|hip thrust$|wall sit|superman|fire hydrant",
            n,
        ):
            return "bodyweight"
        return "other"
    found = list(dict.fromkeys(found))
    found.sort(key=lambda e: EQ_PRIORITY.index(e) if e in EQ_PRIORITY else 99)
    return found[0]


def infer_variant(name: str) -> str | None:
    n = norm_name(name)
    variants = []
    rules = [
        (r"\bincline\b", "incline"),
        (r"\bdecline\b", "decline"),
        (r"behind the neck|behind neck|rear pull", "behind-neck"),
        (r"wide grip|wide-grip", "wide-grip"),
        (r"close grip|close-grip|narrow grip|narrow-grip", "close-grip"),
        (r"neutral grip|neutral-grip|v bar|v-bar|hammer grip|parallel grip", "neutral-grip"),
        (r"mixed grip", "mixed-grip"),
        (r"single arm|one arm|one-arm|alternating", "single-arm"),
        (r"single leg|one leg|pistol", "single-leg"),
        (r"seated", "seated"),
        (r"standing", "standing"),
        (r"lying|supine", "lying"),
        (r"prone|face down", "prone"),
        (r"weighted", "weighted"),
        (r"assisted|negative", "assisted" if "assisted" in n else "negative"),
        (r"deficit", "deficit"),
        (r"pause", "paused"),
        (r"sumo", "sumo"),
        (r"front squat", "front"),
        (r"romanian|stiff leg|stiff-leg", "romanian"),
        (r"commando", "commando"),
        (r"chest to bar|chest-to-bar", "chest-to-bar"),
        (r"l sit|l-sit", "l-sit"),
        (r"towel", "towel"),
        (r"archer", "archer"),
        (r"typewriter", "typewriter"),
        (r"scapular", "scapular"),
        (r"jumping", "jumping"),
        (r"band assisted", "band-assisted"),
    ]
    for pat, label in rules:
        if re.search(pat, n) and label not in variants:
            variants.append(label)
    if not variants:
        return None
    return ", ".join(variants[:3])


def add_alias(rec, *names):
    aliases = rec.setdefault("aliases", [])
    have = {norm_key(rec["name"])} | {norm_key(a) for a in aliases}
    for n in names:
        if not n:
            continue
        k = norm_key(n)
        if k and k not in have and n != rec["name"]:
            aliases.append(n)
            have.add(k)


def new_rec(**kwargs):
    rec = {
        "id": kwargs["id"],
        "name": kwargs["name"],
        "primaryMuscles": kwargs.get("primaryMuscles") or [],
        "secondaryMuscles": kwargs.get("secondaryMuscles") or [],
        "equipment": kwargs["equipment"],
        "variant": kwargs.get("variant"),
        "aliases": kwargs.get("aliases") or [],
        "mediaRef": kwargs.get("mediaRef"),
        "source": kwargs["source"],
    }
    rec["primaryMuscles"] = _uniq(rec["primaryMuscles"])
    rec["secondaryMuscles"] = _uniq([m for m in rec["secondaryMuscles"] if m not in rec["primaryMuscles"]])
    if rec["equipment"] not in ALLOWED_EQUIPMENT:
        raise ValueError(rec)
    return rec


def load_sources():
    fedb = json.load(open(RAW / "fedb-exercises.json"))
    oei = json.load(open(RAW / "oei-exercises.json"))
    wfv = json.load(open(RAW / "wfv-exercises.json"))
    return fedb, oei, wfv


def build():
    fedb, oei_doc, wfv = load_sources()
    records = []
    by_key = {}
    by_id = {}

    def index(rec):
        keys = [norm_key(rec["name"])] + [norm_key(a) for a in rec["aliases"]]
        for k in keys:
            by_key.setdefault(k, rec)
        by_id[rec["id"]] = rec

    def ensure_unique_id(base: str) -> str:
        slug = base
        i = 2
        while slug in by_id:
            slug = f"{base}-{i}"
            i += 1
        return slug

    # 1) free-exercise-db metadata (Unlicense). Do not use its images.
    for e in fedb:
        name = e["name"]
        prim = map_muscles(e.get("primaryMuscles"), name)
        sec = map_muscles(e.get("secondaryMuscles"), name)
        rec = new_rec(
            id=ensure_unique_id(slugify(name)),
            name=name,
            primaryMuscles=prim,
            secondaryMuscles=sec,
            equipment=map_equipment(e.get("equipment"), name),
            variant=infer_variant(name),
            aliases=[],
            mediaRef=None,
            source="free-exercise-db",
        )
        # useful aliases from messy original names
        if name.lower() == "pullups":
            add_alias(rec, "Pull-Up", "Pull Up", "Pullups")
        records.append(rec)
        index(rec)

    # 2) open-exercise-illustrations (CC0) — add unique exercises, attach media
    for e in oei_doc["exercises"]:
        name = e["name"]
        keys = [norm_key(name)] + [norm_key(a) for a in (e.get("aliases") or [])]
        match = next((by_key[k] for k in keys if k in by_key), None)
        start = e.get("images", {}).get("start") or e.get("images", {}).get("hold")
        media = (OEI_RAW + start) if start else None
        prim = map_muscles(e.get("muscles", {}).get("primary"), name)
        sec = map_muscles(e.get("muscles", {}).get("secondary"), name)
        eq_raw = e.get("equipment") or []
        if match:
            add_alias(match, name, *(e.get("aliases") or []))
            if media and match["mediaRef"] is None:
                match["mediaRef"] = media
            # fill missing muscles from OEI if fedb was empty
            if not match["primaryMuscles"] and prim:
                match["primaryMuscles"] = prim
                match["secondaryMuscles"] = [m for m in sec if m not in prim]
            if match["equipment"] == "other" and eq_raw:
                match["equipment"] = map_equipment(eq_raw, name)
            if not match["variant"]:
                match["variant"] = infer_variant(name)
        else:
            rec = new_rec(
                id=ensure_unique_id(e["id"]),
                name=name,
                primaryMuscles=prim,
                secondaryMuscles=sec,
                equipment=map_equipment(eq_raw, name),
                variant=infer_variant(name),
                aliases=list(e.get("aliases") or []),
                mediaRef=media,
                source="open-exercise-illustrations",
            )
            records.append(rec)
            index(rec)
        # also index aliases
        if match:
            index(match)

    # OEI variants (alternate names reusing images)
    for v in oei_doc.get("variants") or []:
        # expected keys: name, of, note? — inspect safely
        if not isinstance(v, dict):
            continue
        target_id = v.get("of") or v.get("exercise") or v.get("id")
        vname = v.get("name")
        if not vname:
            continue
        # find host
        host = by_id.get(target_id) or by_key.get(norm_key(v.get("ofName") or ""))
        if host:
            add_alias(host, vname)

    # 3) workout-free-videos (CC0) — prefer real looping video as media
    for e in wfv:
        name = e["name"]
        keys = [norm_key(name), norm_key(e.get("slug") or "")]
        match = next((by_key[k] for k in keys if k in by_key), None)
        media = WFV_CDN + e["video"]["path"]
        prim = map_muscles([e.get("primaryMuscle")], name)
        sec = map_muscles(e.get("secondaryMuscles"), name)
        eq = map_equipment(e.get("equipment"), name)
        if match:
            add_alias(match, name, e.get("slug", "").replace("-", " ").title())
            # Video is a clearer how-to than a still, and is clearly CC0.
            match["mediaRef"] = media
            if not match["primaryMuscles"] and prim:
                match["primaryMuscles"] = prim
                match["secondaryMuscles"] = [m for m in sec if m not in prim]
            if match["equipment"] == "other":
                match["equipment"] = eq
        else:
            rec = new_rec(
                id=ensure_unique_id(e["slug"]),
                name=name,
                primaryMuscles=prim,
                secondaryMuscles=sec,
                equipment=eq,
                variant=infer_variant(name),
                aliases=[],
                mediaRef=media,
                source="workout-free-videos",
            )
            records.append(rec)
            index(rec)

    # 4) Original gap-fills for Ben: more pull-up variants, sled pull, common med-ball work.
    # These are short original metadata only (no copied descriptions or media).
    gap = [
        dict(name="Close-Grip Pull-Up", primaryMuscles=["lats", "biceps"], secondaryMuscles=["rhomboids", "forearms"], equipment="bodyweight", variant="close-grip", aliases=["Close Grip Pull-Up", "Narrow-Grip Pull-Up"]),
        dict(name="Close-Grip Chin-Up", primaryMuscles=["biceps", "lats"], secondaryMuscles=["rhomboids", "forearms"], equipment="bodyweight", variant="close-grip", aliases=["Close Grip Chin-Up"]),
        dict(name="Wide-Grip Chin-Up", primaryMuscles=["lats", "biceps"], secondaryMuscles=["rhomboids", "forearms"], equipment="bodyweight", variant="wide-grip", aliases=[]),
        dict(name="Weighted Chin-Up", primaryMuscles=["lats", "biceps"], secondaryMuscles=["rhomboids", "forearms"], equipment="bodyweight", variant="weighted", aliases=["Weighted Chin Up"]),
        dict(name="Commando Pull-Up", primaryMuscles=["lats", "biceps"], secondaryMuscles=["obliques", "forearms"], equipment="bodyweight", variant="commando", aliases=["Side-to-Side Pull-Up"]),
        dict(name="Chest-to-Bar Pull-Up", primaryMuscles=["lats"], secondaryMuscles=["biceps", "rhomboids", "abs"], equipment="bodyweight", variant="chest-to-bar", aliases=["Chest to Bar Pull-Up", "CTB Pull-Up"]),
        dict(name="L-Sit Pull-Up", primaryMuscles=["lats", "abs"], secondaryMuscles=["biceps", "hip flexors"] if False else ["biceps"], equipment="bodyweight", variant="l-sit", aliases=["L Sit Pull-Up"]),
        dict(name="Towel Pull-Up", primaryMuscles=["lats", "forearms"], secondaryMuscles=["biceps", "rhomboids"], equipment="bodyweight", variant="towel", aliases=["Towel Grip Pull-Up"]),
        dict(name="Mixed-Grip Pull-Up", primaryMuscles=["lats", "biceps"], secondaryMuscles=["rhomboids", "forearms"], equipment="bodyweight", variant="mixed-grip", aliases=["Mixed Grip Pull-Up"]),
        dict(name="Typewriter Pull-Up", primaryMuscles=["lats"], secondaryMuscles=["biceps", "obliques", "rhomboids"], equipment="bodyweight", variant="typewriter", aliases=[]),
        dict(name="Jumping Pull-Up", primaryMuscles=["lats"], secondaryMuscles=["biceps", "glutes"], equipment="bodyweight", variant="jumping", aliases=["Kipping Jump Pull-Up"]),
        dict(name="Archer Pull-Up", primaryMuscles=["lats"], secondaryMuscles=["biceps", "rhomboids", "obliques"], equipment="bodyweight", variant="archer", aliases=["Typewriter-to-Archer Pull-Up"]),
        dict(name="Ring Pull-Up", primaryMuscles=["lats"], secondaryMuscles=["biceps", "forearms", "rhomboids"], equipment="bodyweight", variant=None, aliases=["Gymnastic Ring Pull-Up"]),
        dict(name="Australian Pull-Up", primaryMuscles=["rhomboids", "lats"], secondaryMuscles=["biceps", "rear_delts"], equipment="bodyweight", variant=None, aliases=["Inverted Row", "Bodyweight Row", "Inverted Bodyweight Row"]),
        dict(name="Sled Pull", primaryMuscles=["lats", "rhomboids"], secondaryMuscles=["biceps", "forearms", "glutes"], equipment="sled", variant=None, aliases=["Rope Sled Pull", "Standing Sled Pull"]),
        dict(name="Backward Sled Pull", primaryMuscles=["quads", "glutes"], secondaryMuscles=["hamstrings", "calves"], equipment="sled", variant=None, aliases=["Backward Sled Drag", "Reverse Sled Pull"]),
        dict(name="Lateral Sled Drag", primaryMuscles=["abductors", "adductors"], secondaryMuscles=["glutes", "quads"], equipment="sled", variant=None, aliases=["Side Sled Drag"]),
        dict(name="Medicine Ball Slam", primaryMuscles=["abs", "lats"], secondaryMuscles=["shoulders"] if False else ["front_delts", "triceps"], equipment="medicine_ball", variant=None, aliases=["Med Ball Slam", "Ball Slam"]),
        dict(name="Medicine Ball Wall Ball", primaryMuscles=["quads", "front_delts"], secondaryMuscles=["glutes", "triceps"], equipment="medicine_ball", variant=None, aliases=["Wall Ball", "Wall Ball Shot"]),
        dict(name="Medicine Ball Rotational Throw", primaryMuscles=["obliques"], secondaryMuscles=["abs", "front_delts"], equipment="medicine_ball", variant=None, aliases=["Med Ball Rotational Throw", "Side Medicine Ball Throw"]),
        dict(name="Medicine Ball Squat to Press", primaryMuscles=["quads", "front_delts"], secondaryMuscles=["glutes", "triceps"], equipment="medicine_ball", variant=None, aliases=["Med Ball Thruster"]),
        dict(name="Medicine Ball Russian Twist", primaryMuscles=["obliques"], secondaryMuscles=["abs"], equipment="medicine_ball", variant=None, aliases=["Med Ball Russian Twist"]),
        dict(name="Medicine Ball Woodchop", primaryMuscles=["obliques"], secondaryMuscles=["abs", "front_delts"], equipment="medicine_ball", variant=None, aliases=["Med Ball Woodchop", "Medicine Ball Chop"]),
        dict(name="Medicine Ball Overhead Slam", primaryMuscles=["abs", "lats"], secondaryMuscles=["front_delts", "triceps"], equipment="medicine_ball", variant=None, aliases=["Overhead Med Ball Slam"]),
        dict(name="Trap Bar Shrug", primaryMuscles=["traps"], secondaryMuscles=["forearms"], equipment="trap_bar", variant=None, aliases=["Hex Bar Shrug"]),
        dict(name="Trap Bar Jump", primaryMuscles=["quads", "glutes"], secondaryMuscles=["hamstrings", "calves"], equipment="trap_bar", variant=None, aliases=["Hex Bar Jump", "Trap Bar Jump Shrug"]),
        dict(name="Trap Bar Farmer Carry", primaryMuscles=["traps", "forearms"], secondaryMuscles=["abs", "glutes"], equipment="trap_bar", variant=None, aliases=["Hex Bar Carry", "Trap Bar Carry"]),
    ]

    added_gaps = []
    for g in gap:
        keys = [norm_key(g["name"])] + [norm_key(a) for a in g.get("aliases") or []]
        match = next((by_key[k] for k in keys if k in by_key), None)
        if match:
            add_alias(match, g["name"], *g.get("aliases", []))
            if match["equipment"] == "other" and g["equipment"] != "other":
                match["equipment"] = g["equipment"]
            continue
        rec = new_rec(
            id=ensure_unique_id(slugify(g["name"])),
            name=g["name"],
            primaryMuscles=g["primaryMuscles"],
            secondaryMuscles=g["secondaryMuscles"],
            equipment=g["equipment"],
            variant=g.get("variant") or infer_variant(g["name"]),
            aliases=list(g.get("aliases") or []),
            mediaRef=None,
            source="lift",
        )
        records.append(rec)
        index(rec)
        added_gaps.append(rec["name"])

    # Prefer readable pull-up names; keep the original as an alias.
    rename = {
        "Pullups": "Pull-Up",
        "Weighted Pull Ups": "Weighted Pull-Up",
        "V-Bar Pullup": "V-Bar Pull-Up",
        "Mixed Grip Chin": "Mixed-Grip Chin-Up",
        "Side To Side Chins": "Side-to-Side Chin-Up",
        "Gironda Sternum Chins": "Sternum Chin-Up",
    }
    for rec in records:
        if rec["name"] in rename:
            original = rec["name"]
            rec["name"] = rename[original]
            add_alias(rec, original)
            if rec["equipment"] == "other":
                rec["equipment"] = "bodyweight"
            if not rec["variant"]:
                rec["variant"] = infer_variant(rec["name"])

    # Cross-alias near-duplicate pull-up / chin-up names
    def find_rec(*names):
        for n in names:
            if norm_key(n) in by_key:
                return by_key[norm_key(n)]
        return None

    pairs = [
        ("Commando Pull-Up", "Side-to-Side Chin-Up"),
        ("Mixed-Grip Pull-Up", "Mixed-Grip Chin-Up"),
        ("Neutral Grip Pull Up", "V-Bar Pull-Up"),
        ("Australian Pull-Up", "Inverted Row"),
    ]
    for a, b in pairs:
        ra, rb = find_rec(a), find_rec(b)
        if ra and rb and ra is not rb:
            add_alias(ra, rb["name"], *rb["aliases"])
            add_alias(rb, ra["name"], *ra["aliases"])

    # Stable sort: name, then id
    records.sort(key=lambda r: (r["name"].lower(), r["id"]))

    # Validate
    for r in records:
        assert r["id"]
        assert r["name"]
        assert r["equipment"] in ALLOWED_EQUIPMENT
        for m in r["primaryMuscles"] + r["secondaryMuscles"]:
            assert m in ALLOWED_MUSCLES, (r["name"], m)
        assert r["source"] in {
            "free-exercise-db", "open-exercise-illustrations",
            "workout-free-videos", "lift",
        }
        assert r["mediaRef"] is None or r["mediaRef"].startswith("https://")
        # mediaRef only from clearly bundlable CC0 sources
        if r["mediaRef"]:
            assert (
                "open-exercise-illustrations" in r["mediaRef"]
                or "workout-free-videos" in r["mediaRef"]
            ), r["mediaRef"]

    ids = [r["id"] for r in records]
    assert len(ids) == len(set(ids))

    OUT.write_text(json.dumps(records, indent=2, ensure_ascii=False) + "\n")
    return records, added_gaps, oei_doc, wfv, fedb


def coverage_tables(records):
    by_mus = Counter()
    by_eq = Counter(r["equipment"] for r in records)
    matrix = defaultdict(Counter)
    for r in records:
        mus = r["primaryMuscles"] or ["(unspecified)"]
        for m in mus:
            by_mus[m] += 1
            matrix[m][r["equipment"]] += 1
    return by_mus, by_eq, matrix


def media_stats(records):
    oei = sum(1 for r in records if r["mediaRef"] and "open-exercise-illustrations" in r["mediaRef"])
    wfv = sum(1 for r in records if r["mediaRef"] and "workout-free-videos" in r["mediaRef"])
    none = sum(1 for r in records if not r["mediaRef"])
    return oei, wfv, none


if __name__ == "__main__":
    records, added_gaps, oei_doc, wfv, fedb = build()
    by_mus, by_eq, matrix = coverage_tables(records)
    oei_m, wfv_m, none_m = media_stats(records)
    src_counts = Counter(r["source"] for r in records)
    eq_gaps = []
    wanted_eq = ["barbell", "dumbbell", "machine", "cable", "bodyweight", "band", "kettlebell", "medicine_ball", "sled"]
    # Per-muscle missing key equipment
    mus_order = [
        "upper_chest", "mid_chest", "lower_chest", "front_delts", "side_delts", "rear_delts",
        "lats", "traps", "rhomboids", "lower_back", "biceps", "triceps", "forearms",
        "quads", "hamstrings", "glutes", "adductors", "abductors", "calves", "abs", "obliques", "neck",
    ]
    print("TOTAL", len(records))
    print("sources", dict(src_counts))
    print("media OEI stills", oei_m, "WFV video", wfv_m, "none", none_m)
    print("equipment", dict(by_eq))
    print("muscles", dict(by_mus))
    print("gap fills added", added_gaps)
    print("wrote", OUT)
