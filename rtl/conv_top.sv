// Convolution layer (own RTL): 4x4 conv over the 64x64 image in the RAM banks, saturated to
// 4-bit signed, then ReLU. Streams the 61 x 61 outputs row-major, one per cycle.
//
// Same ports as the reference wrapper top/conv_top.sv, so either can sit in network_top. The
// instance and signal names RAM_inst, ofmap_conv, valid_ofmap_conv and ofmap_relu are also
// kept: sim/tb_cnn.sv loads images through RAM_inst and monitors those signals.
module conv_top (
    input  logic         clk,
    input  logic         rst,
    input  logic         start_in,
    input  logic  [3:0]  f_in,
    input  logic         valid_in_f,
    input  logic         load_we,       // image load port: write load_data into image row
    input  logic  [5:0]  load_row,      // load_row of the RAM (only while idle)
    input  logic  [63:0] load_data,
    output logic  [3:0]  ofmap,
    output logic         valid_ofmap
);

    // Memory related signals
    logic [63:0] data_1, data_2, data_3, data_4;
    logic [3:0]  addr_1, addr_2, addr_3, addr_4;
    logic        csn_1, csn_2, csn_3, csn_4;
    logic        wen_1, wen_2, wen_3, wen_4;
    logic [1:0]  count_def;
    logic [63:0] ifmap_1, ifmap_2, ifmap_3, ifmap_4;

    // Window / calculation related signals
    logic        load_rows, shift_rows, window_valid, finish;
    logic [7:0]  Psum1, Psum2, Psum3, Psum4;
    logic        valid_psum;

    // Accumulator / RELU related signals
    logic [3:0]  ofmap_conv, ofmap_relu;
    logic        valid_ofmap_conv;

    assign ofmap       = ofmap_relu;
    assign valid_ofmap = valid_ofmap_conv;

    // ------------------------------------------------------------------
    // Component instantiations
    // ------------------------------------------------------------------
    conv_controller Controller_inst (
        .clk          (clk),
        .rst          (rst),
        .start_in     (start_in),
        .load_we      (load_we),
        .load_row     (load_row),
        .load_data    (load_data),
        .data_1       (data_1),
        .data_2       (data_2),
        .data_3       (data_3),
        .data_4       (data_4),
        .address_1    (addr_1),
        .address_2    (addr_2),
        .address_3    (addr_3),
        .address_4    (addr_4),
        .csn_1        (csn_1),
        .csn_2        (csn_2),
        .csn_3        (csn_3),
        .csn_4        (csn_4),
        .wen_1        (wen_1),
        .wen_2        (wen_2),
        .wen_3        (wen_3),
        .wen_4        (wen_4),
        .count_def    (count_def),
        .load_rows    (load_rows),
        .shift_rows   (shift_rows),
        .window_valid (window_valid),
        .finish       (finish)
    );

    RAM_IP_TOP RAM_inst (
        .clk         (clk),
        .data_1      (data_1),
        .data_2      (data_2),
        .data_3      (data_3),
        .data_4      (data_4),
        .address_1   (addr_1),
        .address_2   (addr_2),
        .address_3   (addr_3),
        .address_4   (addr_4),
        .csn_1       (csn_1),
        .csn_2       (csn_2),
        .csn_3       (csn_3),
        .csn_4       (csn_4),
        .wen_1       (wen_1),
        .wen_2       (wen_2),
        .wen_3       (wen_3),
        .wen_4       (wen_4),
        .count_def   (count_def),
        .data_out_1  (ifmap_1),
        .data_out_2  (ifmap_2),
        .data_out_3  (ifmap_3),
        .data_out_4  (ifmap_4)
    );

    conv_pe_array PE_TOP_inst (
        .clk          (clk),
        .rst          (rst),
        .f_in         (f_in),
        .valid_in_f   (valid_in_f),
        .ifmap_1      (ifmap_1),
        .ifmap_2      (ifmap_2),
        .ifmap_3      (ifmap_3),
        .ifmap_4      (ifmap_4),
        .load_rows    (load_rows),
        .shift_rows   (shift_rows),
        .window_valid (window_valid),
        .psum_1       (Psum1),
        .psum_2       (Psum2),
        .psum_3       (Psum3),
        .psum_4       (Psum4),
        .valid_psum   (valid_psum)
    );

    conv_accumulator Accumulator_inst (
        .clk         (clk),
        .rst         (rst),
        .psum_1      (Psum1),
        .psum_2      (Psum2),
        .psum_3      (Psum3),
        .psum_4      (Psum4),
        .valid_in    (valid_psum),
        .ofmap       (ofmap_conv),
        .valid_ofmap (valid_ofmap_conv)
    );

    conv_relu RELU_inst (
        .ofmap_in    (ofmap_conv),
        .ofmap_relu  (ofmap_relu)
    );

endmodule
