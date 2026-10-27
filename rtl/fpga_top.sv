// Board top level for the Nexys4 rev B (pins in vivado/nexys4.xdc). Conditions the switch and
// button inputs, loads the image selected by the switches into the CNN and shows the result on
// LEDs. The CNN itself is top.sv; image_loader holds the images and writes the selected one
// through top's load port before each run.
//
//   SW0      sw_rst     up = reset
//   SW1..8   sw_img     image number in binary (SW1 = LSB), 1..255; all off = image 256
//   BTNC     btn_start  press = load the selected image and classify it (one run per press,
//                       however long the button is held; top.sv itself would restart every
//                       3 cycles)
//   LED0     led[0]     result valid
//   LED1     led[1]     square
//   LED2     led[2]     circle
//   LED3     led[3]     the result matches the image's label
// The LEDs go dark when the switches no longer select the image that was classified.
module fpga_top #(
    parameter int DEBOUNCE_CYCLES = 1_000_000   // 10 ms at 100 MHz
) (
    input  logic       clk,
    input  logic       sw_rst,
    input  logic [7:0] sw_img,
    input  logic       btn_start,
    output logic [3:0] led
);

    logic        rst, pressed, start;
    logic        load_we;
    logic [5:0]  load_row;
    logic [63:0] load_data;
    logic        sel_match, label;
    logic        cls, cls_valid, shown;

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
        .pressed (pressed)
    );

    image_loader image_loader_inst (
        .clk       (clk),
        .rst       (rst),
        .sel_in    (sw_img),
        .go        (pressed),
        .load_we   (load_we),
        .load_row  (load_row),
        .load_data (load_data),
        .start     (start),
        .sel_match (sel_match),
        .label     (label)
    );

    top top_inst (
        .clk              (clk),
        .rst              (rst),
        .start_ext        (start),
        .load_we          (load_we),
        .load_row         (load_row),
        .load_data        (load_data),
        .output_ext       (cls),
        .valid_output_ext (cls_valid)
    );

    assign shown  = cls_valid & sel_match;
    assign led[0] = shown;
    assign led[1] = shown &  cls;
    assign led[2] = shown & ~cls;
    assign led[3] = shown & (cls == label);

endmodule
