#!/usr/bin/env python3
"""After an upload: wait for App Store Connect to process the build, then add it
to an internal TestFlight group. Reads the API key path/IDs from the environment
(the workflow writes the key from secrets; nothing is printed but IDs and states).
Usage: asc_add_to_group.py <app_id> <build_number> <group name> [timeout_min]"""
import json, os, sys, time, urllib.request, urllib.parse
import jwt  # pyjwt

app_id, build, group = sys.argv[1], sys.argv[2], sys.argv[3]
deadline = time.time() + 60 * float(sys.argv[4] if len(sys.argv) > 4 else 45)
key = open(os.environ["ASC_KEY_PATH"]).read()

def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})

def call(method, path, body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}

q = urllib.parse.urlencode({"filter[app]": app_id, "filter[version]": build, "fields[builds]": "version,processingState,uploadedDate"})
b = None
while time.time() < deadline:
    data = call("GET", f"/v1/builds?{q}")["data"]
    if data:
        b = data[0]
        state = b["attributes"]["processingState"]
        print(f"build {build}: {state}", flush=True)
        if state in ("VALID", "FAILED", "INVALID"): break
    else:
        print(f"build {build}: not visible yet", flush=True)
    time.sleep(60)
if not b:
    sys.exit("build never appeared")
state = b["attributes"]["processingState"]
print(f"PROCESSING_STATE={state}")
if state != "VALID":
    sys.exit(0 if state == "PROCESSING" else 1)

gq = urllib.parse.urlencode({"filter[app]": app_id, "filter[name]": group})
groups = call("GET", f"/v1/betaGroups?{gq}")["data"]
g = next((x for x in groups if x["attributes"]["name"] == group), None)
if not g: sys.exit(f"no beta group named {group!r}")
call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": b["id"]}]})
print(f"ADDED build {build} ({b['id']}) to {group!r} ({g['id']})")
