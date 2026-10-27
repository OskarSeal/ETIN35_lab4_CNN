// Reset synchronizer: asserts asynchronously, releases synchronously to clk, so that every
// flip-flop leaves reset in the same cycle.
module reset_sync (
    input  logic clk,
    input  logic rst_in,        // asynchronous, active high
    output logic rst_out
);

    logic [1:0] ff_q, ff_d;

    // ------------------------------------------------------------------
    // Sequential process
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst_in) begin
        if (rst_in)
            ff_q <= 2'b11;
        else
            ff_q <= ff_d;
    end

    // ------------------------------------------------------------------
    // Combinational process
    // ------------------------------------------------------------------
    assign ff_d    = {ff_q[0], 1'b0};
    assign rst_out = ff_q[1];

endmodule
