import argparse
import copy
import json
import time
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Expand Antonov config subjects (users).")
    p.add_argument(
        "--config",
        default="config_antonov_2025.json",
        help="Path to config JSON (default: config_antonov_2025.json)",
    )
    p.add_argument(
        "--max-user-id",
        type=int,
        default=1057,
        help="Max user id to support (user-N => N). Default: 1057",
    )
    p.add_argument(
        "--template-index",
        type=int,
        default=0,
        help="Which existing subject entry to clone for new users (0-based). Default: 0",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    path = Path(args.config)
    cfg = json.loads(path.read_text(encoding="utf-8"))

    subjects = cfg.get("subjects")
    if not isinstance(subjects, list) or len(subjects) == 0:
        raise SystemExit('Config must contain non-empty list field "subjects".')

    if args.template_index < 0 or args.template_index >= len(subjects):
        raise SystemExit("--template-index out of range for existing subjects list.")

    desired_len = int(args.max_user_id)
    if desired_len <= 0:
        raise SystemExit("--max-user-id must be > 0")

    if len(subjects) >= desired_len:
        print(f'No change: subjects already has {len(subjects)} entries (>= {desired_len}).')
        return

    template = subjects[args.template_index]
    while len(subjects) < desired_len:
        subjects.append(copy.deepcopy(template))

    cfg["subjects"] = subjects

    backup = path.with_suffix(path.suffix + f".bak.{int(time.time())}")
    backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    path.write_text(json.dumps(cfg, indent=4), encoding="utf-8")

    print(f"Wrote updated config: {path}")
    print(f"Backup saved as:    {backup}")
    print(f"subjects length:    {len(subjects)}")


if __name__ == "__main__":
    main()

