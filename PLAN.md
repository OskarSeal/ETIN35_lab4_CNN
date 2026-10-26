# CNN on FPGA — EITF35 extra labs 4 & 5

Classify 64×64 binary images as **circle (0)** or **square (1)** with a small fixed-weight CNN
on a **Nexys4 rev B** (Artix-7 `xc7a100tcsg324-1`), 100 MHz, < 1 W.

```
Conv 4×4 → ReLU (61×61) → MaxPool 15×15 /15 (4×4) → FC1 16→3 → ReLU → FC2 3→1 → sigmoid → 1 bit
```

- **Assignment:** `CNN_presentation.ppt`.
  - Grade 4: integrate the provided IPs and run behavioral sims, then write your own conv
    (controller / PE / accumulator), ReLU and max-pool and run 10 images.
  - Grade 5: add the FC layers with a hardware-friendly sigmoid.
- **Benchmark / report template:** `lab4-5_report_ilayda.pdf` (2018). Their results: 1677 LUT,
  777 FF, 256 LUTRAM, WNS 1.193 ns, 0.11 W. Their lesson: pipeline the FC layer.
- **Target:** Grade 5, SystemVerilog.

## Toolchain

| Tool | Where |
|---|---|
| Vivado / xsim 2026.1 | `D:\Program\2026.1\Vivado\bin` (not on PATH; `tools/run_sim.py` uses `VIVADO_BIN` or that default) |
| Python (golden model, vectors, sim runner) | `uv run …` using `pyproject.toml` |
| Base constraints (Nexys4 rev B) | `D:\Program\Vivado\Lund_lab_src\sv\keyboard_top.xdc` |

## How to run

```powershell
uv run python tools/cnn_golden.py accuracy             # golden-model accuracy, 1000 test images
uv run python tools/cnn_golden.py show 31              # every stage for one image
uv run python tools/make_vectors.py coe 1 build/coe/img_00001   # 4 bank .coe files for one image

# RAM IPs (once, or to change the image baked into the FPGA build)
D:\Program\2026.1\Vivado\bin\vivado.bat -mode batch -nojournal -nolog `
    -source vivado/create_dist_mem.tcl -tclargs build/coe/img_00001

uv run python tools/run_sim.py cnn 1-10,31             # whole design: conv stream, pooling, class
uv run python tools/run_sim.py cnn 1-1000 --own conv,pool   # same, with own RTL for those layers
uv run python tools/run_sim.py fc 1-1000 --random 2000 # FC_TOP alone on pooled vectors

# Out-of-context synthesis + place & route of own blocks at 100 MHz (≈ 5 min per block)
D:\Program\2026.1\Vivado\bin\vivado.bat -mode batch -nojournal -nolog `
    -source vivado/synth_check.tcl -tclargs conv_top Pooling_TOP
```

`--own` takes any of `conv`, `pool`, `fc`: those layers come from `rtl/` (same module names and
ports as the reference), the rest from the reference netlists. Each combination gets its own
run directory, e.g. `build/sim/cnn-own-conv-pool`.

| Bench | Speed | Notes |
|---|---|---|
| `cnn` | ≈ 6 s per image with the gate-level reference conv; much faster with `--own conv` | Compile + elaborate ≈ 1 min; add `--no-build` to reuse the snapshot |
| `fc` | ≈ 0.13 s per vector | |

The testbenches are self-checking (`sim/tb_cnn.sv`, `sim/tb_fc.sv`). The runner compares the dumps
with the golden model. If a conv stream doesn't match, it searches the 128 orientation / scan /
overflow variants and names the one the hardware computes.

## Repository layout

| Path | Contents |
|---|---|
| `top/` | SystemVerilog top level: `top`, `top_initialize` (weight ROMs), `network_top`, `conv_top`, original `tb_top` |
| `IPs/` | Reference blocks as Vivado 2016.1 gate-level VHDL netlists (black boxes) + RAM wrapper `RAM_IP_TOP.sv` |
| `matlab_model/` | Original MATLAB model (not bit-exact, see below) |
| `Images/` | 1000 test PNGs, labels `Tst_trg.csv` (1 = square), `ifmap_stimuli_TEST.txt` (all images, 1 bit/line, row-major) |
| `rtl/` | Own RTL: conv layer (`conv_top`, `conv_controller`, `conv_pe_array`, `conv_pe`, `conv_accumulator`, `conv_relu`) and `Pooling_TOP` |
| `tools/` | Python: `cnn_golden.py` (golden model), `make_vectors.py` (.coe + TB vectors), `run_sim.py` (xsim runner) |
| `sim/` | Testbenches `tb_cnn.sv` (whole design) and `tb_fc.sv` (FC_TOP alone) |
| `vivado/` | `create_dist_mem.tcl` generates the four RAM IPs into `vivado/ip/` (generated, not checked in); `synth_check.tcl` synthesizes own blocks |
| `build/` | Generated vectors and simulation runs (not checked in) |

