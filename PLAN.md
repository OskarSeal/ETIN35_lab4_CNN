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
uv run python tools/make_vectors.py coe 1 vivado/coe/img_00001  # 4 bank .coe files for one image

# RAM IPs (once). Their init image only matters for simulations that don't load the RAM;
# the board loads the selected image before each run. The .coe files for images 1 and 3 are
# checked in; create_projects.tcl runs this with image 1 if needed.
D:\Program\2026.1\Vivado\bin\vivado.bat -mode batch -nojournal -nolog `
    -source vivado/create_dist_mem.tcl -tclargs vivado/coe/img_00001

uv run python tools/run_sim.py cnn 1-10,31             # whole design: conv stream, pooling, class
uv run python tools/run_sim.py cnn 1-1000 --own conv,pool,fc  # same, with own RTL for those layers
uv run python tools/run_sim.py fc 1-1000 --random 2000 --own fc # FC_TOP alone on pooled vectors

# Out-of-context synthesis + place & route of own blocks at 100 MHz (≈ 5 min per block)
D:\Program\2026.1\Vivado\bin\vivado.bat -mode batch -nojournal -nolog `
    -source vivado/synth_check.tcl -tclargs conv_top Pooling_TOP FC_TOP top

# Board: image ROM files (checked in; only to regenerate), simulate fpga_top selecting images
# with the switches, build, program
uv run python tools/make_vectors.py board vivado/board
uv run python tools/run_sim.py fpga 1,3,31,59,255,256  # any of images 1-256
D:\Program\2026.1\Vivado\bin\vivado.bat -mode batch -nojournal -nolog -source vivado/build_fpga.tcl
D:\Program\2026.1\Vivado\bin\vivado.bat -mode batch -nojournal -nolog -source vivado/program_fpga.tcl
```

One bitstream holds images 1–256; SW1–SW8 select one (see Phase 5). The optional
`-tclargs <name>` of the build and program scripts selects `build/fpga/<name>/` instead of
`build/fpga/`.

Vivado GUI projects, one per grade. Run Behavioral Simulation runs `tb_cnn` on the images
in `sim/vectors` (images 1–10, checked in); each project writes its dumps to
`build/sim/project/<project>/`. Only git and Vivado are needed, so this also works on
another computer right after cloning:

```powershell
git clone https://github.com/OskarSeal/CNN.git
cd CNN
<Vivado>\bin\vivado.bat -mode batch -nojournal -nolog `
    -source vivado/create_projects.tcl -tclargs D:/Program/Vivado grade4 grade5
uv run python tools/make_vectors.py tb 1-10 sim/vectors   # only to simulate other images
```

On the lab computer (Vivado 2024.1) the repository goes to `C:\Users\os0283sa-s\Program\CNN`
and the projects to their own folder next to it, which the script creates:
`-tclargs C:/Users/os0283sa-s/Program/CNN_projects grade4 grade5`. The flow is
tested with Vivado 2026.1 only; the Tcl scripts avoid Tcl 8.6-only commands such as `lmap` so
that older Vivado versions can run them.

The projects store the repository's absolute path, so after moving the repository, delete and
recreate them. What `create_projects.tcl` adds (all referenced from the repository, none copied):

| | `CNN_grade4` | `CNN_grade5` |
|---|---|---|
| Both | `top/top.sv`, `top/network_top.sv`, `top/top_initialize.sv`, `IPs/Convolution/RAM_IP_src/RAM_IP_TOP.sv`, the RAM IPs `vivado/ip/dist_mem_gen_0..3.xci`, `rtl/conv_*.sv` (6 files), `rtl/pooling_top.sv`, board top `rtl/fpga_top.sv` + `image_loader.sv` + `debounce.sv` + `reset_sync.sv`, image ROM file `vivado/board/board_images.mem` + labels `vivado/board/board_labels.sv` | same |
| FC layer | `IPs/FC/behav_vhdl/FC.vhd` (reference netlist) | `rtl/fc_top.sv` |
| Constraints | `vivado/nexys4.xdc` | same |
| Simulation | `sim/tb_cnn.sv` (top `tb_cnn`, runtime `all`, `-testplusarg VEC_DIR=… OUT_DIR=…`) | same |

| Project | Layers | Class ready |
|---|---|---|
| `CNN_reference` (`reference`, grade 4 part 1) | all course netlists | 14802 cycles |
| `CNN_grade4` (grade 4 part 2) | own conv + ReLU + pool, reference FC | 3824 cycles |
| `CNN_grade5` | all own | 3771 cycles |

