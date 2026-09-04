#!/usr/bin/env python3
"""Allow CocoaPods path-spec checksum drift while freezing the lock graph.

CocoaPods computes checksums for local/path podspecs from a generated JSON
representation. That representation can differ across Ruby runtimes even when
the podspec and resolved dependency graph are identical. Registry pod
checksums, versions, sources, and every other lockfile field remain immutable.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


CHECKSUM_RE = re.compile(r"^  ([^:]+): ([0-9a-f]{40})$")
ENTRY_RE = re.compile(r"^  ([^:]+):\s*$")
TOP_LEVEL_RE = re.compile(r"^[A-Z][A-Z ]+:(?:\s+.*)?$")


class LockVerificationError(ValueError):
    pass


def read_lines(path: Path) -> list[str]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise LockVerificationError(f"unable to read lockfile: {path}") from error
    if not text.endswith("\n"):
        raise LockVerificationError(f"lockfile must end with a newline: {path}")
    return text.splitlines()


def section(lines: list[str], name: str) -> list[str]:
    marker = f"{name}:"
    try:
        start = lines.index(marker) + 1
    except ValueError as error:
        raise LockVerificationError(f"missing {name} section") from error
    end = len(lines)
    for index in range(start, len(lines)):
        if TOP_LEVEL_RE.fullmatch(lines[index]):
            end = index
            break
    return lines[start:end]


def path_pods(lines: list[str]) -> set[str]:
    result: set[str] = set()
    current: str | None = None
    for line in section(lines, "EXTERNAL SOURCES"):
        entry = ENTRY_RE.fullmatch(line)
        if entry:
            current = entry.group(1)
            continue
        if line.startswith("    :path:"):
            if current is None:
                raise LockVerificationError("path source has no pod name")
            result.add(current)
    if not result:
        raise LockVerificationError("no local path pods found")
    return result


def checksums(lines: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in section(lines, "SPEC CHECKSUMS"):
        if not line:
            continue
        match = CHECKSUM_RE.fullmatch(line)
        if not match:
            raise LockVerificationError("invalid SPEC CHECKSUMS entry")
        name, value = match.groups()
        if name in result:
            raise LockVerificationError(f"duplicate checksum entry: {name}")
        result[name] = value
    if not result:
        raise LockVerificationError("SPEC CHECKSUMS is empty")
    return result


def normalized(lines: list[str], allowed: set[str]) -> list[str]:
    result: list[str] = []
    in_checksums = False
    for line in lines:
        if line == "SPEC CHECKSUMS:":
            in_checksums = True
            result.append(line)
            continue
        if in_checksums and TOP_LEVEL_RE.fullmatch(line):
            in_checksums = False
        if in_checksums:
            match = CHECKSUM_RE.fullmatch(line)
            if match and match.group(1) in allowed:
                continue
        result.append(line)
    return result


def verify(expected_path: Path, actual_path: Path) -> int:
    expected = read_lines(expected_path)
    actual = read_lines(actual_path)
    expected_paths = path_pods(expected)
    actual_paths = path_pods(actual)
    if actual_paths != expected_paths:
        raise LockVerificationError("local path pod set changed")

    expected_checksums = checksums(expected)
    actual_checksums = checksums(actual)
    if actual_checksums.keys() != expected_checksums.keys():
        raise LockVerificationError("pod checksum key set changed")
    missing = expected_paths.difference(expected_checksums)
    if missing:
        raise LockVerificationError("a local path pod has no checksum")

    if normalized(actual, expected_paths) != normalized(expected, expected_paths):
        raise LockVerificationError(
            "locked dependency graph changed outside local path-pod checksums"
        )

    print(
        "IOS_POD_LOCK_PORTABILITY::PASS::"
        f"path_pods={len(expected_paths)}::dependency_graph=EXACT"
    )
    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(
            "usage: verify_ios_pod_lock.py EXPECTED_LOCK ACTUAL_LOCK",
            file=sys.stderr,
        )
        return 64
    try:
        return verify(Path(argv[1]), Path(argv[2]))
    except LockVerificationError as error:
        print(f"IOS_POD_LOCK_PORTABILITY::FAIL::{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
