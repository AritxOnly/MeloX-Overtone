"""Archive Overtone with three installed App Store Connect provisioning profiles."""

import argparse
from fnmatch import fnmatchcase
from pathlib import Path
import plistlib
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
APP_ID = "top.aritxonly.overtone"
WIDGET_SUFFIX = "lyricswidget"
PROFILE_SETTINGS = {
    APP_ID: "OVERTONE_APP_PROFILE",
    f"{APP_ID}.{WIDGET_SUFFIX}": "OVERTONE_WIDGET_PROFILE",
    f"{APP_ID}.watchkitapp": "OVERTONE_WATCH_PROFILE",
}


def signing_settings(paths):
    profiles = {}
    teams = set()
    for path in paths:
        decoded = subprocess.check_output(["security", "cms", "-D", "-i", str(path)])
        profile = plistlib.loads(decoded)
        entitlements = profile["Entitlements"]
        bundle_id = entitlements["application-identifier"].partition(".")[2]
        if bundle_id not in PROFILE_SETTINGS or bundle_id in profiles:
            raise ValueError(f"{path.name}: unexpected or duplicate Bundle ID {bundle_id}")
        if ("ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices")
                or entitlements.get("get-task-allow")):
            raise ValueError(f"{path.name}: an App Store Connect distribution profile is required")
        if bundle_id in (APP_ID, f"{APP_ID}.{WIDGET_SUFFIX}"):
            group = f"group.{APP_ID}"
            allowed_groups = entitlements.get("com.apple.security.application-groups", [])
            if not any(fnmatchcase(group, allowed) for allowed in allowed_groups):
                raise ValueError(f"{path.name}: the profile must allow App Group {group}")
        teams.add(profile["TeamIdentifier"][0])
        profiles[bundle_id] = profile["UUID"]

    if profiles.keys() != PROFILE_SETTINGS.keys() or len(teams) != 1:
        raise ValueError("Supply one profile each for the app, widget and Watch from the same team")

    return [
        f"DEVELOPMENT_TEAM={teams.pop()}",
        f"OVERTONE_BASE_BUNDLE_ID={APP_ID}",
        f"OVERTONE_WIDGET_SUFFIX={WIDGET_SUFFIX}",
        *(f"{setting}={profiles[bundle_id]}" for bundle_id, setting in PROFILE_SETTINGS.items()),
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profiles", type=Path, nargs=3, metavar="PROFILE",
                        help="Installed .mobileprovision files in any order")
    parser.add_argument("--archive-path", type=Path,
                        help="Optional .xcarchive destination (default: Xcode Organizer)")
    args = parser.parse_args()
    try:
        settings = signing_settings(args.profiles)
    except (OSError, subprocess.CalledProcessError, plistlib.InvalidFileException,
            ValueError, KeyError, IndexError) as error:
        parser.exit(2, f"Provisioning error: {error}\n")

    command = [
        "xcodebuild", "archive", "-project", "MeloX.xcodeproj", "-scheme", "MeloX",
        "-configuration", "Release", "-destination", "generic/platform=iOS",
        "CODE_SIGN_STYLE=Manual", "CODE_SIGN_IDENTITY=Apple Distribution",
        "CODE_SIGNING_ALLOWED=YES", "CODE_SIGNING_REQUIRED=YES", *settings,
    ]
    if args.archive_path:
        command.extend(["-archivePath", str(args.archive_path.resolve())])
    return subprocess.run(command, cwd=ROOT).returncode


if __name__ == "__main__":
    sys.exit(main())
