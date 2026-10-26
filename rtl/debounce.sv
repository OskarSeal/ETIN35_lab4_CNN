// Push-button conditioning: two-flop synchronizer, debounce (the input must be stable for
// STABLE_CYCLES clock cycles before the debounced level follows it) and a one-cycle pulse on
// each press. Holding the button gives a single pulse, however long it is held.
module debounce #(
    parameter int STABLE_CYCLES = 1_000_000     // 10 ms at 100 MHz
) (
    input  logic clk,
    input  logic rst,
    input  logic btn_in,        // asynchronous, active high
    output logic pressed        // one-cycle pulse when the debounced level goes high
);

    localparam int CW = $clog2(STABLE_CYCLES + 1);

    logic [1:0]    sync;
    logic          level;
    logic [CW-1:0] count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sync    <= '0;
            level   <= 1'b0;
            count   <= '0;
            pressed <= 1'b0;
        end else begin
            sync    <= {sync[0], btn_in};
            pressed <= 1'b0;
            if (sync[1] == level) begin
                count <= '0;
            end else if (count == CW'(STABLE_CYCLES - 1)) begin
                level   <= sync[1];
                count   <= '0;
                pressed <= sync[1];
            end else begin
                count <= count + 1;
            end
        end
    end

endmodule
