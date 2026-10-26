// PE array: four PEs, one per window row, with the filter weight registers and the four
// 64-bit row registers that slide the window over the image one column per cycle.
//
// The 16 filter weights arrive row-major on f_in (one per valid_in_f, from top_initialize)
// and are shifted in, so after 16 values weight k*4 + j sits at index k*4 + j.
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

    logic [3:0]  weights [16];
    logic [63:0] rows [4];
    logic [7:0]  psum [4];

    // ------------------------------------------------------------------
    // Filter weights
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            weights <= '{default: '0};
        end else if (valid_in_f) begin
            for (int i = 0; i < 15; i++)
                weights[i] <= weights[i+1];
            weights[15] <= f_in;
        end
    end

    // ------------------------------------------------------------------
    // Row registers: bits [3:0] of rows[k] are window row k
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rows <= '{default: '0};
        end else if (load_rows) begin
            rows <= '{ifmap_1, ifmap_2, ifmap_3, ifmap_4};
        end else if (shift_rows) begin
            for (int k = 0; k < 4; k++)
                rows[k] <= rows[k] >> 1;
        end
    end

    // ------------------------------------------------------------------
    // PEs
    // ------------------------------------------------------------------
    for (genvar k = 0; k < 4; k++) begin : gen_pe
        conv_pe PE_inst (
            .clk     (clk),
            .rst     (rst),
            .pixels  (rows[k][3:0]),
            .weights ({weights[4*k+3], weights[4*k+2], weights[4*k+1], weights[4*k]}),
            .psum    (psum[k])
        );
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            valid_psum <= 1'b0;
        else
            valid_psum <= window_valid;
    end

    assign psum_1 = psum[0];
    assign psum_2 = psum[1];
    assign psum_3 = psum[2];
    assign psum_4 = psum[3];

endmodule
