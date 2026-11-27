#!/usr/bin/env python3
"""Build the bundled exercise seed from research/exercises.json.

Validates the dataset and REPORTS failures; it never silently fixes rows.
Hard failures (duplicate id, unknown muscle/equipment, empty name, bad media)
stop the build. Warnings (no primary muscle, alias collisions) are listed in
research/VALIDATION.md and the row ships unchanged.

Usage: python3 tools/build_seed.py [--version N]
"""
import json, re, sys, collections, pathlib, argparse

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "research/exercises.json"
OUT = ROOT / "Packages/LiftKit/Sources/LiftCore/Resources/exercise-library.json"
REPORT = ROOT / "research/VALIDATION.md"
MEDIA = ROOT / "App/Resources/ExerciseMedia"
GENERATED_MAP = ROOT / "tools/generated-media-map.json"

MUSCLES = {"upper_chest","mid_chest","lower_chest","front_delts","side_delts","rear_delts","lats","traps",
           "rhomboids","lower_back","biceps","triceps","forearms","quads","hamstrings","glutes","adductors",
           "abductors","calves","abs","obliques","neck"}
EQUIPMENT = {"barbell","dumbbell","machine","cable","bodyweight","medicine_ball","sled","kettlebell","ez_bar",
             "trap_bar","smith_machine","band","plate","other"}
ID_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

# Rep ranges / rest for the common lifts, carried over from the v1 seed.
TUNED = {
    "barbell-squat": (5, 8, 180), "deadlift": (3, 5, 180), "bench-press": (5, 8, 150),
    "barbell-shoulder-press": (5, 8, 150), "bent-over-row": (6, 10, 120), "romanian-deadlift": (6, 10, 150),
    "front-squat": (5, 8, 180), "incline-bench-press": (6, 10, 120), "pullups": (6, 10, 120),
    "barbell-hip-thrust": (8, 12, 120), "leg-press": (8, 12, 120), "dips": (8, 12, 90),
    "incline-dumbbell-press": (8, 12, 90), "dumbbell-shoulder-press": (8, 12, 90), "dumbbell-row": (8, 12, 90),
    "wide-grip-lat-pulldown": (8, 12, 90), "seated-cable-row": (8, 12, 90), "bulgarian-split-squat": (8, 12, 90),
    "dumbbell-lunge": (10, 12, 90), "barbell-curl": (8, 12, 60), "hammer-curls-2": (10, 12, 60),
    "side-lateral-raise": (12, 15, 60), "triceps-pushdown": (10, 12, 60), "cable-crossover": (12, 15, 60),
    "face-pull": (12, 15, 60), "leg-curl": (10, 12, 60), "leg-extension": (10, 12, 60),
    "calf-raises": (10, 15, 60), "rear-delt-fly": (12, 15, 60), "overhead-triceps-extension": (10, 12, 60),
}
COMMON = {
    "Push": ["bench-press", "barbell-shoulder-press", "incline-dumbbell-press", "dips", "side-lateral-raise",
             "triceps-pushdown", "cable-crossover"],
    "Pull": ["deadlift", "pullups", "bent-over-row", "wide-grip-lat-pulldown", "seated-cable-row", "face-pull",
             "barbell-curl", "hammer-curls-2"],
    "Legs": ["barbell-squat", "romanian-deadlift", "leg-press", "leg-curl", "leg-extension", "calf-raises",
             "bulgarian-split-squat"],
}

def generated_media_map():
    """Exercise id -> bundled video stem. Aliases share the target file."""
    if not hasattr(generated_media_map, "_cache"):
        generated_media_map._cache = json.loads(GENERATED_MAP.read_text()) if GENERATED_MAP.is_file() else {}
    return generated_media_map._cache