With the reference FC, `tb_cnn` reports FAIL on the images where that FC is lossy (finding 3,
e.g. images 31 and 141); images 1–10 pass in all three.

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
| `rtl/` | Own RTL: conv layer (`conv_top`, `conv_controller`, `conv_pe_array`, `conv_pe`, `conv_accumulator`, `conv_relu`), `Pooling_TOP`, `FC_TOP`; board top `fpga_top` with `image_loader` (image ROM), `debounce` and `reset_sync` |
| `tools/` | Python: `cnn_golden.py` (golden model), `make_vectors.py` (.coe + TB vectors), `run_sim.py` (xsim runner) |
| `sim/` | Testbenches `tb_cnn.sv` (whole design), `tb_fc.sv` (FC_TOP alone), `tb_fpga.sv` (board top); `vectors/` (images 1–10 for the GUI projects) |
| `vivado/` | `board/` (the board's image ROM file for images 1–256 and the module with their labels, from `make_vectors.py board`), `create_dist_mem.tcl` (RAM IPs into `vivado/ip/`, not checked in, from `coe/img_0000N/`: images 1 and 3), `synth_check.tcl` (OOC synthesis), `build_fpga.tcl` + `nexys4.xdc` (bitstream), `program_fpga.tcl`, `sources.tcl` (shared source list), `create_projects.tcl` + `setup_project.tcl` (GUI projects) |
| `build/` | Generated vectors and simulation runs (not checked in) |

**RTL style** (`rtl/`, as in the course's `top/`): no `for` loops (procedural or `generate`).
Each module has one sequential process that holds only the reset and `x_q <= x_d` (or a plain
delay such as `valid_q <= valid_in`); all logic is in `always_comb` blocks or `assign`.

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

### Phase 4 — FC layers + sigmoid (Grade 5) ✅

`rtl/fc_top.sv`, module `FC_TOP` with the reference ports:

- **Weights:** 48 FC1 + 3 FC2 weights shifted in from the `top_initialize` stream. Biases are
  parameters (−12/+20/+24, +6).
- **FC1:** three multiply-accumulates take each pooled value as it arrives (row-major), with
  the accumulators starting at the biases. FC1 is done one cycle after the 16th value; the
  reference instead buffers all 16 and runs 48 serial products.
- **Pipeline after FC1:** ReLU → FC2 products → FC2 sum + bias → **sigmoid as a sign check**
  (σ(x) > 0.5 ⇔ x > 0, so class = FC2 > 0). One stage per cycle; the class comes 6 cycles
  after the last pooled value.
- **Widths** cover *any* streamed 4-bit weights and the full 4-bit input range: FC1 12 b,
  FC2 17 b signed. It cannot overflow, which is exactly where the reference FC loses accuracy.

Results:

| | Reference FC | Own FC |
|---|---|---|
| Class vs golden, 3000 vectors (1000 images + 2000 random, dense ones over 0..15) | 2772/3000 | **3000/3000** |
| FC1-after-ReLU and FC2 values vs golden | – | **exact on 3000/3000** |
| Accuracy on the 1000 images | 95.4% | **96.7%** |
| Whole design, all own layers, 1000 images | – | conv, pool and class **1000/1000** bit-exact; class ready **3771** cycles after start (reference 14802) |
| FC_TOP, OOC P&R @ 100 MHz | – | 342 LUT, 366 FF, 0 DSP, WNS +4.37 ns |

Whole design (`top` with all own layers), out-of-context synthesis + P&R at 100 MHz
(`synth_check.tcl … top`), against the 2018 report:

| | 2018 report | Own design |
|---|---|---|
| LUT (of which as memory) | 1677 (256) | **901 (132)** |
| FF | 777 | 758 |
| DSP / BRAM | – | 0 / 0 |
| WNS @ 100 MHz | +1.193 ns | **+3.679 ns** |
| Accuracy on the 1000 test images | – | 96.7% |
| Latency, start → class | – | 3771 cycles ≈ 38 µs (≈ 26 k images/s) |

These whole-design numbers are from after the RTL rewrite (no `for` loops, see RTL style); the
per-block rows in the Phase 3 / 4 tables are from before it. The OOC numbers have no I/O
buffers (the design has 5 I/Os). Power comes in Phase 5 with the
real implementation. Synthesis warnings come only from the course's `top.sv` (unused
`counter_q` register and one FSM state bit) and are harmless.

`sim/tb_fc.sv` also dumps the FC internals when compiled with `-d OWN_FC` (`run_sim.py` passes
`OWN_<LAYER>` for each `--own` layer), so the FC bench checks values, not just the 1-bit
class.

### Phase 5 — FPGA (image selection by switches: written, not yet simulated or built)

`rtl/fpga_top.sv` wraps `top`; pins are in `vivado/nexys4.xdc`. One bitstream holds test
images 1–256 in a ROM (`rtl/image_loader.sv`); the switches select one, and each press of BTNC
loads it into the conv layer's RAM and classifies it.

| Board | Signal | Function |
|---|---|---|
| SW0 (U9) | `sw_rst` | up = reset. Goes through `reset_sync`: asynchronous assert, synchronous release |
| SW1–SW8 (U8 R7 R6 R5 V7 V6 V5 U4) | `sw_img[7:0]` | image number in binary, SW1 = LSB: 1–255, all off = 256. Two-flop synchronizer, sampled on the press |
| BTNC (E16) | `btn_start` | press = load the selected image and classify it. `debounce` (2-flop sync, 10 ms) gives one pulse per press |
| LED0 (T8) | `led[0]` | result valid |
| LED1 (V9) | `led[1]` | square |
| LED2 (R8) | `led[2]` | circle |
| LED3 (T6) | `led[3]` | the result matches the image's label (`Images/Tst_trg.csv`) |

The LEDs go dark when the switches no longer select the image that was classified, so they
never show a stale result for a new selection.

- **Pins:** SW0, LED0–2 are from the course XDC; BTNC, SW1–SW8 and LED3 are from the Digilent
  Nexys4 master XDC. If something does nothing on the board, check those pins first.
- **Load path:** `top`, `network_top` and both `conv_top`s (own and reference wrapper) have a
  new image load port `load_we` / `load_row[5:0]` / `load_data[63:0]`. Image row r goes to
  bank r mod 4, address r / 4, the same layout as the `.coe` files. In the own conv layer
  `conv_controller` drives the RAM write side from it (it was tied off); the reference wrapper
  muxes it in front of the netlist controller's RAM ports. Loads happen only while the CNN is
  idle (a press comes at most every 10 ms, a run takes 38 µs). `tb_cnn` ties the port off and
  still loads by forcing the RAM ports.
- **`image_loader`:** 256 × 64 words of 64 bits (1 Mbit) in block RAM, with two read
  registers, plus the 256 labels (`board_labels`). On the press it copies the 64 rows of the
  selected image (64 + 3 cycles), then gives the start pulse to `top`. Start → class is
  3771 + 67 cycles ≈ 38 µs.
- **Generated files** (`make_vectors.py board`): `vivado/board/board_images.mem`
  (`$readmemh`, entry n at words 64 n … 64 n + 63, entry 0 = image 256) and
  `vivado/board/board_labels.sv` (module `board_labels`, the labels as a 256-bit constant).
  `build_fpga.tcl` reads the `.mem` with `read_mem` and the GUI projects add both as design
  sources; `image_loader` opens the `.mem` by name. The images were checked in Python against
  the hardware-verified `.coe` files of images 1 and 3: the RAM after a load holds exactly
  those words.
- **Labels are not a `$readmem` file:** the first version read them with `$readmemb` into a
  1-bit-wide memory. Vivado 2024.1 synthesis rejects that ("malformed $readmem task: invalid
  memory name"), keeps going and leaves the labels at 0, so on the board LED3 lit only for
  circles. The images (64-bit words) loaded fine: image 1 showed square, image 3 circle.
- **Demo images:** the golden model (and so the hardware, bit-exact) gets 10 of images 1–256
  wrong (LED3 off): 31, 122, 202, 245 (squares shown as circles) and 59, 69, 75, 78, 154,
  224 (circles shown as squares). Correct examples: 1 (square), 3 (circle).
- **`run_sim.py fpga <images>`** simulates `fpga_top` with the switches set to each image in
  turn: a bouncing press (the first held over two run lengths), the 64 rows written through
  the load port checked against the image, one run per press, the LEDs against the golden
  class and label, the LEDs going dark when the switches move away and back on when they
  return, and glitch-only input.
- **Before the image ROM** (one image baked into the RAM IPs, no load path) the build met
  timing with 913 LUT (132 as memory), 782 FF, 0 BRAM, WNS +3.559 ns, 0.112 W; on the board
  it could only ever show the result for that one image. Vivado folded the RAM bit columns that
  were constant for that image; with the load path the RAM is written, so that no longer
  happens and LUT as memory rises.
- To do: run `run_sim.py fpga 1,3,31,59,255,256` and `run_sim.py cnn 1-10 --own conv,pool,fc`
  (regression of the load port tied off) in Vivado, build, check utilization / timing / power
  and update the table, then test on the board.

### Phase 6 — Report
- Follow the 2018 report's structure.
- Add what it lacks: accuracy on 1000 images, latency/throughput, bit-width justification,
  verification method, and the findings above (MATLAB rotation, RAM bit order, lossy
  reference FC).

The deck's ASIC layout slide (550 µm², 500 MHz, Encounter) is out of scope for Grades 4/5.
