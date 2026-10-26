"""Generate RAM init files and testbench vectors from the test images.

The image RAM is four 16 x 64 banks interleaved by row: bank k holds image rows k, k+4, ...,
k+60 at addresses 0..15 (see IPs/Convolution/RAM_IP_src/RAM_IP_TOP.sv). Each 64-bit word is
one image row with column c in bit c, i.e. column 0 is the LSB / rightmost character of the
binary string. That is how the reference IPs read it (verified in simulation).
matlab_model/coe_script_matlab.m writes column 0 in the MSB instead, which makes the hardware
classify the image mirrored left-right.

Usage:
    uv run python tools/make_vectors.py coe 19 build/coe/img_00019
    uv run python tools/make_vectors.py tb 1-10,31 build/vectors
"""
import argparse
from pathlib import Path

import numpy as np

import cnn_golden as g

BANKS = 4


def row_bits(row: np.ndarray) -> str:
    """Binary string of one image row, MSB (column 63) first."""
    return "".join(str(int(b)) for b in row[::-1])


def write_bank_coes(img: np.ndarray, out_dir: Path) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for k in range(BANKS):
        words = [row_bits(r) for r in img[k::BANKS]]
        path = out_dir / f"bank{k}.coe"
        path.write_text("memory_initialization_radix = 2;\n"
                        "memory_initialization_vector =\n" + ",\n".join(words) + ";\n")
        paths.append(path)
    return paths


def write_tb_vectors(ids: list[int], out_dir: Path, cv: g.Convention = g.HW) -> None:
    """images.mem: 64 rows per image for $readmemb.
    expected.txt: one line per image: id label class fc2 pool[0..15] (row-major tiles)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    labels = g.load_labels()
    mem, exp = [], []
    for i in ids:
        img = g.load_image(i)
        s = g.run(img, cv)
        mem.append(f"// image {i}")
        mem.extend(row_bits(r) for r in img)
        exp.append(" ".join(map(str, [i, labels[i - 1], s.cls, s.fc2, *s.pool.flatten()])))
    (out_dir / "images.mem").write_text("\n".join(mem) + "\n")
    (out_dir / "expected.txt").write_text("\n".join(exp) + "\n")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    coe = sub.add_parser("coe", help="four bank .coe files for one image")
    coe.add_argument("image", type=int)
    coe.add_argument("out_dir", type=Path)
    tb = sub.add_parser("tb", help="testbench stimulus + expected results")
    tb.add_argument("images", help="e.g. 1-10,31")
    tb.add_argument("out_dir", type=Path)
    args = ap.parse_args()

    if args.cmd == "coe":
        for p in write_bank_coes(g.load_image(args.image), args.out_dir):
            print(p)
    else:
        ids = g.parse_ids(args.images)
        write_tb_vectors(ids, args.out_dir)
        print(f"{len(ids)} images -> {args.out_dir}")


if __name__ == "__main__":
    main()
