"""Bit-accurate integer golden model of the lab CNN (circle = 0, square = 1).

Weights are the 4-bit signed values streamed by top/top_initialize.sv (row-major), which are
the same as in matlab_model/. Biases are not streamed by the hardware; they come from
matlab_model/fully_connect.m.

Checked against the reference IPs in simulation (tools/run_sim.py), with the image stored as
in make_vectors.py (column c in RAM word bit c):
- conv (HW convention): sliding window without kernel flip, row-major scan, sum saturated to
  4-bit signed, then ReLU. Bit-exact with the reference conv stream.
- pooling: 15x15 tiles, stride 15, conv row/col 61 dropped, row-major tile order. Bit-exact.
- FC: exact arithmetic here. The reference FC_TOP is lossy (its FC1 -> FC2 path is narrower
  than the sums need): it disagrees on ~8% of random pooled vectors, always answering
  "square", and scores 95.4% on the test images against 96.7% for this model.
matlab_model/ itself is not bit-exact: xcorr2(filter, image) returns the conv map rotated
180 degrees (Convention MATLAB below).

Usage:
    uv run python tools/cnn_golden.py accuracy
    uv run python tools/cnn_golden.py show 31
"""
import argparse
from dataclasses import dataclass
from functools import cache
from pathlib import Path

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
IMAGE_DIR = ROOT / "Images"
NUM_IMAGES = 1000

CONV_W = np.array([
    [-3, -1,  1, -1],
    [ 2, -2,  0,  0],
    [ 0,  3,  0, -3],
    [-1, -2, -2,  4],
])
CONV_B = 0
FC1_W = np.array([
    [[2,  2,  2,  5], [ 3,  4,  6,  5], [3,  5,  3,  3], [3,  4,  2,  2]],
    [[2, -6,  2, -2], [-3,  1, -2, -5], [0, -2, -1, -3], [0, -2, -2,  3]],
    [[0,  3, -1, -3], [ 3, -8,  1, -4], [0, -2, -6, -3], [0, -2,  1, -3]],
])
FC1_B = np.array([-12, 20, 24])
FC2_W = np.array([-8, 7, 7])
FC2_B = 6

CONV_OUT = 61   # 64 - 4 + 1
TILE = 15       # max-pool window and stride
TILES = 4       # 4 x 4 pooled map; row/col 61 of the conv map is not covered


@dataclass(frozen=True)
class Convention:
    """How the hardware maps the maths onto the image."""
    matlab_rot180: bool = False     # reproduce xcorr2(filter, image) in matlab_model/convolve.m
    acc_bits: int | None = 4        # width the conv sum is narrowed to; None = no narrowing
    acc_overflow: str = "saturate"  # "saturate" or "wrap" when narrowing


HW = Convention()
MATLAB = Convention(matlab_rot180=True, acc_bits=None)
HW_WRAP = Convention(acc_overflow="wrap")


@dataclass
class Stages:
    conv_raw: np.ndarray    # 61x61 full-precision conv sum (+ bias)
    conv_acc: np.ndarray    # 61x61 after narrowing to the accumulator width (pre-ReLU)
    relu: np.ndarray        # 61x61
    pool: np.ndarray        # 4x4, row-major tile order
    fc1: np.ndarray         # 3, before ReLU
    fc2: int
    cls: int                # 1 = square, 0 = circle


def parse_ids(spec: str) -> list[int]:
    """'1-10,31,35' -> [1, ..., 10, 31, 35] (1-based image numbers)."""
    ids = []
    for part in spec.split(","):
        lo, _, hi = part.strip().partition("-")
        ids.extend(range(int(lo), int(hi or lo) + 1))
    return ids


def load_image(img_id: int) -> np.ndarray:
    return np.array(Image.open(IMAGE_DIR / "imgTst" / f"img_{img_id:05d}.png"), dtype=np.int64)


@cache
def load_labels() -> np.ndarray:
    """Index i holds the label of image i + 1."""
    lines = (IMAGE_DIR / "Tst_trg.csv").read_text().split("\n")
    return np.array([int(line.split()[0]) for line in lines if line.strip()])


def narrow(x: np.ndarray, bits: int | None, mode: str) -> np.ndarray:
    if bits is None:
        return x
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if mode == "saturate":
        return np.clip(x, lo, hi)
    if mode == "wrap":
        return (x - lo) % (1 << bits) + lo
    raise ValueError(f"unknown overflow mode {mode!r}")


def conv_raw(img: np.ndarray, cv: Convention = HW) -> np.ndarray:
    """out[r, c] = sum_ij w[i, j] * img[r + i, c + j] + bias  (sliding window, no flip)."""
    out = np.einsum("rcij,ij->rc", sliding_window_view(img, (4, 4)), CONV_W) + CONV_B
    return np.rot90(out, 2) if cv.matlab_rot180 else out


def fc(pool: np.ndarray) -> tuple[np.ndarray, int, int]:
    """4x4 pooled map -> (FC1 before ReLU, FC2, class)."""
    fc1 = np.einsum("kij,ij->k", FC1_W, pool) + FC1_B
    fc2 = int(np.maximum(fc1, 0) @ FC2_W + FC2_B)
    return fc1, fc2, int(fc2 > 0)


def run(img: np.ndarray, cv: Convention = HW) -> Stages:
    raw = conv_raw(img, cv)
    acc = narrow(raw, cv.acc_bits, cv.acc_overflow)
    relu = np.maximum(acc, 0)
    covered = relu[:TILES * TILE, :TILES * TILE]
    pool = covered.reshape(TILES, TILE, TILES, TILE).max(axis=(1, 3))
    return Stages(raw, acc, relu, pool, *fc(pool))


def accuracy(cv: Convention, ids: list[int]) -> float:
    labels = load_labels()
    return float(np.mean([run(load_image(i), cv).cls == labels[i - 1] for i in ids]))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("accuracy", help="accuracy of each convention on all 1000 test images")
    show = sub.add_parser("show", help="print every stage for one image")
    show.add_argument("image", type=int)
    args = ap.parse_args()

    if args.cmd == "accuracy":
        ids = list(range(1, NUM_IMAGES + 1))
        for name, cv in [("HW (sliding window, saturate)", HW),
                         ("HW, 4-bit wrap-around", HW_WRAP),
                         ("MATLAB as written", MATLAB)]:
            print(f"{name:32s} {accuracy(cv, ids):.1%}")
    else:
        s = run(load_image(args.image))
        label = load_labels()[args.image - 1]
        print(f"image {args.image}: label {label}, conv raw range [{s.conv_raw.min()}, {s.conv_raw.max()}]")
        print("pool (row-major):\n", s.pool)
        print("fc1 (pre-ReLU):", s.fc1.tolist(), " fc2:", s.fc2, " class:", s.cls)


if __name__ == "__main__":
    main()
