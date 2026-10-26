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

    logic [3:0] col_in_tile, row_in_tile;
    logic [2:0] tile_col, tile_row;
    logic [3:0] running_max [TILES];

    logic       covered, tile_done;
    logic [3:0] new_max;

    assign covered   = (tile_col != TILES) && (tile_row != TILES);
    assign tile_done = (col_in_tile == TILE - 1) && (row_in_tile == TILE - 1);
    assign new_max   = (ofmap_RELU > running_max[tile_col[1:0]]) ? ofmap_RELU
                                                                 : running_max[tile_col[1:0]];

    // ------------------------------------------------------------------
    // Running maxima and output
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            running_max   <= '{default: '0};
            pooling_out   <= '0;
            valid_pooling <= 1'b0;
        end else begin
            valid_pooling <= 1'b0;
            if (valid_data && covered) begin
                if (tile_done) begin
                    pooling_out                  <= new_max;
                    valid_pooling                <= 1'b1;
                    running_max[tile_col[1:0]]   <= '0;
                end else begin
                    running_max[tile_col[1:0]]   <= new_max;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Position in the 61 x 61 stream
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            col_in_tile <= '0;
            tile_col    <= '0;
            row_in_tile <= '0;
            tile_row    <= '0;
        end else if (valid_data) begin
            if (tile_col == TILES) begin                // last column: next row
                col_in_tile <= '0;
                tile_col    <= '0;
                if (tile_row == TILES) begin            // last row: image done
                    row_in_tile <= '0;
                    tile_row    <= '0;
                end else if (row_in_tile == TILE - 1) begin
                    row_in_tile <= '0;
                    tile_row    <= tile_row + 1;
                end else begin
                    row_in_tile <= row_in_tile + 1;
                end
            end else if (col_in_tile == TILE - 1) begin
                col_in_tile <= '0;
                tile_col    <= tile_col + 1;
            end else begin
                col_in_tile <= col_in_tile + 1;
            end
        end
    end

endmodule
