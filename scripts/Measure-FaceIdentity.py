#!/usr/bin/env python3
"""Measure face-embedding similarity against an authorized reference image."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import cv2
import numpy as np
from insightface.app import FaceAnalysis


def read_image(path: Path):
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError(f"Could not read image: {path}")
    return image


def largest_face(faces):
    if not faces:
        return None
    return max(
        faces,
        key=lambda face: float(
            (face.bbox[2] - face.bbox[0]) * (face.bbox[3] - face.bbox[1])
        ),
    )


def cosine_similarity(left: np.ndarray, right: np.ndarray) -> float:
    denominator = float(np.linalg.norm(left) * np.linalg.norm(right))
    if denominator == 0:
        raise RuntimeError("A face embedding had zero magnitude.")
    return float(np.dot(left, right) / denominator)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--targets", type=Path, nargs="+", required=True)
    parser.add_argument("--analysis-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--det-size", type=int, default=640)
    args = parser.parse_args()

    if not args.reference.is_file():
        raise FileNotFoundError(args.reference)
    if not (args.analysis_root / "models" / "buffalo_l").is_dir():
        raise FileNotFoundError(args.analysis_root / "models" / "buffalo_l")

    analyzer = FaceAnalysis(
        name="buffalo_l",
        root=str(args.analysis_root),
        providers=["CPUExecutionProvider"],
    )
    analyzer.prepare(ctx_id=-1, det_thresh=0.5, det_size=(args.det_size, args.det_size))

    reference_face = largest_face(analyzer.get(read_image(args.reference)))
    if reference_face is None:
        raise RuntimeError(f"No face was detected in reference: {args.reference}")

    rows: list[dict[str, str]] = []
    for target in args.targets:
        if not target.is_file():
            rows.append(
                {
                    "file": target.name,
                    "face_detected": "false",
                    "detection_score": "",
                    "cosine_similarity": "",
                    "error": "file not found",
                }
            )
            continue

        try:
            face = largest_face(analyzer.get(read_image(target)))
            if face is None:
                raise RuntimeError("no face detected")
            similarity = cosine_similarity(reference_face.normed_embedding, face.normed_embedding)
            rows.append(
                {
                    "file": target.name,
                    "face_detected": "true",
                    "detection_score": f"{float(face.det_score):.6f}",
                    "cosine_similarity": f"{similarity:.6f}",
                    "error": "",
                }
            )
        except Exception as exc:  # Keep batch evaluation resumable.
            rows.append(
                {
                    "file": target.name,
                    "face_detected": "false",
                    "detection_score": "",
                    "cosine_similarity": "",
                    "error": str(exc),
                }
            )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "file",
                "face_detected",
                "detection_score",
                "cosine_similarity",
                "error",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"Saved: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
