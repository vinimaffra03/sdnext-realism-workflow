#!/usr/bin/env python3
"""Apply InsightFace InSwapper to an already rendered image.

This intentionally runs after diffusion so identity transfer cannot compete with
OpenPose or change the scene composition.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import insightface
from insightface.app import FaceAnalysis


def largest_face(faces):
    if not faces:
        raise RuntimeError("No face was detected.")
    return max(faces, key=lambda face: float((face.bbox[2] - face.bbox[0]) * (face.bbox[3] - face.bbox[1])))


def read_image(path: Path):
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError(f"Could not read image: {path}")
    return image


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Authorized fictional identity reference.")
    parser.add_argument("--target", type=Path, required=True, help="Pose-correct rendered image.")
    parser.add_argument("--output", type=Path, required=True, help="Output PNG path.")
    parser.add_argument("--analysis-root", type=Path, required=True, help="Directory containing models/buffalo_l.")
    parser.add_argument("--swapper-model", type=Path, required=True, help="Local inswapper_128.onnx path.")
    parser.add_argument("--det-size", type=int, default=640)
    args = parser.parse_args()

    for path in (args.source, args.target, args.swapper_model):
        if not path.is_file():
            raise FileNotFoundError(path)
    if not (args.analysis_root / "models" / "buffalo_l").is_dir():
        raise FileNotFoundError(args.analysis_root / "models" / "buffalo_l")

    providers = ["CPUExecutionProvider"]
    analyzer = FaceAnalysis(name="buffalo_l", root=str(args.analysis_root), providers=providers)
    analyzer.prepare(ctx_id=-1, det_thresh=0.5, det_size=(args.det_size, args.det_size))
    swapper = insightface.model_zoo.get_model(str(args.swapper_model), providers=providers)

    source = read_image(args.source)
    target = read_image(args.target)
    source_faces = analyzer.get(source)
    target_faces = analyzer.get(target)
    source_face = largest_face(source_faces)
    target_face = largest_face(target_faces)
    result = swapper.get(target, target_face, source_face, paste_back=True)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(args.output), result):
        raise RuntimeError(f"Could not save output: {args.output}")

    print(f"Saved: {args.output.resolve()}")
    print(f"Source faces: {len(source_faces)}; target faces: {len(target_faces)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
