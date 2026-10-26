// Accumulator: adds the four row partial sums and the bias, saturates the result to the
// 4-bit signed conv output (-8..7) and registers it.
//
// Saturation matches the reference design. On the test images the raw sums span -9..+4, so
// only the most negative values are clipped, and those become 0 after the ReLU anyway.
module conv_accumulator #(
    parameter int BIAS = 0
) (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] psum_1,          // signed
    input  logic [7:0] psum_2,
    input  logic [7:0] psum_3,
    input  logic [7:0] psum_4,
    input  logic       valid_in,
    output logic [3:0] ofmap,           // signed
    output logic       valid_ofmap
);

    logic signed [9:0] sum;
    logic signed [3:0] sat;

    assign sum = $signed(psum_1) + $signed(psum_2) + $signed(psum_3) + $signed(psum_4)
               + 10'(BIAS);

    always_comb begin
        if (sum > 10'sd7)
            sat = 4'sd7;
        else if (sum < -10'sd8)
            sat = -4'sd8;
        else
            sat = sum[3:0];
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ofmap       <= '0;
            valid_ofmap <= 1'b0;
        end else begin
            ofmap       <= sat;
            valid_ofmap <= valid_in;
        end
    end

endmodule
