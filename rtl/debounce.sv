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

    logic [1:0]    sync_q, sync_d;
    logic          level_q, level_d;
    logic [CW-1:0] count_q, count_d;
    logic          pressed_q, pressed_d;

    assign pressed = pressed_q;

    // ------------------------------------------------------------------
    // Sequential process
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sync_q    <= '0;
            level_q   <= 1'b0;
            count_q   <= '0;
            pressed_q <= 1'b0;
        end else begin
            sync_q    <= sync_d;
            level_q   <= level_d;
            count_q   <= count_d;
            pressed_q <= pressed_d;
        end
    end

    // ------------------------------------------------------------------
    // Combinational process
    // ------------------------------------------------------------------
    always_comb begin
        sync_d    = {sync_q[0], btn_in};
        level_d   = level_q;
        count_d   = count_q;
        pressed_d = 1'b0;

        if (sync_q[1] == level_q) begin
            count_d = '0;
        end else if (count_q == CW'(STABLE_CYCLES - 1)) begin
            level_d   = sync_q[1];
            count_d   = '0;
            pressed_d = sync_q[1];
        end else begin
            count_d = count_q + 1;
        end
    end

endmodule
