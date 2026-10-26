// Reset synchronizer: asserts asynchronously, releases synchronously to clk, so that every
// flip-flop leaves reset in the same cycle.
module reset_sync (
    input  logic clk,
    input  logic rst_in,        // asynchronous, active high
    output logic rst_out
);

    logic [1:0] ff;

    always_ff @(posedge clk or posedge rst_in) begin
        if (rst_in)
            ff <= 2'b11;
        else
            ff <= {ff[0], 1'b0};
    end

    assign rst_out = ff[1];

endmodule
