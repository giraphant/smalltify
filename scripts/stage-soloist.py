#!/usr/bin/env python3
"""Verify the official Soloist binary, optionally fetch it from Spotify, and stage it for LOCAL USE ONLY.

Any build Spotify signed is accepted: the check is Spotify's own code signature, not a pinned
hash, because Spotify rebuilds Soloist every few days and each build expires 90 days after it
is signed. `--fetch` downloads the current build from Spotify's official address, the one its
download page links; nothing else is ever downloaded, resigned or published here.
"""
import argparse
import datetime
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

DOWNLOAD = "https://soloist-builds.spotifycdn.com/soloist_release_osx_arm64.tar.gz"
REQUIREMENT = 'anchor apple generic and identifier "com.spotify.soloist" and certificate leaf[subject.OU] = "2FNC3A47ZF"'
LIFETIME = datetime.timedelta(days=90)


def verify(binary):
    subprocess.run(["codesign", "--verify", "--strict", "-R", "=" + REQUIREMENT, str(binary)], check=True)
    details = subprocess.run(["codesign", "-dv", str(binary)], capture_output=True, text=True).stderr
    match = re.search(r"^Timestamp=(.+)$", details, re.M)
    if not match:
        print("Verified Spotify's signature on Soloist; it carries no signing time.")
        return
    # codesign writes the time in the system's format; the expiry is only advice.
    stamp = match.group(1).strip()
    for layout in ("%d %b %Y at %H:%M:%S", "%b %d, %Y at %H:%M:%S"):
        try:
            signed = datetime.datetime.strptime(stamp, layout)
            break
        except ValueError:
            pass
    else:
        print(f"Verified Spotify's signature on Soloist, signed {stamp}; builds expire 90 days later.")
        return
    expires = signed + LIFETIME
    left = (expires - datetime.datetime.now()).days
    print(f"Verified Spotify's signature on Soloist, signed {signed:%Y-%m-%d}; it expires around {expires:%Y-%m-%d}.")
    if left < 14:
        print(f"WARNING: {max(left, 0)} days left. Run `make fetch-soloist` for a newer build.")


def fetch(directory):
    """Downloads into a scratch folder and moves the files in only once the signature checks out."""
    with tempfile.TemporaryDirectory() as scratch:
        archive = Path(scratch) / "soloist.tar.gz"
        print(f"Downloading {DOWNLOAD}")
        with urllib.request.urlopen(DOWNLOAD, timeout=120) as response, open(archive, "wb") as out:
            shutil.copyfileobj(response, out)
        extracted = Path(scratch) / "x"
        with tarfile.open(archive) as tar:
            names = {"soloist", "THIRD_PARTY_LICENSES.txt", "CHANGELOG.md"}
            members = [m for m in tar.getmembers() if m.isfile() and Path(m.name).name in names]
            for member in members:
                member.name = Path(member.name).name
            tar.extractall(extracted, members=members)
        if not (extracted / "soloist").is_file():
            raise SystemExit("The download holds no soloist binary.")
        verify(extracted / "soloist")
        directory.mkdir(parents=True, exist_ok=True)
        for item in extracted.iterdir():
            target = directory / item.name
            if target.exists():
                target.chmod(0o644)
                target.unlink()
            shutil.move(str(item), target)
        (directory / "soloist").chmod(0o555)


parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=Path("build/soloist/soloist"))
parser.add_argument("--app", type=Path)
parser.add_argument("--fetch", action="store_true", help="download the current build from Spotify first")
args = parser.parse_args()
if args.fetch:
    fetch(args.source.parent)
elif not args.source.is_file():
    raise SystemExit("Missing local Soloist binary. Run `make fetch-soloist`, or see SMALLTIFY.md.")
else:
    verify(args.source)
if args.app:
    destination = args.app / "Contents/Helpers/soloist"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.source, destination)
    destination.chmod(0o755)
    if hashlib.sha256(destination.read_bytes()).digest() != hashlib.sha256(args.source.read_bytes()).digest():
        raise SystemExit("Staged Soloist differs from the verified copy.")
    licenses = args.source.with_name("THIRD_PARTY_LICENSES.txt")
    if licenses.is_file():
        shutil.copy2(licenses, args.app / "Contents/Resources/Soloist-Third-Party-Licenses.txt")
    print("Staged for this Mac only. Do not redistribute this app with the Soloist binary.")
