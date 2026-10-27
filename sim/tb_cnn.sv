`timescale 1ns/1ps

// Self-checking testbench for the full CNN (top.sv).
//
// For every image listed in expected.txt it holds the design in reset, writes the image into
// the four RAM banks through their write ports (forced from here), releases reset, gives a
// one-cycle start pulse and waits for the classification. It checks the class and the 16
// pooled values against tools/cnn_golden.py and dumps the conv / pooling streams so that
// tools/run_sim.py can compare them in detail.
//
// Optional plusargs (paths are relative to the simulation run directory):
//   +VEC_DIR=<dir>  images.mem and expected.txt (tools/make_vectors.py tb ...), default vectors
//   +OUT_DIR=<dir>  where conv_dump.txt, pool_dump.txt and results.txt go, default out

`define NET  uut.network_inst
`define CONV uut.network_inst.CONV_TOP_inst
`define RAM  uut.network_inst.CONV_TOP_inst.RAM_inst

module tb_cnn;

    localparam int CLK_PERIOD     = 10;     // ns, 100 MHz
    localparam int MAX_IMAGES     = 1000;
    localparam int TIMEOUT_CYCLES = 20000;
    localparam int CONV_OUTPUTS   = 61 * 61;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    logic clk       = 1'b0;
    logic rst       = 1'b1;
    logic start_ext = 1'b0;
    logic output_ext, valid_output_ext;

    top uut (
        .clk              (clk),
        .rst              (rst),
        .start_ext        (start_ext),
        .load_we          (1'b0),         // the image is loaded by forcing the RAM ports
        .load_row         ('0),
        .load_data        ('0),
        .output_ext       (output_ext),
        .valid_output_ext (valid_output_ext)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------
    // Vectors and output files
    // ------------------------------------------------------------------
    logic [63:0] img_rows [MAX_IMAGES*64];
    string       vec_dir, out_dir;
    int          f_exp, f_conv, f_pool, f_res;

    // ------------------------------------------------------------------
    // Monitors (sampled on the rising edge, like a register would)
    // ------------------------------------------------------------------
    int          img_id;
    int          cycle;             // cycles since the start pulse
    bit          loading;
    int          n_conv, n_pool, n_ram_writes;
    logic [3:0]  pool_got [16];
    bit          done;
    logic        result;
    int          t_first_conv, t_first_pool, t_done;

    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (!rst && `CONV.valid_ofmap_conv) begin
            $fdisplay(f_conv, "%0d %0d %0d %0d", img_id, cycle,
                      $signed(`CONV.ofmap_conv), `CONV.ofmap_relu);
            if (n_conv == 0) t_first_conv = cycle;
            n_conv++;
        end
        if (!rst && `NET.valid_pooling) begin
            $fdisplay(f_pool, "%0d %0d %0d", img_id, cycle, `NET.pooling_out);
            if (n_pool == 0) t_first_pool = cycle;
            if (n_pool < 16) pool_got[n_pool] = `NET.pooling_out;
            n_pool++;
        end
        if (!rst && `NET.valid_output && !done) begin
            result = `NET.out;
            t_done = cycle;
            done   = 1'b1;
        end
        if (!loading && (`RAM.wen_1 || `RAM.wen_2 || `RAM.wen_3 || `RAM.wen_4))
            n_ram_writes++;
    end

    // ------------------------------------------------------------------
    // Load one image: bank k gets image rows k, k+4, ... at addresses 0..15
    // ------------------------------------------------------------------
    logic [3:0]  ld_addr;
    logic [63:0] ld_data_1, ld_data_2, ld_data_3, ld_data_4;

    task automatic load_image(input int n);
        loading = 1'b1;
        force `RAM.address_1 = ld_addr;   force `RAM.data_1 = ld_data_1;   force `RAM.wen_1 = 1'b1;
        force `RAM.address_2 = ld_addr;   force `RAM.data_2 = ld_data_2;   force `RAM.wen_2 = 1'b1;
        force `RAM.address_3 = ld_addr;   force `RAM.data_3 = ld_data_3;   force `RAM.wen_3 = 1'b1;
        force `RAM.address_4 = ld_addr;   force `RAM.data_4 = ld_data_4;   force `RAM.wen_4 = 1'b1;
        for (int a = 0; a < 16; a++) begin
            ld_addr   = a;
            ld_data_1 = img_rows[n*64 + 4*a + 0];
            ld_data_2 = img_rows[n*64 + 4*a + 1];
            ld_data_3 = img_rows[n*64 + 4*a + 2];
            ld_data_4 = img_rows[n*64 + 4*a + 3];
            @(negedge clk);                 // written on the rising edge in between
        end
        release `RAM.address_1;  release `RAM.data_1;  release `RAM.wen_1;
        release `RAM.address_2;  release `RAM.data_2;  release `RAM.wen_2;
        release `RAM.address_3;  release `RAM.data_3;  release `RAM.wen_3;
        release `RAM.address_4;  release `RAM.data_4;  release `RAM.wen_4;
        loading = 1'b0;
    endtask

    // ------------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------------
    initial begin
        int id, label, exp_cls, exp_fc2;
        int exp_pool [16];
        int n_images, n_fail;
        bit ok;

        if (!$value$plusargs("VEC_DIR=%s", vec_dir)) vec_dir = "vectors";
        if (!$value$plusargs("OUT_DIR=%s", out_dir)) out_dir = "out";
        $readmemb({vec_dir, "/images.mem"}, img_rows);
        f_exp  = $fopen({vec_dir, "/expected.txt"}, "r");
        f_conv = $fopen({out_dir, "/conv_dump.txt"}, "w");
        f_pool = $fopen({out_dir, "/pool_dump.txt"}, "w");
        f_res  = $fopen({out_dir, "/results.txt"}, "w");
        if (f_exp == 0) $fatal(1, "cannot open %s/expected.txt", vec_dir);
        $fdisplay(f_res, "# id label expected got conv_outputs pool_outputs first_conv first_pool done ram_writes pool_ok");

        n_images = 0;
        n_fail   = 0;
        while ($fscanf(f_exp, "%d %d %d %d", id, label, exp_cls, exp_fc2) == 4) begin
            foreach (exp_pool[t]) void'($fscanf(f_exp, "%d", exp_pool[t]));

            // Reset, load, release, start
            @(negedge clk);
            rst          = 1'b1;
            img_id       = id;
            load_image(n_images);
            repeat (2) @(negedge clk);
            n_conv       = 0;
            n_pool       = 0;
            n_ram_writes = 0;
            done         = 1'b0;
            t_first_conv = -1;
            t_first_pool = -1;
            rst          = 1'b0;
            repeat (2) @(negedge clk);
            cycle        = 0;
            start_ext    = 1'b1;
            @(negedge clk);
            start_ext    = 1'b0;

            fork
                wait (done);
                repeat (TIMEOUT_CYCLES) @(posedge clk);
            join_any
            disable fork;
            // The class can be ready before the conv layer has produced its last row (row 61
            // is not used by pooling); wait for the remaining conv outputs too.
            fork
                wait (n_conv >= CONV_OUTPUTS);
                repeat (TIMEOUT_CYCLES) @(posedge clk);
            join_any
            disable fork;
            repeat (20) @(posedge clk);     // let trailing outputs (if any) show up in the dumps

            ok = 1'b1;
            for (int t = 0; t < 16; t++) ok &= (pool_got[t] === 4'(exp_pool[t]));
            ok &= (n_pool == 16);
            $fdisplay(f_res, "%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d", id, label, exp_cls,
                      done ? int'(result) : -1, n_conv, n_pool, t_first_conv, t_first_pool,
                      done ? t_done : -1, n_ram_writes, ok);
            if (!done || result !== exp_cls[0] || !ok || n_conv != CONV_OUTPUTS) begin
                n_fail++;
                $display("FAIL img %0d: class %s (expected %0d, label %0d), pool %s, %0d conv outputs",
                         id, done ? $sformatf("%0d", result) : "TIMEOUT", exp_cls, label,
                         ok ? "ok" : "MISMATCH", n_conv);
            end
            n_images++;
        end

        $display("SUMMARY: %0d images, %0d failed", n_images, n_fail);
        $fclose(f_conv);
        $fclose(f_pool);
        $fclose(f_res);
        $finish;
    end

endmodule
