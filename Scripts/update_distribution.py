#!/usr/bin/env python3
"""Update Ahoge's SideStore source and latest-release manifest from CI metadata."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def semver_key(value: str) -> tuple[int, int, int]:
    pieces = value.split(".")
    if len(pieces) != 3 or not all(piece.isdigit() for piece in pieces):
        raise ValueError(f"Expected semantic version MAJOR.MINOR.PATCH, got {value!r}")
    return tuple(int(piece) for piece in pieces)  # type: ignore[return-value]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--latest", required=True, type=Path)
    parser.add_argument("--metadata", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--notes", required=True, type=Path)
    args = parser.parse_args()

    source = read_json(args.source)
    metadata = read_json(args.metadata)
    manifest = read_json(args.manifest)
    notes = args.notes.read_text(encoding="utf-8").strip()

    apps = source.get("apps")
    if not isinstance(apps, list) or len(apps) != 1 or not isinstance(apps[0], dict):
        raise ValueError("Ahoge source must contain exactly one app object")
    app = apps[0]

    if app.get("bundleIdentifier") != metadata.get("bundleIdentifier"):
        raise ValueError("Release bundle identifier does not match Distribution/source.json")

    version = str(metadata["version"])
    semver_key(version)

    # SideStore's current Version schema is strict (additionalProperties=false).
    # Build number and checksum therefore live in latest.json/release metadata,
    # while the public source contains only supported Version properties.
    new_version: dict[str, Any] = {
        "version": version,
        "date": str(metadata["releaseDate"]),
        "localizedDescription": notes or f"Ahoge {version}",
        "downloadURL": str(metadata["downloadURL"]),
        "size": int(metadata["size"]),
        "minOSVersion": str(metadata["minimumOSVersion"]),
    }

    versions = app.get("versions", [])
    if not isinstance(versions, list):
        raise ValueError("apps[0].versions must be an array")

    retained: list[dict[str, Any]] = []
    for item in versions:
        if not isinstance(item, dict):
            raise ValueError("Every version entry must be an object")
        if str(item.get("version")) != version:
            retained.append(item)

    retained.append(new_version)
    retained.sort(key=lambda item: semver_key(str(item["version"])), reverse=True)
    app["versions"] = retained

    source["sourceURL"] = "https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/source.json"
    manifest["sourceURL"] = source["sourceURL"]
    manifest["releaseNotes"] = notes or f"Ahoge {version}"

    args.source.write_text(json.dumps(source, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    args.latest.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
