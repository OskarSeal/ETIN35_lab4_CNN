"""Build and run a testbench in xsim, then compare the results with the golden model.

Benches:
    cnn   sim/tb_cnn.sv:  whole design (top.sv) on test images; checks conv stream, pooling, class
    fc    sim/tb_fc.sv:   FC_TOP alone on pooled vectors (from test images and/or random)
    fpga  sim/tb_fpga.sv: board top (fpga_top), own layers; images 1-256 selected by the
          switches from the image ROM (vivado/board/), checks the load and the LEDs

Each layer (conv, pool, fc) uses the reference netlist unless listed in --own, in which case
the own RTL in rtl/ is compiled instead (same module name and ports).

Usage:
    uv run python tools/run_sim.py cnn 1-10,31
    uv run python tools/run_sim.py cnn 1-10,31 --own conv,pool
    uv run python tools/run_sim.py fc 1-1000 --random 2000
    uv run python tools/run_sim.py cnn 1-1000 --no-build   # reuse the last snapshot
    uv run python tools/run_sim.py fpga 1,3,31,59,255,256

Vivado is taken from $VIVADO_BIN (default D:\\Program\\2026.1\\Vivado\\bin). The RAM IPs must
exist in vivado/ip/ (vivado/create_dist_mem.tcl). Each bench / layer combination runs in its
own directory, e.g. build/sim/cnn or build/sim/cnn-own-conv-pool.
"""
import argparse
import itertools
import os
import shutil
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

import cnn_golden as g
import make_vectors

ROOT = g.ROOT
VIVADO_BIN = Path(os.environ.get("VIVADO_BIN", r"D:\Program\2026.1\Vivado\bin"))
IP_DIR = ROOT / "vivado" / "ip"
BOARD_DIR = ROOT / "vivado" / "board"


@dataclass(frozen=True)
class Bench:
    top: str
    vhdl: list[str]
    sv: list[str]
    uses_ram_ip: bool
    defines: list[str]      # Verilog defines, OWN_<LAYER> for each own layer


# Per layer: (VHDL, SV) sources of the reference ("ref") and own ("own") implementation.
LAYERS = {
    "conv": {
        "ref": (["IPs/Convolution/Controller_Imp/behav_vhdl/Controller_impl.vhd",
                 "IPs/Convolution/PE_Top/behav_vhdl/PE.VHD",
                 "IPs/Convolution/Accumulator/behav_vhdl/accumulator.vhd",
                 "IPs/Convolution/RELU_Conv_Activation/behav_vhdl/RELU.vhd"],
                ["top/conv_top.sv"]),
        "own": ([], ["rtl/conv_controller.sv", "rtl/conv_pe.sv", "rtl/conv_pe_array.sv",
                     "rtl/conv_accumulator.sv", "rtl/conv_relu.sv", "rtl/conv_top.sv"]),
    },
    "pool": {
        "ref": (["IPs/pooling/behav_vhdl/Pooling.vhd"], []),
        "own": ([], ["rtl/pooling_top.sv"]),
    },
    "fc": {
        "ref": (["IPs/FC/behav_vhdl/FC.vhd"], []),
        "own": ([], ["rtl/fc_top.sv"]),
    },
}

# Per bench: testbench top, layers it contains, other SV sources, whether it needs the RAM IPs.
BENCHES = {
    "cnn": ("tb_cnn", ["conv", "pool", "fc"],
            ["IPs/Convolution/RAM_IP_src/RAM_IP_TOP.sv", "top/network_top.sv",
             "top/top_initialize.sv", "top/top.sv", "sim/tb_cnn.sv"], True),
    "fc": ("tb_fc", ["fc"], ["top/top_initialize.sv", "sim/tb_fc.sv"], False),
    # Board top level, always with the own layers; the images come from the image ROM
    "fpga": ("tb_fpga", ["conv", "pool", "fc"],
             ["IPs/Convolution/RAM_IP_src/RAM_IP_TOP.sv", "top/network_top.sv",
              "top/top_initialize.sv", "top/top.sv", "rtl/reset_sync.sv", "rtl/debounce.sv",
              "vivado/board/board_labels.sv", "rtl/image_loader.sv", "rtl/fpga_top.sv",
              "sim/tb_fpga.sv"], True),
}


