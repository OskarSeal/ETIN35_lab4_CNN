`timescale 1ns/1ps

// Board-level testbench for fpga_top. Unlike tb_cnn, the image is not loaded by the testbench:
// it comes from the init file baked into the RAM IPs, as on the board. The start button
// bounces and is held for longer than two runs. Checks that
//   - the LEDs are off before the first press,
//   - one press (bouncing, held) gives exactly one run,
//   - the LEDs then show the class in vectors/expected.txt,
//   - a second press gives a second run,
//   - glitches shorter than the debounce time give none.
// Path relative to the simulation run directory.
module tb_fpga;

    localparam int CLK_PERIOD = 10;     // ns, 100 MHz
    localparam int DEBOUNCE   = 50;     // cycles (10 ms on the board)
    localparam int RUN_CYCLES = 5000;   // > one classification (3771 cycles after start)

    logic       clk       = 1'b0;
    logic       sw_rst    = 1'b1;
    logic       btn_start = 1'b0;
    logic [2:0] led;

    fpga_top #(
        .DEBOUNCE_CYCLES (DEBOUNCE)
    ) uut (
        .clk       (clk),
        .sw_rst    (sw_rst),
        .btn_start (btn_start),
        .led       (led)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // Classifications finished inside the CNN
    int runs = 0;
    always @(posedge clk)
        if (uut.top_inst.network_inst.valid_output)
            runs++;

    // Contact bounce: a few glitches shorter than the debounce time, then the final level
    task automatic bounce(input logic level);
        repeat (5) begin
            btn_start = level;
            #(CLK_PERIOD * 7);
            btn_start = !level;
            #(CLK_PERIOD * 3);
        end
        btn_start = level;
    endtask

    int errors = 0;

    task automatic expect_runs(input int n, input string what);
        if (runs != n) begin
            $display("FAIL %s: %0d runs, expected %0d", what, runs, n);
            errors++;
        end
    endtask

    initial begin
        int    f, id, label, exp_cls, exp_fc2;
        string shown;

        f = $fopen("vectors/expected.txt", "r");
        if (f == 0 || $fscanf(f, "%d %d %d %d", id, label, exp_cls, exp_fc2) != 4)
            $fatal(1, "cannot read vectors/expected.txt");

        repeat (10) @(negedge clk);
        sw_rst = 1'b0;
        repeat (10) @(negedge clk);
        if (led !== 3'b000) begin
            $display("FAIL before start: LEDs %b", led);
            errors++;
        end

        // Press (bouncing), hold for two run lengths, release (bouncing)
        bounce(1'b1);
        repeat (2 * RUN_CYCLES) @(negedge clk);
        bounce(1'b0);
        repeat (DEBOUNCE + RUN_CYCLES) @(negedge clk);
        expect_runs(1, "first press, held");
        if (led !== {exp_cls[0] == 1'b0, exp_cls[0] == 1'b1, 1'b1}) begin
            $display("FAIL image %0d: LEDs %b, expected class %0d", id, led, exp_cls);
            errors++;
        end

        // Second press
        bounce(1'b1);
        repeat (DEBOUNCE + 10) @(negedge clk);
        bounce(1'b0);
        repeat (DEBOUNCE + RUN_CYCLES) @(negedge clk);
        expect_runs(2, "second press");

        // Glitches only
        repeat (3) begin
            btn_start = 1'b1;
            #(CLK_PERIOD * 10);
            btn_start = 1'b0;
            #(CLK_PERIOD * 10);
        end
        repeat (DEBOUNCE + RUN_CYCLES) @(negedge clk);
        expect_runs(2, "glitches only");

        if (led[1])
            shown = "square";
        else if (led[2])
            shown = "circle";
        else
            shown = "nothing";
        $display("SUMMARY: image %0d (label %0d) shown as %s on the LEDs, %0d runs, %0d errors",
                 id, label, shown, runs, errors);
        $finish;
    end

endmodule
