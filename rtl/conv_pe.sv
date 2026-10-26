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

    always_comb begin
        sum = '0;
        for (int j = 0; j < 4; j++)
            if (pixels[j])
                sum = sum + $signed(weights[4*j +: 4]);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            psum <= '0;
        else
            psum <= sum;
    end

endmodule