## Findings

### From simulating the reference design (Phase 2)

1. **RAM word layout: column c is in bit c (LSB first).**
   - That's how the reference conv reads it. The course MATLAB `.coe` script puts column 0 in the
     MSB, so with the course flow the hardware classifies every image **mirrored left–right**
     (96.2% instead of 96.7%).
   - `tools/make_vectors.py` writes LSB first.
   - Banks are interleaved by row: bank k holds rows k, k+4, …
2. **Reference conv + pooling are bit-exact with the golden model** (HW convention):
   - conv: sliding window without kernel flip, row-major scan, sum **saturated** to 4-bit
     signed, then ReLU
   - pooling: 15×15 tiles, row/col 61 dropped, row-major tile order
   - verified on images 1–200: conv stream and pooling bit-exact on 200/200; class 198/200
     (the two differences, images 31 and 141, come from the lossy reference FC, finding 3)
3. **Reference FC_TOP is lossy.** On the test images it scores 95.4%; exact arithmetic scores
   96.7%.
   - Over 3000 pooled vectors it disagrees with exact arithmetic 228 times, always answering
     "square".
   - Its netlist has a 3-bit FC1→FC2 bus and a 10-bit FC2 accumulator; the sums need 11 and
     14 bits.
   - **Decision:** the golden model keeps exact FC arithmetic. Your own FC targets the golden
     model, not the reference.
4. **Reference timing** (cycles after the start pulse):
   - weights load in cycles 1–48
   - memory read starts at about 100
   - first conv output at 110, then **one output every 4 cycles**
   - first pooled value at 3583
   - **class at 14802** (≈ 148 µs per image at 100 MHz)
   - the conv finishes its unused last row afterwards (≈ 14990)
   - the controller never writes the RAM during a run
5. **The MATLAB model is rotated 180°.** `xcorr2(filter, image)` in `matlab_model/convolve.m:2`
   has its arguments swapped (93.5%). It's kept in `cnn_golden.py` as the `MATLAB` convention
   for comparison.
6. **The weights in `top_initialize.sv` match MATLAB** (4-bit signed, row-major; FC1 is 3
   groups of 16). Biases are not streamed in: FC1 −12/+20/+24, FC2 +6, conv 0 (confirmed by
   the bit-exact conv stream).
7. **Worst-case widths for your own design:** conv sum [−15, 10] (dataset: −9…+4, so 4-bit
   saturate is safe), pool [0, 7] after saturation, FC1 11 b signed, FC2 14 b signed.
8. **`top.sv` start FSM re-triggers while `start_ext` stays high** (IDLE→COUNTER→FINISH→IDLE
   every 3 cycles). Use a one-cycle pulse in sim (the testbenches do). The board needs a
   synchronizer, debounce and edge detect.

## Phases

### Phase 0 — Setup ✅
- [x] Vivado 2026.1 located; reference netlists compile with xsim 2026.1
- [x] `PLAN.md`, `.gitignore`, `pyproject.toml` (uv), `git init`
- [ ] First commit

### Phase 1 — Bit-accurate Python golden model ✅
- [x] `tools/cnn_golden.py`: integer model with every stage; conventions as parameters;
      reproduces 96.7% / 93.5% / 80.8%
- [x] `tools/make_vectors.py`: per-bank `.coe` files and testbench vectors

### Phase 2 — Reference design in simulation (Grade 4, part 1) ✅
- [x] `vivado/create_dist_mem.tcl`: four `dist_mem_gen` IPs in batch mode
- [x] `sim/tb_cnn.sv`: loads images through the RAM write ports, records conv / pool / class,
      self-checking, timeouts
