#!/usr/bin/env python3
"""Verify a manually downloaded official binary, and stage it for LOCAL USE ONLY.
No downloads, vendor resigning, publication or credential handling happen here.
"""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess

EXPECTED_SHA256 = "3317fccefe7ea2379f9caad6d0c9daddecf69f82736d874c68fd4f464d5aab94"
REQUIREMENT = 'anchor apple generic and identifier "com.spotify.soloist" and certificate leaf[subject.OU] = "2FNC3A47ZF"'
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=Path("build/soloist/soloist"))
parser.add_argument("--app", type=Path)
args = parser.parse_args()
if not args.source.is_file():
    raise SystemExit("Missing local Soloist binary. See FORK.md; builds never fetch binaries automatically.")
if hashlib.sha256(args.source.read_bytes()).hexdigest() != EXPECTED_SHA256:
    raise SystemExit("Soloist SHA-256 mismatch. Refusing an unreviewed binary update.")
subprocess.run(["codesign", "--verify", "--strict", "-R", "=" + REQUIREMENT, str(args.source)], check=True)
print("Verified Spotify Soloist 1.3.10.19 (20261027), original Spotify signature and pinned SHA-256.")
if args.app:
    destination = args.app / "Contents/Helpers/soloist"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.source, destination)
    destination.chmod(0o755)
    if hashlib.sha256(destination.read_bytes()).hexdigest() != EXPECTED_SHA256:
        raise SystemExit("Staged Soloist failed integrity verification.")
    licenses = args.source.with_name("THIRD_PARTY_LICENSES.txt")
    if licenses.is_file():
        shutil.copy2(licenses, args.app / "Contents/Resources/Soloist-Third-Party-Licenses.txt")
    print("Staged for this Mac only. Do not redistribute this app with the Soloist binary.")
