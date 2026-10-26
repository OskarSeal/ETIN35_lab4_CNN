// Board top level for the Nexys4 rev B (pins in vivado/nexys4.xdc). Conditions the switch and
// button inputs and shows the result on LEDs; the CNN itself is top.sv, unchanged.
//
//   SW0  sw_rst     up = reset
//   BTNC btn_start  press = classify the image in the RAM (one run per press, however long
//                   the button is held; top.sv itself would restart every 3 cycles)
//   LED0 led[0]     result valid
//   LED1 led[1]     square
//   LED2 led[2]     circle
module fpga_top #(
    parameter int DEBOUNCE_CYCLES = 1_000_000   // 10 ms at 100 MHz
) (
    input  logic       clk,
    input  logic       sw_rst,
    input  logic       btn_start,
    output logic [2:0] led
);

    logic rst, start;
    logic cls, cls_valid;

    reset_sync reset_sync_inst (
        .clk     (clk),
        .rst_in  (sw_rst),
        .rst_out (rst)
    );

    debounce #(
        .STABLE_CYCLES (DEBOUNCE_CYCLES)
    ) start_button_inst (
        .clk     (clk),
        .rst     (rst),
        .btn_in  (btn_start),
        .pressed (start)
    );

    top top_inst (
        .clk              (clk),
        .rst              (rst),
        .start_ext        (start),
        .output_ext       (cls),
        .valid_output_ext (cls_valid)
    );

    assign led[0] = cls_valid;
    assign led[1] = cls_valid &  cls;
    assign led[2] = cls_valid & ~cls;

endmodule
