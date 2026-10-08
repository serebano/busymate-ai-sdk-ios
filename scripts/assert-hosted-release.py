#!/usr/bin/env python3
"""Require the owner's exact live build before running real permission cases."""
import json
import os
from pathlib import Path
import re
import sys
import urllib.request

commit = os.environ.get("BUSYMATE_HOSTED_COMMIT", "")
build = os.environ.get("BUSYMATE_HOSTED_BUILD", "")
if not re.fullmatch(r"[0-9a-f]{9,40}", commit) or not re.fullmatch(r"[1-9][0-9]*", build):
    raise SystemExit("Set the verified BUSYMATE_HOSTED_COMMIT (9-40 hex) and BUSYMATE_HOSTED_BUILD. No permission test was started.")
if len(sys.argv) != 2:
    raise SystemExit("Usage: assert-hosted-release.py EVIDENCE_JSON")
request = urllib.request.Request("https://busymate.ai/api/version", headers={"Cache-Control": "no-cache"})
with urllib.request.urlopen(request, timeout=30) as response:
    if response.url != request.full_url:
        raise SystemExit("Unexpected version endpoint redirect")
    version = json.load(response)
if version.get("component") != "ai":
    raise SystemExit("Unexpected hosted component")
actual = str(version.get("commit", ""))
if not re.fullmatch(r"[0-9a-f]{9,40}", actual):
    raise SystemExit("Hosted version has no valid commit")
if not (commit.startswith(actual) or actual.startswith(commit)) or str(version.get("build")) != build:
    raise SystemExit(f"Expected build {build}/{commit}; hosted build is {version.get('build')}/{actual}. Permission tests refused.")
path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps({"expectedCommit": commit, "expectedBuild": int(build), "observed": version}, indent=2) + "\n")
print(f"Verified hosted build {build}/{actual}")