def local_media(e):
    """Map a research mediaRef, or a generated-media-map entry, to the vendored file key. Returns (key, files)."""
    i = e["id"]
    mapped = generated_media_map().get(i)
    if mapped:
        return f"video:{mapped}", [f"video/{mapped}.mp4"]
    r = e.get("mediaRef")
    if not r:
        return None, []
    if r.endswith(".mp4") and "namnq/workout-free-videos@v2.0.0" in r:
        return f"video:{i}", [f"video/{i}.mp4"]
    if "hitmanrepo/open-exercise-illustrations" in r and r.endswith("/start.webp"):
        return f"still:{i}", [f"stills/{i}-start.webp", f"stills/{i}-end.webp"]
    if "hitmanrepo/open-exercise-illustrations" in r and r.endswith("/hold.webp"):
        return f"hold:{i}", [f"stills/{i}-hold.webp"]
    return "INVALID", []

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--version", type=int, default=2)
    args = ap.parse_args()
    rows = json.loads(SRC.read_text())
    errors, warnings = [], []
    ids = collections.Counter(r.get("id") for r in rows)
    for k, v in ids.items():
        if v > 1: errors.append(f"`{k}`: duplicate id ({v} rows)")
    names = collections.defaultdict(list)
    for r in rows:
        i = r.get("id") or "(missing id)"
        if not r.get("id") or not ID_RE.match(r["id"]): errors.append(f"`{i}`: id is not a stable slug")
        if not (r.get("name") or "").strip(): errors.append(f"`{i}`: empty name")
        elif r["name"] != r["name"].strip(): errors.append(f"`{i}`: name has leading/trailing spaces")
        for f in ("primaryMuscles", "secondaryMuscles"):
            bad = [m for m in r.get(f) or [] if m not in MUSCLES]
            if bad: errors.append(f"`{i}`: unknown {f} {bad}")
        if r.get("equipment") not in EQUIPMENT: errors.append(f"`{i}`: unknown equipment {r.get('equipment')!r}")
        if not r.get("primaryMuscles"): warnings.append(f"`{i}` ({r.get('name')}): no primary muscle; hidden by muscle filters, still searchable")
        overlap = set(r.get("primaryMuscles") or []) & set(r.get("secondaryMuscles") or [])
        if overlap: warnings.append(f"`{i}`: muscle in both primary and secondary {sorted(overlap)}")
        key, files = local_media(r)
        if key == "INVALID": errors.append(f"`{i}`: mediaRef is not a known bundled source: {r['mediaRef']}")
        for fp in files:
            if not (MEDIA / fp).is_file(): errors.append(f"`{i}`: vendored media missing {fp}")
        nk = (r.get("name","").lower(), (r.get("variant") or "").lower())
        names[nk].append(i)
    for k, v in names.items():
        if len(v) > 1: warnings.append(f"same name+variant {k}: {v}")
    alias_owner = collections.defaultdict(set)
    for r in rows:
        for a in [r["name"]] + (r.get("aliases") or []):
            alias_owner[a.strip().lower()].add(r["id"])
    for a, owners in sorted(alias_owner.items()):
        if len(owners) > 1: warnings.append(f"alias/name `{a}` used by {sorted(owners)}")
    for day, lst in COMMON.items():
        for i in lst:
            if i not in ids: errors.append(f"common[{day}] references missing id `{i}`")

    lines = ["# Exercise seed validation", "", f"Source: research/exercises.json ({len(rows)} rows). Seed version {args.version}.", "",
             f"## Errors ({len(errors)})", ""] + [f"- {e}" for e in errors] + ["", f"## Warnings ({len(warnings)}), shipped unchanged", ""] + [f"- {w}" for w in warnings]
    REPORT.write_text("\n".join(lines) + "\n")
    print(f"{len(rows)} rows, {len(errors)} errors, {len(warnings)} warnings -> {REPORT.relative_to(ROOT)}")
    if errors:
        print("\n".join(errors[:50])); sys.exit(1)

    out = []
    for r in rows:
        lo, hi, rest = TUNED.get(r["id"], (8, 12, None))
        e = {"id": r["id"], "name": r["name"], "primaryMuscles": r["primaryMuscles"], "secondaryMuscles": r["secondaryMuscles"],
             "equipment": r["equipment"], "variant": r.get("variant") or "", "aliases": r.get("aliases") or [],
             "repMin": lo, "repMax": hi, "source": r.get("source")}
        if rest: e["restSeconds"] = rest
        key, _ = local_media(r)
        if key: e["mediaRef"] = key
        out.append(e)
    lib = {"version": args.version, "source": "research/exercises.json (free-exercise-db data, Unlicense; OEI/WFV media, CC0; Lift gap-fills)",
           "exercises": out, "common": COMMON}
    OUT.write_text(json.dumps(lib, ensure_ascii=False, separators=(",", ":")))
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)")

if __name__ == "__main__":
    main()
