// ReLU on the 4-bit signed conv output: negative values become 0.
module conv_relu (
    input  logic [3:0] ofmap_in,        // signed
    output logic [3:0] ofmap_relu       // 0..7
);

    assign ofmap_relu = ofmap_in[3] ? 4'd0 : ofmap_in;

endmodule
