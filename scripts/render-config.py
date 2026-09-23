#!/usr/bin/env python3
"""Render repository configuration templates using local or runtime secrets."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import sys

TOKEN = re.compile(r"\{\{([A-Z][A-Z0-9_]*)\}\}")


def read_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"{path}:{line_number}: expected NAME=value")
        name, value = line.split("=", 1)
        name, value = name.strip(), value.strip()
        if not re.fullmatch(r"[A-Z][A-Z0-9_]*", name):
            raise ValueError(f"{path}:{line_number}: invalid variable name")
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[name] = value
    return values


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--env-file", type=Path, default=Path(".env"))
    parser.add_argument("--secret-dir", type=Path, default=Path("/etc/minecraft/secrets"))
    args = parser.parse_args()

    try:
        values = read_env_file(args.env_file)
        values.update(os.environ)
        template = args.source.read_text(encoding="utf-8")

        def substitute(match: re.Match[str]) -> str:
            name = match.group(1)
            if name in values:
                value = values[name]
            else:
                secret_path = args.secret_dir / name.lower()
                try:
                    value = secret_path.read_text(encoding="utf-8")
                except FileNotFoundError:
                    raise ValueError(f"missing secret {name}: set environment variable or provide {secret_path}") from None
            if not value or "\n" in value or "\r" in value:
                raise ValueError(f"secret {name} is empty or contains a newline")
            if args.source.suffix.lower() in {".yml", ".yaml"}:
                value = value.replace("'", "''")
            return value

        rendered = TOKEN.sub(substitute, template)
        unresolved = TOKEN.findall(rendered)
        if unresolved:
            raise ValueError(f"unresolved template markers: {', '.join(sorted(set(unresolved)))}")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(rendered)
    except (OSError, ValueError) as error:
        print(f"render-config: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
