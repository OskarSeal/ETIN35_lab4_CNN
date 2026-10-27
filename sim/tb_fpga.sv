`timescale 1ns/1ps

// Board-level testbench for fpga_top. As on the board, the testbench does not touch the RAM:
// it sets the image switches and presses the start button, and the image comes from the ROM in
// image_loader (board_images.mem / board_labels.mem in the run directory). For every image in
// vectors/expected.txt (images 1..256) it checks that
//   - one press (bouncing; the first one held for longer than two runs) gives exactly one
//     load of 64 rows and one run,
//   - every row written through top's load port is that image's row (vectors/images.mem),
//   - the LEDs then show the class in expected.txt, and LED3 whether it matches the label.
// Before the first press the LEDs must be off; afterwards, moving the switches to another
// image must turn them off and moving them back on again, and glitches shorter than the
// debounce time must give no run.
// Paths are relative to the simulation run directory.
module tb_fpga;

    localparam int CLK_PERIOD = 10;     // ns, 100 MHz
    localparam int DEBOUNCE   = 50;     // cycles (10 ms on the board)
    localparam int RUN_CYCLES = 5000;   // > one load + classification (64 + 3 + 3771 cycles)
    localparam int MAX_IMAGES = 256;

    logic       clk       = 1'b0;
    logic       sw_rst    = 1'b1;
    logic [7:0] sw_img    = '0;
    logic       btn_start = 1'b0;
    logic [3:0] led;

    fpga_top #(
        .DEBOUNCE_CYCLES (DEBOUNCE)
    ) uut (
        .clk       (clk),
        .sw_rst    (sw_rst),
        .sw_img    (sw_img),
        .btn_start (btn_start),
        .led       (led)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    logic [63:0] img_rows [MAX_IMAGES*64];
    int          n_cur;                 // index in expected.txt of the image being checked
    int          errors = 0;

    // Classifications finished inside the CNN, rows written through the load port
    int runs = 0, writes = 0;
    always @(posedge clk) begin
        if (uut.top_inst.network_inst.valid_output)
            runs++;
        if (uut.top_inst.load_we) begin
            if (uut.top_inst.load_data !== img_rows[n_cur*64 + uut.top_inst.load_row]) begin
                $display("FAIL load: row %0d written as %h, expected %h", uut.top_inst.load_row,
                         uut.top_inst.load_data, img_rows[n_cur*64 + uut.top_inst.load_row]);
                errors++;
            end
            writes++;
        end
    end

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

    task automatic press(input int hold_cycles);
        bounce(1'b1);
        repeat (DEBOUNCE + hold_cycles) @(negedge clk);
        bounce(1'b0);
        repeat (DEBOUNCE + RUN_CYCLES) @(negedge clk);
    endtask

    task automatic expect_count(input int got, input int exp, input string what);
        if (got != exp) begin
            $display("FAIL %s: %0d, expected %0d", what, got, exp);
            errors++;
        end
    endtask

    task automatic expect_leds(input logic [3:0] exp, input string what);
        if (led !== exp) begin
            $display("FAIL %s: LEDs %b, expected %b", what, led, exp);
            errors++;
        end
    endtask

    function automatic string shown_as(input logic [3:0] l);
        string cls, verdict;
        if (!l[0])
            return "nothing";
        cls     = l[1] ? "square" : "circle";
        verdict = l[3] ? "right" : "wrong";
        return {cls, " (", verdict, ")"};
    endfunction

    initial begin
        int          f, id, label, exp_cls, exp_fc2, pool;
        int          n_images, last_id;
        logic [3:0]  exp_led;

        $readmemb("vectors/images.mem", img_rows);
        f = $fopen("vectors/expected.txt", "r");
        if (f == 0)
            $fatal(1, "cannot open vectors/expected.txt");

        repeat (10) @(negedge clk);
        sw_rst = 1'b0;
        repeat (10) @(negedge clk);
        expect_leds(4'b0000, "before the first press");

        n_images = 0;
        while ($fscanf(f, "%d %d %d %d", id, label, exp_cls, exp_fc2) == 4) begin
            repeat (16) void'($fscanf(f, "%d", pool));
            if (id < 1 || id > MAX_IMAGES)
                $fatal(1, "image %0d is not in the board ROM (1..%0d)", id, MAX_IMAGES);
            n_cur  = n_images;
            sw_img = 8'(id);                // image 256 = all switches off
            repeat (10) @(negedge clk);
            runs   = 0;
            writes = 0;
            press(n_images == 0 ? 2 * RUN_CYCLES : 10);
            expect_count(runs, 1, $sformatf("image %0d: runs", id));
            expect_count(writes, 64, $sformatf("image %0d: rows loaded", id));
            exp_led = {exp_cls == label, exp_cls == 0, exp_cls == 1, 1'b1};
            expect_leds(exp_led, $sformatf("image %0d (class %0d, label %0d)", id, exp_cls, label));
            $display("image %3d (label %0d, switches %b): %s", id, label, sw_img, shown_as(led));
            last_id = id;
            n_images++;
        end
        if (n_images == 0)
            $fatal(1, "no images in vectors/expected.txt");

        // Switches moved away from the classified image and back, without pressing
        sw_img = 8'(last_id + 1);
        repeat (10) @(negedge clk);
        expect_leds(4'b0000, "switches moved away");
        sw_img = 8'(last_id);
        repeat (10) @(negedge clk);
        expect_leds(exp_led, "switches moved back");

        // Glitches only
        runs   = 0;
        writes = 0;
        repeat (3) begin
            btn_start = 1'b1;
            #(CLK_PERIOD * 10);
            btn_start = 1'b0;
            #(CLK_PERIOD * 10);
        end
        repeat (DEBOUNCE + RUN_CYCLES) @(negedge clk);
        expect_count(runs, 0, "glitches only: runs");
        expect_count(writes, 0, "glitches only: rows loaded");

        $display("SUMMARY: %0d images, %0d errors", n_images, errors);
        $finish;
    end

endmodule
