// Fully connected layers (own RTL): FC1 (16 -> 3) + ReLU, FC2 (3 -> 1) and the output
// "sigmoid". sigmoid(x) > 0.5 <=> x > 0, so the hardware-friendly sigmoid is a sign check:
// class 1 (square) when FC2 > 0, else 0 (circle).
//
// Weights are streamed in by top_initialize and shifted into registers from the top: 48 FC1
// weights, index k*16 + m for neuron k and pooled position m (row-major tiles), in bits
// [4*(k*16 + m) +: 4] of w1_q, then 3 FC2 weights, weight k in bits [4*k +: 4] of w2_q.
// Biases are not streamed by the design, so they are parameters here
// (matlab_model/fully_connect.m).
//
// The pooled values arrive one at a time; each is multiplied with the three FC1 weights of its
// position as it comes in, and the accumulators start at the biases, so FC1 is complete one
// cycle after the 16th value. The rest is a short pipeline (ReLU, FC2 products, FC2 sum,
// sign), one stage per cycle.
//
// Widths cover any 4-bit signed weights and the full 4-bit input range (0..15):
// |FC1| <= 16 * 8 * 15 + bias < 2048 -> 12 bits signed, |FC2| <= 3 * 8 * 2047 + bias -> 17 bits.
//
// Same name and ports as the reference FC_TOP, so network_top is unchanged.
module FC_TOP #(
    parameter int FC1_BIAS [3] = '{-12, 20, 24},
    parameter int FC2_BIAS     = 6
) (
    input  logic       clk,
    input  logic       rst,
    input  logic [3:0] kernel_FC1_in,
    input  logic       valid_FC1_in,
    input  logic [3:0] kernel_FC2_in,
    input  logic       valid_FC2_in,
    input  logic [3:0] pooling,         // 0..15, unsigned
    input  logic       valid_pooling,
    output logic       fc_output,
    output logic       valid_output
);

    localparam int N_IN = 16;
    localparam int W1   = 12;           // FC1 accumulator width (signed)
    localparam int W2   = 17;           // FC2 sum width (signed)

    // Weight registers
    logic [191:0]         w1_q, w1_d;
    logic [11:0]          w2_q, w2_d;

    // Stage 0: pooled value with the FC1 weights of its position
    logic [3:0]           pos_q, pos_d;         // position of the next pooled value
    logic [3:0]           in_q, in_d;
    logic [3:0]           w_q [3], w_d [3];
    logic                 mac_q, last_q, last_d;

    // Stage 1: FC1 accumulators
    logic signed [W1-1:0] acc_q [3], acc_d [3];
    logic                 fc1_done_q, fc1_done_d;

    // Stage 2: ReLU
    logic [W1-2:0]        hid_q [3], hid_d [3]; // 0 .. 2^(W1-1) - 1
    logic                 hid_valid_q;

    // Stage 3: FC2 products
    logic signed [W2-1:0] prod_q [3], prod_d [3];
    logic                 prod_valid_q;

    // Stage 4: FC2 sum + bias
    logic signed [W2-1:0] fc2_q, fc2_d;
    logic                 fc2_valid_q;

    // Stage 5: class
    logic                 cls_q, cls_d;
    logic                 cls_valid_q;

    assign fc_output    = cls_q;
    assign valid_output = cls_valid_q;

    // ------------------------------------------------------------------
    // Sequential process
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            w1_q         <= '0;
            w2_q         <= '0;
            pos_q        <= '0;
            in_q         <= '0;
            w_q          <= '{default: '0};
            mac_q        <= 1'b0;
            last_q       <= 1'b0;
            acc_q        <= '{W1'(FC1_BIAS[0]), W1'(FC1_BIAS[1]), W1'(FC1_BIAS[2])};
            fc1_done_q   <= 1'b0;
            hid_q        <= '{default: '0};
            hid_valid_q  <= 1'b0;
            prod_q       <= '{default: '0};
            prod_valid_q <= 1'b0;
            fc2_q        <= '0;
            fc2_valid_q  <= 1'b0;
            cls_q        <= 1'b0;
            cls_valid_q  <= 1'b0;
        end else begin
            w1_q         <= w1_d;
            w2_q         <= w2_d;
            pos_q        <= pos_d;
            in_q         <= in_d;
            w_q          <= w_d;
            mac_q        <= valid_pooling;
            last_q       <= last_d;
            acc_q        <= acc_d;
            fc1_done_q   <= fc1_done_d;
            hid_q        <= hid_d;
            hid_valid_q  <= fc1_done_q;
            prod_q       <= prod_d;
            prod_valid_q <= hid_valid_q;
            fc2_q        <= fc2_d;
            fc2_valid_q  <= prod_valid_q;
            cls_q        <= cls_d;
            cls_valid_q  <= fc2_valid_q;
        end
    end

    // ------------------------------------------------------------------
    // Weight shift registers
    // ------------------------------------------------------------------
    always_comb begin
        w1_d = w1_q;
        w2_d = w2_q;
        if (valid_FC1_in)
            w1_d = {kernel_FC1_in, w1_q[191:4]};
        if (valid_FC2_in)
            w2_d = {kernel_FC2_in, w2_q[11:4]};
    end

    // ------------------------------------------------------------------
    // Stage 0: register the pooled value with the FC1 weights of its position
    // ------------------------------------------------------------------
    always_comb begin
        pos_d  = pos_q;
        in_d   = in_q;
        w_d    = w_q;
        last_d = last_q;
        if (valid_pooling) begin
            in_d   = pooling;
            w_d[0] = w1_q[      4*pos_q +: 4];
            w_d[1] = w1_q[ 64 + 4*pos_q +: 4];
            w_d[2] = w1_q[128 + 4*pos_q +: 4];
            last_d = (pos_q == N_IN - 1);
            pos_d  = pos_q + 1;             // wraps to 0 after the 16th value
        end
    end

    // ------------------------------------------------------------------
    // Stage 1: FC1 multiply-accumulate, starting from the biases. The accumulators restart
    // from the bias once the result has been taken (fc1_done_q).
    // ------------------------------------------------------------------
    always_comb begin
        fc1_done_d = mac_q && last_q;
        acc_d[0] = (fc1_done_q ? W1'(FC1_BIAS[0]) : acc_q[0])
                 + (mac_q ? W1'($signed(w_q[0]) * $signed({1'b0, in_q})) : W1'(0));
        acc_d[1] = (fc1_done_q ? W1'(FC1_BIAS[1]) : acc_q[1])
                 + (mac_q ? W1'($signed(w_q[1]) * $signed({1'b0, in_q})) : W1'(0));
        acc_d[2] = (fc1_done_q ? W1'(FC1_BIAS[2]) : acc_q[2])
                 + (mac_q ? W1'($signed(w_q[2]) * $signed({1'b0, in_q})) : W1'(0));
    end

    // ------------------------------------------------------------------
    // Stage 2: ReLU
    // ------------------------------------------------------------------
    always_comb begin
        hid_d = hid_q;
        if (fc1_done_q) begin
            hid_d[0] = acc_q[0][W1-1] ? '0 : acc_q[0][W1-2:0];
            hid_d[1] = acc_q[1][W1-1] ? '0 : acc_q[1][W1-2:0];
            hid_d[2] = acc_q[2][W1-1] ? '0 : acc_q[2][W1-2:0];
        end
    end

    // ------------------------------------------------------------------
    // Stage 3: FC2 products
    // ------------------------------------------------------------------
    always_comb begin
        prod_d = prod_q;
        if (hid_valid_q) begin
            prod_d[0] = W2'($signed(w2_q[3:0])  * $signed({1'b0, hid_q[0]}));
            prod_d[1] = W2'($signed(w2_q[7:4])  * $signed({1'b0, hid_q[1]}));
            prod_d[2] = W2'($signed(w2_q[11:8]) * $signed({1'b0, hid_q[2]}));
        end
    end

    // ------------------------------------------------------------------
    // Stage 4: FC2 sum + bias
    // ------------------------------------------------------------------
    always_comb begin
        fc2_d = fc2_q;
        if (prod_valid_q)
            fc2_d = prod_q[0] + prod_q[1] + prod_q[2] + W2'(FC2_BIAS);
    end

    // ------------------------------------------------------------------
    // Stage 5: sigmoid as a sign check -> class
    // ------------------------------------------------------------------
    always_comb begin
        cls_d = cls_q;
        if (fc2_valid_q)
            cls_d = (fc2_q > 0);
    end

endmodule
