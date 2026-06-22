import argparse
import json
import random
import re
import time
from pathlib import Path


PERMISSIONS = ["R", "A", "D", "E", "P"]
SCAS = ["AAL-1", "AAL-2", "AAL-3"]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=(
            "Add random ACL entries to Antonov config while preventing "
            "cross-user access to User_* PC objects."
        )
    )
    p.add_argument(
        "--config",
        default="config_antonov_2025.json",
        help="Path to config JSON (default: config_antonov_2025.json)",
    )
    p.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Random seed (optional, for reproducibility)",
    )
    p.add_argument(
        "--entries-per-user",
        type=int,
        default=3,
        help="How many random (user,object) ACL entries to add per user (default: 3)",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    if args.seed is not None:
        random.seed(args.seed)
    else:
        random.seed()

    path = Path(args.config)
    cfg = json.loads(path.read_text(encoding="utf-8"))

    subjects = cfg.get("subjects", [])
    objects = cfg.get("objects", [])
    if not isinstance(subjects, list) or not isinstance(objects, list):
        raise SystemExit('Config must contain "subjects" and "objects" arrays.')
    n_users = len(subjects)
    n_objects = len(objects)

    acl = cfg.get("ACL")
    if not isinstance(acl, dict):
        acl = {}
        cfg["ACL"] = acl

    # Identify "PC objects" (User_* in objects list) and who is allowed.
    # Example: Name = "User_3" => only user index 3 can have ACL entries to that object index.
    pc_object_allowed_user = {}  # object_index (1-based) -> allowed_user_index (1-based)
    for idx, obj in enumerate(objects, start=1):
        name = str(obj.get("Name", "")).strip()
        # Common naming variants in configs: "User_1", "User_1 PC"
        m = re.match(r"^User_(\d+)(?:\s+PC)?$", name, flags=re.IGNORECASE)
        if m:
            pc_object_allowed_user[idx] = int(m.group(1))

    # Non-PC objects are safe for random ACL generation
    non_pc_object_indices = [i for i in range(1, n_objects + 1) if i not in pc_object_allowed_user]

    # Ensure owners have at least one ACL entry to their own PC object (keep existing, add if missing)
    for obj_idx, owner_user in pc_object_allowed_user.items():
        key = f"{owner_user},{obj_idx}"
        if key not in acl:
            acl[key] = {"Permission": "P", "SCA": "AAL-3"}

    # Add random ACLs: for each user, pick a few non-PC objects
    entries_per_user = max(0, int(args.entries_per_user))
    for user_idx in range(1, n_users + 1):
        if not non_pc_object_indices or entries_per_user == 0:
            continue
        chosen_objs = random.sample(
            non_pc_object_indices, k=min(entries_per_user, len(non_pc_object_indices))
        )
        for obj_idx in chosen_objs:
            key = f"{user_idx},{obj_idx}"
            if key in acl:
                continue  # don't overwrite existing
            acl[key] = {"Permission": random.choice(PERMISSIONS), "SCA": random.choice(SCAS)}

    # Safety: remove any cross-user ACLs that point to a User_* object
    # (e.g., "2,1" where object 1 is User_1) unless user==owner.
    keys_to_delete = []
    for k in acl.keys():
        try:
            u_str, o_str = k.split(",", 1)
            u = int(u_str)
            o = int(o_str)
        except Exception:
            continue
        owner = pc_object_allowed_user.get(o)
        if owner is not None and u != owner:
            keys_to_delete.append(k)
    for k in keys_to_delete:
        del acl[k]

    backup = path.with_suffix(path.suffix + f".bak.{int(time.time())}")
    backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    path.write_text(json.dumps(cfg, indent=4), encoding="utf-8")

    print(f"Wrote updated config: {path}")
    print(f"Backup saved as:    {backup}")
    print(f"ACL entries:        {len(acl)}")
    print(f"Users:              {n_users}")
    print(f"Objects:            {n_objects}")
    print(f"PC objects:         {pc_object_allowed_user}")


if __name__ == "__main__":
    main()

