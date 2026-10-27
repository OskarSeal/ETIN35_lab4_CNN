// Max-pooling layer (own RTL): 15x15 tiles with stride 15 over the 61 x 61 ReLU output.
//
// The conv layer streams its outputs row-major, one per valid_data. Row and column 61 are not
// covered by any tile and are skipped. Only one running maximum per tile column is kept (the
// feature map is never stored), and each of the 16 maxima is emitted as soon as its tile is
// complete, i.e. in row-major tile order. Accepts a new value every cycle.
//
// Same name and ports as the reference Pooling_TOP, so network_top is unchanged.
module Pooling_TOP (
    input  logic       clk,
    input  logic       rst,
    input  logic [3:0] ofmap_RELU,      // 0..7 after the ReLU
    input  logic       valid_data,
    output logic [3:0] pooling_out,
    output logic       valid_pooling
);

    localparam int TILE  = 15;
    localparam int TILES = 4;           // tile index TILES = the uncovered last row / column

    // Position in the 61 x 61 stream
    logic [3:0] col_in_tile_q, col_in_tile_d;
    logic [3:0] row_in_tile_q, row_in_tile_d;
    logic [2:0] tile_col_q, tile_col_d;
    logic [2:0] tile_row_q, tile_row_d;

    // Running maxima and output
    logic [3:0] running_max_q [TILES], running_max_d [TILES];
    logic [3:0] out_q, out_d;
    logic       valid_q, valid_d;

    logic       covered, tile_done;
    logic [3:0] new_max;

    assign pooling_out   = out_q;
    assign valid_pooling = valid_q;

    // ------------------------------------------------------------------
    // Sequential process
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            col_in_tile_q <= '0;
            row_in_tile_q <= '0;
            tile_col_q    <= '0;
            tile_row_q    <= '0;
            running_max_q <= '{default: '0};
            out_q         <= '0;
            valid_q       <= 1'b0;
        end else begin
            col_in_tile_q <= col_in_tile_d;
            row_in_tile_q <= row_in_tile_d;
            tile_col_q    <= tile_col_d;
            tile_row_q    <= tile_row_d;
            running_max_q <= running_max_d;
            out_q         <= out_d;
            valid_q       <= valid_d;
        end
    end

    // ------------------------------------------------------------------
    // Combinational process: running maxima and output
    // ------------------------------------------------------------------
    assign covered   = (tile_col_q != TILES) && (tile_row_q != TILES);
    assign tile_done = (col_in_tile_q == TILE - 1) && (row_in_tile_q == TILE - 1);
    assign new_max   = (ofmap_RELU > running_max_q[tile_col_q[1:0]]) ? ofmap_RELU
                                                                     : running_max_q[tile_col_q[1:0]];

    always_comb begin
        running_max_d = running_max_q;
        out_d         = out_q;
        valid_d       = 1'b0;

        if (valid_data && covered) begin
            if (tile_done) begin
                out_d                          = new_max;
                valid_d                        = 1'b1;
                running_max_d[tile_col_q[1:0]] = '0;
            end else begin
                running_max_d[tile_col_q[1:0]] = new_max;
            end
        end
    end

    // ------------------------------------------------------------------
    // Combinational process: position in the 61 x 61 stream
    // ------------------------------------------------------------------
    always_comb begin
        col_in_tile_d = col_in_tile_q;
        row_in_tile_d = row_in_tile_q;
        tile_col_d    = tile_col_q;
        tile_row_d    = tile_row_q;

        if (valid_data) begin
            if (tile_col_q == TILES) begin              // last column: next row
                col_in_tile_d = '0;
                tile_col_d    = '0;
                if (tile_row_q == TILES) begin          // last row: image done
                    row_in_tile_d = '0;
                    tile_row_d    = '0;
                end else if (row_in_tile_q == TILE - 1) begin
                    row_in_tile_d = '0;
                    tile_row_d    = tile_row_q + 1;
                end else begin
                    row_in_tile_d = row_in_tile_q + 1;
                end
            end else if (col_in_tile_q == TILE - 1) begin
                col_in_tile_d = '0;
                tile_col_d    = tile_col_q + 1;
            end else begin
                col_in_tile_d = col_in_tile_q + 1;
            end
        end
    end

endmodule
