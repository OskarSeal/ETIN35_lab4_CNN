// One processing element: the partial sum of one window row.
// Pixels are 0/1, so each "multiplication" just selects the weight or 0.
module conv_pe (
    input  logic        clk,
    input  logic        rst,
    input  logic [3:0]  pixels,     // bit j = window column j
    input  logic [15:0] weights,    // weights[4*j +: 4] = signed weight of window column j
    output logic [7:0]  psum        // signed, registered
);

    logic signed [7:0] sum;

    // ------------------------------------------------------------------
    // Combinational process
    // ------------------------------------------------------------------
    always_comb begin
        sum = (pixels[0] ? $signed(weights[3:0])   : 8'sd0)
            + (pixels[1] ? $signed(weights[7:4])   : 8'sd0)
            + (pixels[2] ? $signed(weights[11:8])  : 8'sd0)
            + (pixels[3] ? $signed(weights[15:12]) : 8'sd0);
    end

    // ------------------------------------------------------------------
    // Sequential process
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            psum <= '0;
        else
            psum <= sum;
    end

endmodule