def make_bench(name: str, own: set[str]) -> Bench:
    top, layers, common_sv, uses_ram_ip = BENCHES[name]
    vhdl, sv = [], []
    for layer in layers:
        layer_vhdl, layer_sv = LAYERS[layer]["own" if layer in own else "ref"]
        vhdl += layer_vhdl
        sv += layer_sv
    defines = [f"OWN_{layer.upper()}" for layer in layers if layer in own]
    return Bench(top, vhdl, sv + common_sv, uses_ram_ip, defines)


# ----------------------------------------------------------------------------------------
# Build / run
# ----------------------------------------------------------------------------------------
def xtool(run_dir: Path, name: str, *args: str) -> str:
    exe = VIVADO_BIN / f"{name}.bat"
    if not exe.exists():
        sys.exit(f"{exe} not found; set VIVADO_BIN")
    proc = subprocess.run([str(exe), *args], cwd=run_dir, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    problems = [l for l in out.splitlines() if l.startswith(("ERROR", "CRITICAL WARNING", "FATAL"))]
    if proc.returncode != 0 or problems:
        print("\n".join(problems or out.splitlines()[-30:]))
        sys.exit(f"{name} failed (exit {proc.returncode}); see {run_dir}")
    return out


def build(bench: Bench, run_dir: Path) -> None:
    src = lambda files: [str(ROOT / f) for f in files]
    print("compiling ...")
    if bench.vhdl:
        xtool(run_dir, "xvhdl", *src(bench.vhdl))
    libs = []
    if bench.uses_ram_ip:
        wrappers = [IP_DIR / f"dist_mem_gen_{k}" / "sim" / f"dist_mem_gen_{k}.v" for k in range(4)]
        if not all(p.exists() for p in wrappers):
            sys.exit("RAM IPs missing: run vivado/create_dist_mem.tcl first")
        xtool(run_dir, "xvlog", *map(str, wrappers))
        libs = ["-L", "dist_mem_gen_v8_0_17"]
        # The IP simulation model reads its init file from the run directory.
        for k in range(4):
            shutil.copy(IP_DIR / f"dist_mem_gen_{k}" / f"dist_mem_gen_{k}.mif", run_dir)
    defines = [arg for d in bench.defines for arg in ("-d", d)]
    xtool(run_dir, "xvlog", "--sv", *defines, *src(bench.sv))
    print("elaborating ...")
    xtool(run_dir, "xelab", *libs, "--timescale", "1ns/1ps", "-s", bench.top, f"work.{bench.top}")


def run(bench: Bench, run_dir: Path) -> None:
    # The testbenches read run_dir/vectors and write run_dir/out. (Plusargs can't be passed
    # through xsim.bat: cmd.exe splits arguments at '='.)
    (run_dir / "out").mkdir(exist_ok=True)
    print("simulating ...")
    out = xtool(run_dir, "xsim", bench.top, "--runall")
    for line in out.splitlines():
        if line.startswith(("FAIL", "SUMMARY")):
            print("  tb:", line)


# ----------------------------------------------------------------------------------------
# Compare: full design
# ----------------------------------------------------------------------------------------
def load_dump(path: Path, value_col: int) -> dict[int, np.ndarray]:
    per_img = defaultdict(list)
    for line in path.read_text().splitlines():
        cols = line.split()
        per_img[int(cols[0])].append(int(cols[value_col]))
    return {k: np.array(v) for k, v in per_img.items()}


def dihedral(a: np.ndarray):
    """The 8 rotations / reflections of a square array, with names."""
    for k, flip in itertools.product(range(4), (False, True)):
        yield f"{'flip+' if flip else ''}rot{90 * k}", np.rot90(np.fliplr(a) if flip else a, k)


def search_conv_convention(img: np.ndarray, stream: np.ndarray) -> list[str]:
    """All (kernel orientation, scan order, overflow) combinations that reproduce the stream."""
    hits = []
    windows = sliding_window_view(img, (4, 4))
    for kname, kernel in dihedral(g.CONV_W):
        fmap = np.einsum("rcij,ij->rc", windows, kernel) + g.CONV_B
        for oname, scan in dihedral(fmap):
            for mode in ("saturate", "wrap"):
                if np.array_equal(g.narrow(scan.flatten(), 4, mode), stream):
                    hits.append(f"kernel {kname}, scan {oname}, {mode}")
    return hits


def compare_cnn(ids: list[int], out_dir: Path) -> None:
    conv = load_dump(out_dir / "conv_dump.txt", 2)
    pool = load_dump(out_dir / "pool_dump.txt", 2)
    results = {}
    for line in (out_dir / "results.txt").read_text().splitlines():
        if not line.startswith("#"):
            c = list(map(int, line.split()))
            results[c[0]] = dict(zip(["label", "exp", "got", "n_conv", "n_pool", "t_conv",
                                      "t_pool", "t_done", "ram_writes", "pool_ok"], c[1:]))

    verbose = len(ids) <= 40
    if verbose:
        print(f"\n{'img':>5} {'label':>5} {'golden':>6} {'hw':>4}  {'conv stream':<28} {'pool':<10} cycles(conv/pool/done)")
    conv_ok = pool_ok = cls_ok = hw_correct = 0
    conventions = defaultdict(int)
    problems = []
    for i in ids:
        img = g.load_image(i)
        s = g.run(img)
        r = results.get(i)
        if r is None:
            problems.append(f"{i}: no result")
            continue
        got = conv.get(i, np.array([], dtype=int))
        if np.array_equal(got, s.conv_acc.flatten()):
            conv_txt = "match"
            conv_ok += 1
        elif len(got) != g.CONV_OUT ** 2:
            conv_txt = f"{len(got)} outputs (!= 3721)"
        else:
            hits = search_conv_convention(img, got)
            for h in hits:
                conventions[h] += 1
            conv_txt = f"other convention ({len(hits)})" if hits else "MISMATCH"
        p = pool.get(i, np.array([], dtype=int))
        pool_txt = "match" if np.array_equal(p, s.pool.flatten()) else "MISMATCH"
        pool_ok += pool_txt == "match"
        cls_ok += r["got"] == s.cls
        hw_correct += r["got"] == r["label"]
        line = (f"{i:>5} {r['label']:>5} {s.cls:>6} {r['got']:>4}  {conv_txt:<28} {pool_txt:<10} "
                f"{r['t_conv']}/{r['t_pool']}/{r['t_done']}"
                + (f"  RAM written {r['ram_writes']}x during run" if r["ram_writes"] else ""))
        if verbose:
            print(line)
        elif conv_txt != "match" or pool_txt != "match" or r["got"] != s.cls or r["ram_writes"]:
            problems.append(line)

    n = len(ids)
    for p in problems[:20]:
        print(p)
    print(f"\nconv stream matches golden: {conv_ok}/{n}   pool: {pool_ok}/{n}   class: {cls_ok}/{n}"
          f"   (hardware vs labels: {hw_correct}/{n})")
    if conventions:
        print("conv conventions that reproduce the mismatching streams (count of images):")
        for name, cnt in sorted(conventions.items(), key=lambda kv: -kv[1]):
            print(f"  {cnt:4d}  {name}")


# ----------------------------------------------------------------------------------------
# Compare: FC only
# ----------------------------------------------------------------------------------------
def write_fc_vectors(ids: list[int], n_random: int, vec_dir: Path, seed: int = 1) -> list[str]:
    """Pooled 4x4 maps (row-major) from test images plus random ones; returns a source tag per
    line. Random maps are half dense, over the full 4-bit input range 0..15, and half sparse
    with values 0..7 like real images."""
    vec_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    pools, tags = [], []
    for i in ids:
        pools.append(g.run(g.load_image(i)).pool.flatten())
        tags.append(f"img {i}")
    for n in range(n_random):
        if n % 2:
            v = rng.integers(0, 8, 16) * (rng.random(16) < 0.25)
        else:
            v = rng.integers(0, 16, 16)
        pools.append(v)
        tags.append("random")
    (vec_dir / "fc_vectors.txt").write_text("".join(" ".join(map(str, p)) + "\n" for p in pools))
    return tags


def compare_fc(tags: list[str], vec_dir: Path, out_dir: Path) -> None:
    pools = [np.array(list(map(int, l.split()))).reshape(4, 4)
             for l in (vec_dir / "fc_vectors.txt").read_text().splitlines()]
    # Each line: index, class[, hid0 hid1 hid2 fc2 when the testbench can see the internals]
    rows = {}
    for line in (out_dir / "fc_results.txt").read_text().splitlines():
        cols = list(map(int, line.split()))
        rows[cols[0]] = cols[1:]
    labels = g.load_labels()
    bad, n_img, hw_correct, gold_correct = [], 0, 0, 0
    cls_ok = n_internal = internal_ok = 0
    for n, (p, tag) in enumerate(zip(pools, tags)):
        fc1, fc2, cls = g.fc(p)
        hw_cls, *internal = rows.get(n, [None])
        golden_internal = [*np.maximum(fc1, 0).tolist(), fc2]
        cls_ok += hw_cls == cls
        if internal:
            n_internal += 1
            internal_ok += internal == golden_internal
        if hw_cls != cls or (internal and internal != golden_internal):
            bad.append(f"  {tag:>9}: pool {p.flatten().tolist()} golden fc1 {fc1.tolist()} fc2 {fc2} "
                       f"class {cls}, hw class {hw_cls}" + (f" hid+fc2 {internal}" if internal else ""))
        if tag.startswith("img"):
            label = labels[int(tag.split()[1]) - 1]
            n_img += 1
            hw_correct += hw_cls == label
            gold_correct += cls == label
    print(f"\nFC class matches golden: {cls_ok}/{len(pools)}")
    if n_internal:
        print(f"FC1 (after ReLU) and FC2 values match golden exactly: {internal_ok}/{n_internal}")
    if n_img:
        print(f"accuracy vs labels on {n_img} images: hardware {hw_correct / n_img:.1%}, golden {gold_correct / n_img:.1%}")
    print("\n".join(bad[:15]))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("bench", choices=BENCHES)
    ap.add_argument("images", help="test image numbers, e.g. 1-10,31")
    ap.add_argument("--own", default="", help="layers to take from rtl/, e.g. conv,pool")
    ap.add_argument("--random", type=int, default=0, help="fc bench: extra random pooled vectors")
    ap.add_argument("--no-build", action="store_true", help="reuse the existing snapshot")
    args = ap.parse_args()

    own = {layer for layer in args.own.split(",") if layer}
    if own - set(LAYERS):
        sys.exit(f"unknown layer(s) in --own: {', '.join(sorted(own - set(LAYERS)))}")
    if args.bench == "fpga":
        own = set(LAYERS)
    bench = make_bench(args.bench, own)
    used = [layer for layer in BENCHES[args.bench][1] if layer in own]
    tag = [] if args.bench == "fpga" or not used else ["own", *used]
    run_dir = ROOT / "build" / "sim" / "-".join([args.bench, *tag])
    vec_dir, out_dir = run_dir / "vectors", run_dir / "out"
    run_dir.mkdir(parents=True, exist_ok=True)
    ids = g.parse_ids(args.images)
    if args.bench == "fpga":
        if not all(1 <= i <= make_vectors.BOARD_IMAGES for i in ids):
            sys.exit(f"the board's image ROM holds images 1-{make_vectors.BOARD_IMAGES} only")
        make_vectors.write_tb_vectors(ids, vec_dir)
        # image_loader reads the image ROM file by name from the run directory
        shutil.copy(BOARD_DIR / "board_images.mem", run_dir)
    elif args.bench == "cnn":
        make_vectors.write_tb_vectors(ids, vec_dir)
    else:
        tags = write_fc_vectors(ids, args.random, vec_dir)

    if not args.no_build:
        build(bench, run_dir)
    run(bench, run_dir)
    if args.bench == "cnn":
        compare_cnn(ids, out_dir)
    elif args.bench == "fc":
        compare_fc(tags, vec_dir, out_dir)


if __name__ == "__main__":
    main()
