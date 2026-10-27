// Image ROM and loader for the board: holds 256 test images, and on each go pulse copies the
// one selected by the switches into the conv layer's RAM through top's load port, then gives
// the start pulse.
//
// ROM entry n (0..255) is test image n, except entry 0, which is image 256: the switch value
// is the image number, with all switches off meaning 256. Each entry is 64 words of 64 bits,
// image row r at word 64 n + r, column c in bit c (as in the RAM banks). The files come from
//   uv run python tools/make_vectors.py board vivado/board
// IMAGE_FILE ($readmemh, 16384 words) and LABEL_FILE ($readmemb, 256 labels, 1 = square) are
// found by name: build_fpga.tcl and the GUI projects add them to the design.
//
// Timing: the ROM is a block RAM with two read registers. A load takes 64 + 3 cycles, then
// start is high for one cycle; the CNN only reads the RAM about 100 cycles after that.
module image_loader #(
    parameter IMAGE_FILE = "board_images.mem",
    parameter LABEL_FILE = "board_labels.mem"
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  sel_in,         // switches, asynchronous
    input  logic        go,             // one-cycle pulse: load the selected image and start
    output logic        load_we,
    output logic [5:0]  load_row,
    output logic [63:0] load_data,
    output logic        start,          // one-cycle pulse after the last row is written
    output logic        sel_match,      // the switches still select the loaded image
    output logic        label           // label of the loaded image (1 = square)
);

    typedef enum logic {IDLE, READ} state_t;
    state_t curr_state, next_state;

    logic [7:0]  sel_meta_q, sel_meta_d;    // switch synchronizer
    logic [7:0]  sel_sync_q, sel_sync_d;
    logic [7:0]  sel_q, sel_d;              // image being loaded / last loaded
    logic [5:0]  rd_q, rd_d;                // row read from the ROM
    logic        rd_en;
    logic [63:0] rom_q, data_q;             // ROM read registers
    logic        we1_q, we1_d, we2_q, we2_d;    // rows on their way through rom_q, data_q
    logic [5:0]  row1_q, row1_d, row2_q, row2_d;
    logic        start_q, start_d;

    logic [63:0] rom    [0:16383];
    logic        labels [0:255];

    initial $readmemh(IMAGE_FILE, rom);
    initial $readmemb(LABEL_FILE, labels);

    assign load_we   = we2_q;
    assign load_row  = row2_q;
    assign load_data = data_q;
    assign start     = start_q;
    assign sel_match = sel_sync_q == sel_q;
    assign label     = labels[sel_q];

    // ------------------------------------------------------------------
    // Sequential process
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            curr_state <= IDLE;
            sel_meta_q <= '0;
            sel_sync_q <= '0;
            sel_q      <= '0;
            rd_q       <= '0;
            we1_q      <= 1'b0;
            we2_q      <= 1'b0;
            row1_q     <= '0;
            row2_q     <= '0;
            start_q    <= 1'b0;
        end else begin
            curr_state <= next_state;
            sel_meta_q <= sel_meta_d;
            sel_sync_q <= sel_sync_d;
            sel_q      <= sel_d;
            rd_q       <= rd_d;
            we1_q      <= we1_d;
            we2_q      <= we2_d;
            row1_q     <= row1_d;
            row2_q     <= row2_d;
            start_q    <= start_d;
        end
    end

    // ROM read port, block RAM template (no reset, so that both registers go into the RAM)
    always_ff @(posedge clk) begin
        if (rd_en)
            rom_q <= rom[{sel_q, rd_q}];
        data_q <= rom_q;
    end

    // ------------------------------------------------------------------
    // Combinational process
    // ------------------------------------------------------------------
    always_comb begin
        next_state = curr_state;
        sel_meta_d = sel_in;
        sel_sync_d = sel_meta_q;
        sel_d      = sel_q;
        rd_d       = rd_q;
        rd_en      = 1'b0;

        case (curr_state)
            IDLE: begin
                rd_d = '0;
                if (go) begin
                    sel_d      = sel_sync_q;
                    next_state = READ;
                end
            end

            READ: begin
                rd_en = 1'b1;
                rd_d  = rd_q + 1;
                if (rd_q == 6'd63)
                    next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase

        // Row rd_q is in rom_q one cycle later and in data_q (written) two cycles later
        we1_d   = rd_en;
        row1_d  = rd_q;
        we2_d   = we1_q;
        row2_d  = row1_q;
        start_d = we2_q && row2_q == 6'd63;
    end

endmodule
