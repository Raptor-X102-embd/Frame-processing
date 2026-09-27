#!/usr/bin/env python3
"""
invert_raw.py — Creates a bitwise-inverted copy of a raw RGB file.

For every byte b in the input, writes (255 - b) to the output.
That is: R' = 255 - R, G' = 255 - G, B' = 255 - B.

Usage:
    python invert_raw.py input.raw
    python invert_raw.py input.raw -o inverted.raw
"""

import argparse
import sys
from pathlib import Path


def invert_raw(input_path: Path, output_path: Path | None = None) -> None:
    data = input_path.read_bytes()

    if len(data) % 3 != 0:
        print(f"WARNING: file size {len(data)} is not a multiple of 3 — "
              f"it may not be an RGB stream.")

    # 255 - b for each byte
    inverted = bytes(255 - b for b in data)

    if output_path is None:
        output_path = input_path.with_name(input_path.stem + "_inv.raw")

    output_path.write_bytes(inverted)

    print(f"Input:   {input_path}  ({len(data)} bytes, {len(data)//3} pixels)")
    print(f"Output:  {output_path}  ({len(inverted)} bytes)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Invert (255 - x) every byte of a raw RGB file."
    )
    parser.add_argument("input", type=Path, help="Path to input .raw file")
    parser.add_argument("-o", "--output", type=Path, default=None,
                        help="Output .raw path (default: <input>_inv.raw)")
    args = parser.parse_args()

    if not args.input.is_file():
        sys.exit(f"Error: file not found — {args.input}")

    invert_raw(args.input, args.output)


if __name__ == "__main__":
    main()
