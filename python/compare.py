#!/usr/bin/env python3
"""
compare_inv.py — Checks whether <actual.raw> is the exact bitwise inversion
(255 - x per byte) of <reference.raw>.

Usage:
    python compare_inv.py reference.raw actual.raw

Exit code:
    0 — exact inversion (every byte matches 255 - ref)
    1 — mismatch (details printed)
    2 — I/O or size error
"""

import sys
from pathlib import Path


def load(path: Path) -> bytes:
    if not path.is_file():
        sys.exit(f"Error: file not found — {path}")
    return path.read_bytes()


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: python compare_inv.py <reference.raw> <actual.raw>")
        sys.exit(2)

    ref_path = Path(sys.argv[1])
    act_path = Path(sys.argv[2])

    ref = load(ref_path)
    act = load(act_path)

    if len(ref) != len(act):
        print(f"FAIL: size mismatch — reference={len(ref)} bytes, actual={len(act)} bytes")
        sys.exit(2)

    total = len(ref)
    mismatches = 0
    first_bad = None
    max_abs_diff = 0

    for i in range(total):
        expected = ref[i]
        got = act[i]
        if expected != got:
            mismatches += 1
            if first_bad is None:
                first_bad = (i, ref[i], expected, got)
            d = abs(expected - got)
            if d > max_abs_diff:
                max_abs_diff = d

    if mismatches == 0:
        print(f"OK: '{act_path.name}' is an EXACT inversion of '{ref_path.name}'")
        print(f"    {total} bytes ({total // 3} pixels) verified.")
        sys.exit(0)

    print(f"FAIL: '{act_path.name}' is NOT an exact inversion of '{ref_path.name}'")
    print(f"    total bytes     : {total}")
    print(f"    mismatched bytes: {mismatches}  ({100.0 * mismatches / total:.4f}%)")
    print(f"    max |Δ|         : {max_abs_diff}")

    if first_bad is not None:
        idx, ref_b, exp_b, got_b = first_bad
        px = idx // 3
        ch = "RGB"[idx % 3]
        print(f"    first mismatch  : byte {idx} (pixel {px}, channel {ch})")
        print(f"                      reference=0x{ref_b:02X}  expected=0x{exp_b:02X}  actual=0x{got_b:02X}")

    sys.exit(1)


if __name__ == "__main__":
    main()
