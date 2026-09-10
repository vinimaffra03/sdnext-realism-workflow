#!/usr/bin/env python3
"""Scale and center an OpenPose map inside a safe full-body frame."""

from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import numpy as np


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=768)
    parser.add_argument("--height-fraction", type=float, default=0.72)
    parser.add_argument("--width-fraction", type=float, default=0.60)
    parser.add_argument("--center-x", type=float, default=0.50)
    parser.add_argument("--center-y", type=float, default=0.50)
    args = parser.parse_args()

    image = cv2.imread(str(args.input), cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError(f"Could not read image: {args.input}")
    source_height, source_width = image.shape[:2]
    width, height = args.width, args.height
    if width < 64 or height < 64:
        raise ValueError("width and height must each be at least 64 pixels")
    if not (0.1 <= args.height_fraction <= 0.95):
        raise ValueError("height-fraction must be between 0.1 and 0.95")
    if not (0.1 <= args.width_fraction <= 0.95):
        raise ValueError("width-fraction must be between 0.1 and 0.95")

    mask = np.max(image, axis=2) > 12
    points = cv2.findNonZero(mask.astype(np.uint8))
    if points is None:
        raise RuntimeError("No OpenPose marks were found.")
    x, y, box_width, box_height = cv2.boundingRect(points)
    crop = image[y : y + box_height, x : x + box_width]

    scale = min(
        (width * args.width_fraction) / box_width,
        (height * args.height_fraction) / box_height,
    )
    target_width = max(1, int(round(box_width * scale)))
    target_height = max(1, int(round(box_height * scale)))
    resized = cv2.resize(crop, (target_width, target_height), interpolation=cv2.INTER_NEAREST)

    canvas = np.zeros((height, width, 3), dtype=image.dtype)
    left = int(round(width * args.center_x - target_width / 2))
    top = int(round(height * args.center_y - target_height / 2))
    left = min(max(left, 0), width - target_width)
    top = min(max(top, 0), height - target_height)
    canvas[top : top + target_height, left : left + target_width] = resized

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(args.output), canvas):
        raise RuntimeError(f"Could not save image: {args.output}")
    print(f"Saved: {args.output.resolve()}")
    print(f"Source bounds: {box_width}x{box_height}; safe bounds: {target_width}x{target_height}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
