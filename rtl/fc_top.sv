// Fully connected layers (own RTL): FC1 (16 -> 3) + ReLU, FC2 (3 -> 1) and the output
// "sigmoid". sigmoid(x) > 0.5 <=> x > 0, so the hardware-friendly sigmoid is a sign check:
// class 1 (square) when FC2 > 0, else 0 (circle).
//
// Weights are streamed in by top_initialize and shifted into registers: 48 FC1 weights,
// index k*16 + m for neuron k and pooled position m (row-major tiles), then 3 FC2 weights.
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

    localparam int N_IN  = 16;
    localparam int N_HID = 3;
    localparam int W1    = 12;          // FC1 accumulator width (signed)
    localparam int W2    = 17;          // FC2 sum width (signed)

    // ------------------------------------------------------------------
    // Weight registers
    // ------------------------------------------------------------------
    logic [3:0] w1 [N_HID*N_IN];
    logic [3:0] w2 [N_HID];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            w1 <= '{default: '0};
            w2 <= '{default: '0};
        end else begin
            if (valid_FC1_in) begin
                for (int i = 0; i < N_HID*N_IN - 1; i++)
                    w1[i] <= w1[i+1];
                w1[N_HID*N_IN - 1] <= kernel_FC1_in;
            end
            if (valid_FC2_in) begin
                for (int i = 0; i < N_HID - 1; i++)
                    w2[i] <= w2[i+1];
                w2[N_HID - 1] <= kernel_FC2_in;
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage 0: register the pooled value with the FC1 weights of its position
    // ------------------------------------------------------------------
    logic [3:0] pos;                    // position of the next pooled value
    logic [3:0] in_q;
    logic [3:0] w_q [N_HID];
    logic       mac_q, last_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pos    <= '0;
            in_q   <= '0;
            w_q    <= '{default: '0};
            mac_q  <= 1'b0;
            last_q <= 1'b0;
        end else begin
            mac_q <= valid_pooling;
            if (valid_pooling) begin
                in_q   <= pooling;
                for (int k = 0; k < N_HID; k++)
                    w_q[k] <= w1[k*N_IN + pos];
                last_q <= (pos == N_IN - 1);
                pos    <= pos + 1;          // wraps to 0 after the 16th value
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage 1: FC1 multiply-accumulate, starting from the biases
    // ------------------------------------------------------------------
    logic signed [W1-1:0] acc [N_HID];
    logic                 fc1_done;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int k = 0; k < N_HID; k++)
                acc[k] <= W1'(FC1_BIAS[k]);
            fc1_done <= 1'b0;
        end else begin
            fc1_done <= mac_q && last_q;
            for (int k = 0; k < N_HID; k++)
                // Restart from the bias once the result has been taken (fc1_done)
                acc[k] <= (fc1_done ? W1'(FC1_BIAS[k]) : acc[k])
                        + (mac_q ? W1'($signed(w_q[k]) * $signed({1'b0, in_q})) : W1'(0));
        end
    end

    // ------------------------------------------------------------------
    // Stage 2: ReLU
    // ------------------------------------------------------------------
    logic [W1-2:0] hid [N_HID];         // 0 .. 2^(W1-1) - 1
    logic          hid_valid;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            hid       <= '{default: '0};
            hid_valid <= 1'b0;
        end else begin
            hid_valid <= fc1_done;
            if (fc1_done)
                for (int k = 0; k < N_HID; k++)
                    hid[k] <= acc[k][W1-1] ? '0 : acc[k][W1-2:0];
        end
    end

    // ------------------------------------------------------------------
    // Stage 3: FC2 products
    // ------------------------------------------------------------------
    logic signed [W2-1:0] prod [N_HID];
    logic                 prod_valid;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            prod       <= '{default: '0};
            prod_valid <= 1'b0;
        end else begin
            prod_valid <= hid_valid;
            if (hid_valid)
                for (int k = 0; k < N_HID; k++)
                    prod[k] <= W2'($signed(w2[k]) * $signed({1'b0, hid[k]}));
        end
    end

    // ------------------------------------------------------------------
    // Stage 4: FC2 sum + bias
    // ------------------------------------------------------------------
    logic signed [W2-1:0] fc2;
    logic                 fc2_valid;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fc2       <= '0;
            fc2_valid <= 1'b0;
        end else begin
            fc2_valid <= prod_valid;
            if (prod_valid)
                fc2 <= prod[0] + prod[1] + prod[2] + W2'(FC2_BIAS);
        end
    end

    // ------------------------------------------------------------------
    // Stage 5: sigmoid as a sign check -> class
    // ------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fc_output    <= 1'b0;
            valid_output <= 1'b0;
        end else begin
            valid_output <= fc2_valid;
            if (fc2_valid)
                fc_output <= (fc2 > 0);
        end
    end

endmodule
