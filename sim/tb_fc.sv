`timescale 1ns/1ps

// Unit testbench for FC_TOP (reference netlist or own RTL, same ports).
//
// The weights are streamed by top_initialize exactly as in the full design. Then each line of
// vectors/fc_vectors.txt (16 pooled values, row-major tile order) is fed in with the same
// spacing the pooling layer produces (one value every 60 cycles, a longer gap after each tile
// row), and the 1-bit result is written to out/fc_results.txt as "<line> <result>"
// (-1 = timeout). With the own FC (compiled with -d OWN_FC) each line also has the internal
// values "<hid0> <hid1> <hid2> <fc2>" (FC1 after ReLU, FC2 sum) for an exact comparison.
// Paths are relative to the simulation run directory.
module tb_fc;

    localparam int CLK_PERIOD     = 10;     // ns, 100 MHz
    localparam int TIMEOUT_CYCLES = 5000;

    logic       clk     = 1'b0;
    logic       rst     = 1'b1;
    logic       start   = 1'b0;
    logic [3:0] pool    = '0;
    logic       v_pool  = 1'b0;
    logic [3:0] k_fc1, k_fc2;
    logic       v_fc1, v_fc2;
    logic       fc_out, fc_valid;

    top_initialize init_inst (
        .clk            (clk),
        .rst            (rst),
        .start_in       (start),
        .f_in           (),
        .valid_in_f     (),
        .k_FC1_in       (k_fc1),
        .valid_k_FC1_in (v_fc1),
        .k_FC2_in       (k_fc2),
        .valid_k_FC2_in (v_fc2),
        .start_read     ()
    );

    FC_TOP dut (
        .clk           (clk),
        .rst           (rst),
        .kernel_FC1_in (k_fc1),
        .valid_FC1_in  (v_fc1),
        .kernel_FC2_in (k_fc2),
        .valid_FC2_in  (v_fc2),
        .pooling       (pool),
        .valid_pooling (v_pool),
        .fc_output     (fc_out),
        .valid_output  (fc_valid)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    bit    done;
    logic  result;
    string internals;

    always @(posedge clk)
        if (!rst && fc_valid && !done) begin
            result = fc_out;
            done   = 1'b1;
`ifdef OWN_FC
            internals = $sformatf(" %0d %0d %0d %0d", dut.hid[0], dut.hid[1], dut.hid[2], dut.fc2);
`else
            internals = "";
`endif
        end

    initial begin
        int f_in, f_out, n;
        int v [16];

        f_in  = $fopen("vectors/fc_vectors.txt", "r");
        f_out = $fopen("out/fc_results.txt", "w");
        if (f_in == 0) $fatal(1, "cannot open vectors/fc_vectors.txt");

        n = 0;
        while ($fscanf(f_in, "%d", v[0]) == 1) begin
            for (int t = 1; t < 16; t++) void'($fscanf(f_in, "%d", v[t]));

            @(negedge clk);
            rst  = 1'b1;
            done = 1'b0;
            repeat (3) @(negedge clk);
            rst  = 1'b0;
            repeat (2) @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            repeat (100) @(negedge clk);        // FC1 / FC2 weights are loaded by now

            for (int t = 0; t < 16; t++) begin
                pool   = 4'(v[t]);
                v_pool = 1'b1;
                @(negedge clk);
                v_pool = 1'b0;
                repeat ((t % 4 == 3) ? 200 : 59) @(negedge clk);
            end

            fork
                wait (done);
                repeat (TIMEOUT_CYCLES) @(posedge clk);
            join_any
            disable fork;
            $fdisplay(f_out, "%0d %0d%s", n, done ? int'(result) : -1, done ? internals : "");
            n++;
        end

        $display("SUMMARY: %0d vectors", n);
        $fclose(f_out);
        $finish;
    end

endmodule
