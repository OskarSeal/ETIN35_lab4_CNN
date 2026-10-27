// PE array: four PEs, one per window row, with the filter weight register and the four
// 64-bit row registers that slide the window over the image one column per cycle.
//
// The 16 filter weights arrive row-major on f_in (one per valid_in_f, from top_initialize)
// and are shifted in from the top, so after 16 values weight k*4 + j (window row k, column j)
// sits in bits [4*(k*4 + j) +: 4] of weights_q, and PE k gets bits [16*k +: 16].
module conv_pe_array (
    input  logic        clk,
    input  logic        rst,
    input  logic [3:0]  f_in,
    input  logic        valid_in_f,
    input  logic [63:0] ifmap_1,        // image rows r .. r+3, column c in bit c
    input  logic [63:0] ifmap_2,
    input  logic [63:0] ifmap_3,
    input  logic [63:0] ifmap_4,
    input  logic        load_rows,
    input  logic        shift_rows,
    input  logic        window_valid,
    output logic [7:0]  psum_1,         // signed partial sums of window rows 0..3
    output logic [7:0]  psum_2,
    output logic [7:0]  psum_3,
    output logic [7:0]  psum_4,
    output logic        valid_psum
);

    logic [63:0] weights_q, weights_d;
    logic [63:0] rows_q [4], rows_d [4];    // bits [3:0] of rows_q[k] are window row k

    // ------------------------------------------------------------------
    // Sequential process
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            weights_q  <= '0;
            rows_q     <= '{default: '0};
            valid_psum <= 1'b0;
        end else begin
            weights_q  <= weights_d;
            rows_q     <= rows_d;
            valid_psum <= window_valid;
        end
    end

    // ------------------------------------------------------------------
    // Combinational process: weight shift register and row registers
    // ------------------------------------------------------------------
    always_comb begin
        weights_d = weights_q;
        rows_d    = rows_q;

        if (valid_in_f)
            weights_d = {f_in, weights_q[63:4]};

        if (load_rows)
            rows_d = '{ifmap_1, ifmap_2, ifmap_3, ifmap_4};
        else if (shift_rows)
            rows_d = '{rows_q[0] >> 1, rows_q[1] >> 1, rows_q[2] >> 1, rows_q[3] >> 1};
    end

    // ------------------------------------------------------------------
    // PEs
    // ------------------------------------------------------------------
    conv_pe PE_1_inst (
        .clk     (clk),
        .rst     (rst),
        .pixels  (rows_q[0][3:0]),
        .weights (weights_q[15:0]),
        .psum    (psum_1)
    );

    conv_pe PE_2_inst (
        .clk     (clk),
        .rst     (rst),
        .pixels  (rows_q[1][3:0]),
        .weights (weights_q[31:16]),
        .psum    (psum_2)
    );

    conv_pe PE_3_inst (
        .clk     (clk),
        .rst     (rst),
        .pixels  (rows_q[2][3:0]),
        .weights (weights_q[47:32]),
        .psum    (psum_3)
    );

    conv_pe PE_4_inst (
        .clk     (clk),
        .rst     (rst),
        .pixels  (rows_q[3][3:0]),
        .weights (weights_q[63:48]),
        .psum    (psum_4)
    );

endmodule
