// Convolution controller: walks the 4x4 window over the 64x64 image, one window per cycle,
// row by row (61 x 61 windows, row-major).
//
// The image is held in four 16 x 64 RAM banks interleaved by row: bank b holds rows b, b+4,
// ..., with column c in bit c. For window row r the controller addresses rows r..r+3 and sets
// count_def = r mod 4, so that RAM_IP_TOP presents them in order on data_out_1..4. The PE
// array loads those four rows once per window row and then shifts them one column per cycle,
// so the RAM is always addressed one window row ahead (row_fetch) and there are no bubbles.
module conv_controller (
    input  logic        clk,
    input  logic        rst,
    input  logic        start_in,
    // RAM ports. The image is preloaded, so the write side is tied off.
    output logic [63:0] data_1,
    output logic [63:0] data_2,
    output logic [63:0] data_3,
    output logic [63:0] data_4,
    output logic [3:0]  address_1,
    output logic [3:0]  address_2,
    output logic [3:0]  address_3,
    output logic [3:0]  address_4,
    output logic        csn_1,
    output logic        csn_2,
    output logic        csn_3,
    output logic        csn_4,
    output logic        wen_1,
    output logic        wen_2,
    output logic        wen_3,
    output logic        wen_4,
    output logic [1:0]  count_def,
    // PE array control
    output logic        load_rows,      // load data_out_1..4 into the row registers
    output logic        shift_rows,     // move the window one column to the right
    output logic        window_valid,   // the row registers hold a valid window
    output logic        finish          // last window of the image
);

    localparam int LAST = 60;           // last window row / column (61 x 61 windows)

    typedef enum logic [1:0] {IDLE, LOAD, RUN} state_t;
    state_t curr_state, next_state;

    logic [5:0] row_q, row_d;           // window row being processed
    logic [5:0] col_q, col_d;           // window column being processed
    logic [5:0] fetch_q, fetch_d;       // window row the RAM is addressed for

    // ------------------------------------------------------------------
    // Sequential process
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            curr_state <= IDLE;
            row_q      <= '0;
            col_q      <= '0;
            fetch_q    <= '0;
        end else begin
            curr_state <= next_state;
            row_q      <= row_d;
            col_q      <= col_d;
            fetch_q    <= fetch_d;
        end
    end

    // ------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------
    always_comb begin
        next_state   = curr_state;
        row_d        = row_q;
        col_d        = col_q;
        fetch_d      = fetch_q;
        load_rows    = 1'b0;
        shift_rows   = 1'b0;
        window_valid = 1'b0;
        finish       = 1'b0;

        case (curr_state)
            IDLE: begin
                fetch_d = '0;
                if (start_in)
                    next_state = LOAD;
            end

            // RAM addressed for window row 0: load it and start fetching row 1
            LOAD: begin
                load_rows  = 1'b1;
                row_d      = '0;
                col_d      = '0;
                fetch_d    = 6'd1;
                next_state = RUN;
            end

            RUN: begin
                window_valid = 1'b1;
                if (col_q != LAST) begin
                    shift_rows = 1'b1;
                    col_d      = col_q + 1;
                end else if (row_q != LAST) begin
                    load_rows = 1'b1;
                    row_d     = row_q + 1;
                    col_d     = '0;
                    fetch_d   = fetch_q + 1;
                end else begin
                    finish     = 1'b1;
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // ------------------------------------------------------------------
    // RAM addressing: bank b holds row fetch + i where (fetch + i) mod 4 = b,
    // i.e. address fetch / 4, plus one for the banks "behind" fetch mod 4.
    // ------------------------------------------------------------------
    assign count_def = fetch_q[1:0];
    assign address_1 = fetch_q[5:2] + 4'(fetch_q[1:0] > 2'd0);
    assign address_2 = fetch_q[5:2] + 4'(fetch_q[1:0] > 2'd1);
    assign address_3 = fetch_q[5:2] + 4'(fetch_q[1:0] > 2'd2);
    assign address_4 = fetch_q[5:2];

    assign data_1 = '0;
    assign data_2 = '0;
    assign data_3 = '0;
    assign data_4 = '0;
    assign csn_1  = 1'b0;
    assign csn_2  = 1'b0;
    assign csn_3  = 1'b0;
    assign csn_4  = 1'b0;
    assign wen_1  = 1'b0;
    assign wen_2  = 1'b0;
    assign wen_3  = 1'b0;
    assign wen_4  = 1'b0;

endmodule
