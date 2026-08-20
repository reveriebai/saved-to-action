#!/usr/bin/env python3
"""Fail when repository files contain personal source artifacts or build output."""

from __future__ import annotations

import re
import sys
from pathlib import Path


BANNED_PATTERNS = [
    re.compile(r"/Users/[A-Za-z0-9._-]+"),
    re.compile(r"\bautomation-\d+\b"),
    re.compile(r"\b191\d{16}\b"),
]
URL_PATTERN = re.compile(r"https?://([^/\s\"'<>]+)")
ALLOWED_URL_HOSTS = {
    "www.apple.com",
    "github.com",
    "ima.qq.com",
    "mp.weixin.qq.com",
    "biji.com",
    "www.biji.com",
}
SKIP_PARTS = {".git", ".build", "dist", "__pycache__"}
BINARY_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".app", ".swiftmodule", ".pcm"}


def scan(root: Path) -> list[str]:
    findings: list[str] = []
    for path in root.rglob("*"):
        if not path.is_file() or any(part in SKIP_PARTS for part in path.parts):
            continue
        if path.suffix.lower() in BINARY_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for pattern in BANNED_PATTERNS:
            if pattern.search(text):
                findings.append(f"{path}: banned personal identifier or absolute path")
        for host in URL_PATTERN.findall(text):
            if host.lower() not in ALLOWED_URL_HOSTS:
                findings.append(f"{path}: unapproved URL host {host}")
    return findings


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    findings = scan(root)
    if findings:
        print("\n".join(findings), file=sys.stderr)
        return 1
    print("Privacy scan passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
