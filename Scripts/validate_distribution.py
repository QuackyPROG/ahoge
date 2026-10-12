#!/usr/bin/env python3
"""Validate Ahoge's SideStore source and in-app release manifest."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
VERSION_FIELDS = {
    "version",
    "date",
    "downloadURL",
    "size",
    "localizedDescription",
    "minOSVersion",
    "maxOSVersion",
}


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as error:
        raise SystemExit(f"{path}: invalid JSON: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"{path}: top-level value must be an object")
    return value


def require_https(value: Any, label: str) -> None:
    parsed = urlparse(str(value))
    if parsed.scheme != "https" or not parsed.netloc:
        raise SystemExit(f"{label} must be an absolute HTTPS URL")


def semver_key(value: str) -> tuple[int, int, int]:
    if not SEMVER.fullmatch(value):
        raise SystemExit(f"Invalid semantic version: {value}")
    major, minor, patch = value.split(".")
    return int(major), int(minor), int(patch)


def validate_source(source: dict[str, Any]) -> tuple[str, str | None]:
    for key in ("name", "identifier", "apps"):
        if key not in source:
            raise SystemExit(f"Distribution/source.json is missing {key}")

    require_https(source.get("sourceURL"), "sourceURL")
    apps = source["apps"]
    if not isinstance(apps, list) or len(apps) != 1 or not isinstance(apps[0], dict):
        raise SystemExit("Distribution/source.json must contain exactly one app")

    app = apps[0]
    for key in ("name", "bundleIdentifier", "developerName", "localizedDescription", "iconURL", "versions"):
        if key not in app:
            raise SystemExit(f"Ahoge app entry is missing {key}")
    require_https(app["iconURL"], "iconURL")

    versions = app["versions"]
    if not isinstance(versions, list):
        raise SystemExit("versions must be an array")

    seen: set[str] = set()
    previous_key: tuple[int, int, int] | None = None
    for index, version in enumerate(versions):
        if not isinstance(version, dict):
            raise SystemExit(f"versions[{index}] must be an object")

        unsupported = set(version) - VERSION_FIELDS
        if unsupported:
            raise SystemExit(
                f"versions[{index}] contains fields rejected by the current SideStore schema: "
                + ", ".join(sorted(unsupported))
            )

        for key in ("version", "date", "downloadURL", "size"):
            if key not in version:
                raise SystemExit(f"versions[{index}] is missing {key}")

        version_name = str(version["version"])
        current_key = semver_key(version_name)
        if previous_key is not None and current_key > previous_key:
            raise SystemExit("versions must be newest-first")
        previous_key = current_key

        if version_name in seen:
            raise SystemExit(f"Duplicate version entry: {version_name}")
        seen.add(version_name)

        require_https(version["downloadURL"], f"versions[{index}].downloadURL")
        if int(version["size"]) <= 0:
            raise SystemExit(f"versions[{index}].size must be greater than zero")
        if "minOSVersion" in version and not str(version["minOSVersion"]).strip():
            raise SystemExit(f"versions[{index}].minOSVersion must not be empty")
        if "maxOSVersion" in version and not str(version["maxOSVersion"]).strip():
            raise SystemExit(f"versions[{index}].maxOSVersion must not be empty")

    if not versions:
        return str(app["bundleIdentifier"]), None
    return str(app["bundleIdentifier"]), str(versions[0]["version"])


def validate_latest(latest: dict[str, Any], source_url: str, source_version: str | None) -> None:
    if latest.get("available") is False:
        return
    if latest.get("available") is not True:
        raise SystemExit("Distribution/latest.json available must be true or false")

    for key in (
        "version",
        "build",
        "minimumOSVersion",
        "releaseDate",
        "downloadURL",
        "sha256",
        "releaseNotesURL",
        "size",
        "sourceURL",
    ):
        if key not in latest:
            raise SystemExit(f"Distribution/latest.json is missing {key}")

    semver_key(str(latest["version"]))
    if not str(latest["build"]).isdigit() or int(str(latest["build"])) < 1:
        raise SystemExit("latest.build must be a positive integer")
    require_https(latest["downloadURL"], "latest.downloadURL")
    require_https(latest["releaseNotesURL"], "latest.releaseNotesURL")
    require_https(latest["sourceURL"], "latest.sourceURL")
    if str(latest["sourceURL"]) != source_url:
        raise SystemExit("latest.sourceURL must match Distribution/source.json sourceURL")
    if not SHA256.fullmatch(str(latest["sha256"])):
        raise SystemExit("latest.sha256 must be 64 lowercase hex characters")
    if int(latest["size"]) <= 0:
        raise SystemExit("latest.size must be greater than zero")
    if source_version is not None and str(latest["version"]) != source_version:
        raise SystemExit("latest.version does not match the first SideStore version")


def main() -> None:
    if len(sys.argv) not in (2, 3):
        raise SystemExit("usage: validate_distribution.py SOURCE_JSON [LATEST_JSON]")

    source_path = Path(sys.argv[1])
    source = load(source_path)
    _, version = validate_source(source)

    if len(sys.argv) == 3:
        latest = load(Path(sys.argv[2]))
        validate_latest(latest, str(source["sourceURL"]), version)

    print("Distribution metadata is valid.")


if __name__ == "__main__":
    main()
