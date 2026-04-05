#!/usr/bin/env python3
import argparse
from pathlib import Path

from huggingface_hub import snapshot_download


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--pattern", action="append", default=[])
    parser.add_argument("--local-dir", required=True)
    parser.add_argument("--revision", default="main")
    parser.add_argument("--token", default="")
    args = parser.parse_args()

    allow_patterns: list[str] = []
    for raw_pattern in args.pattern:
        for value in raw_pattern.split(","):
            value = value.strip()
            if value:
                allow_patterns.append(value)

    local_dir = Path(args.local_dir)
    local_dir.mkdir(parents=True, exist_ok=True)

    snapshot_download(
        repo_id=args.repo,
        revision=args.revision,
        local_dir=str(local_dir),
        allow_patterns=allow_patterns or None,
        token=args.token or None,
    )

    print(str(local_dir))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