- [x] `sim/tb_fc.sv`: FC_TOP alone, weights streamed by `top_initialize`
- [x] `tools/run_sim.py`: compile → elaborate → run → compare in one command
- [x] Conventions settled (findings 1–4)

### Phase 3 — Own conv, ReLU and max-pool (Grade 4, part 2) ✅

The layer modules keep the reference names, ports, instance names and probed signal names
(`conv_top`, `Pooling_TOP`), so `network_top` / `top` are unchanged and each layer can be
swapped with `--own`. Inside, the structure follows the deck (controller, RAM, 4 PEs,
accumulator, ReLU), with its own handshake instead of the reference's `count_PE` / `start_acc`
protocol. That gives **one conv output per cycle instead of one per four**.

- **`conv_controller`:** walks the 61×61 windows row-major. It addresses the four banks for the
  *next* window row (`count_def` = row mod 4) while the current one is processed, so there are
  no bubbles.
- **`conv_pe_array`:** 16 weight registers (shifted in from `f_in`) and four 64-bit row
  registers. The rows are loaded once per window row, then shifted one column per cycle; the
  window is bits [3:0].
- **`conv_pe`:** adds the weights whose pixel is 1. Pixels are 0/1, so no multipliers are
  needed. Registered 8-bit partial sum.
- **`conv_accumulator`:** sum of the 4 partial sums (+ bias 0), saturated to 4-bit signed,
  registered. **`conv_relu`:** combinational.
- **`Pooling_TOP`:** streaming, with one running maximum per tile column; emits each maximum
  when its tile completes (row-major), skips row/col 61, and accepts a value every cycle.

Results:

| | Reference | Own |
|---|---|---|
| Conv stream vs golden, 1000 images | bit-exact (200 checked) | **bit-exact 1000/1000** |
| Pooling vs golden, 1000 images | bit-exact (200 checked) | **bit-exact 1000/1000** |
| First conv output / class ready (cycles after start) | 110 / 14802 | **106 / 3824** (3.9× faster) |
| conv_top, OOC P&R @ 100 MHz | – | 570 LUT (132 as RAM), 341 FF, WNS +3.57 ns |
| Pooling_TOP, OOC P&R @ 100 MHz | – | 28 LUT, 35 FF, WNS +5.72 ns |

- With the reference FC still in the loop, the class differs from golden on 33/1000 images.
  That is exactly the set where the reference FC alone is wrong (finding 3). Accuracy is 95.4%,
  as for the reference.
- Own conv + reference pooling + reference FC also works (`--own conv`, 6 images bit-exact):
  the reference pooling accepts one value per cycle, so the own conv layer is a true drop-in.

### Phase 4 — FC layers + sigmoid (Grade 5)
- Same `FC_TOP` ports. Weight registers loaded from the stream (48 + 3), biases hard-coded.
- 3 MACs consume each pooled value as it arrives, then +bias, ReLU, FC2, +bias.
  Widths: FC1 ≥ 11 b, FC2 ≥ 14 b signed.
- **Sigmoid:** σ(x) > 0.5 ⇔ x > 0, so the hardware sigmoid is the sign bit (class = FC2 > 0).
- Pipeline registers between MAC stages from the start.
- Write it as `rtl/fc_top.sv` (module `FC_TOP`), already wired into `run_sim.py --own fc`.
- Verify with `run_sim.py fc 1-1000 --random 2000 --own fc` against the **golden** model; the
  reference FC is lossy (finding 3). Then run the full design with `--own conv,pool,fc`.
- **Done when:** FC bit-exact with golden on all vectors; full design ≈ 96.7% on the images

### Phase 5 — FPGA
- XDC from the Nexys4 rev B file: clk E3, rst switch, start button
  (sync + debounce + edge detect), result and valid on LEDs.
- Regenerate the RAM IPs with the image to demo (LSB-first `.coe` from `make_vectors.py`).
- Build at 100 MHz; compare utilization, WNS and power with the 2018 numbers; demo on board.
- Stretch: several images in ROM, selected by switches.

### Phase 6 — Report
- Follow the 2018 report's structure.
- Add what it lacks: accuracy on 1000 images, latency/throughput, bit-width justification,
  verification method, and the findings above (MATLAB rotation, RAM bit order, lossy
  reference FC).

The deck's ASIC layout slide (550 µm², 500 MHz, Encounter) is out of scope for Grades 4/5.
