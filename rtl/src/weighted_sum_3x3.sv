`include "img_pkg.svh"
import img_pkg::*;
module weighted_sum_3x3 #(
    parameter WINDOW_W = 3,
    parameter WINDOW_H = 3,
    parameter Q_WIDTH  = 16,
    parameter FRAC_PART= 15,
    parameter logic [WINDOW_H*WINDOW_W-1:0][31:0] COEFF_N = '{default: 32'd1},
    parameter logic [WINDOW_H*WINDOW_W-1:0][31:0] COEFF_D = '{default: 32'd9}
)(
    input                clk,
    input                rst_n,
    input  logic         do_proc_pixel,
    input  pixel_t       wsr [0:WINDOW_H-1][0:WINDOW_W-1],
    output pixel_t       pixel_o,
    output logic         valid_o
);
    
    generate
        if (WINDOW_W < 1)
            $error("weighted_sum_3x3: WINDOW_W must be >= 1 (got %0d)", WINDOW_W);

        if (WINDOW_H < 1)
            $error("weighted_sum_3x3: WINDOW_H must be >= 1 (got %0d)", WINDOW_H);

        if (Q_WIDTH < 2)
            $error("weighted_sum_3x3: Q_WIDTH must be >= 2 (got %0d)", Q_WIDTH);

        if (FRAC_PART < 1)
            $error("weighted_sum_3x3: FRAC_PART must be >= 1 (got %0d)", FRAC_PART);

        if (FRAC_PART > Q_WIDTH - 1)
            $error("weighted_sum_3x3: FRAC_PART (%0d) must be <= Q_WIDTH-1 (%0d)",
                   FRAC_PART, Q_WIDTH-1);

        if (FRAC_PART < 8 + $clog2(WINDOW_H*WINDOW_W))
            $error("weighted_sum_3x3: FRAC_PART (%0d) < 8 + clog2(N_ELEMS) (%0d)",
                   FRAC_PART, 8 + $clog2(WINDOW_H*WINDOW_W));

        if (Q_WIDTH < 2)
        $error("weighted_sum_3x3: Q_WIDTH must be >= 2 (got %0d)", Q_WIDTH);

        if (FRAC_PART < 1)
            $error("weighted_sum_3x3: FRAC_PART must be >= 1 (got %0d)", FRAC_PART);

        if (FRAC_PART > Q_WIDTH - 1)
            $error("weighted_sum_3x3: FRAC_PART (%0d) must be <= Q_WIDTH-1 (%0d)",
                   FRAC_PART, Q_WIDTH-1);

        if (Q_WIDTH - FRAC_PART - 1 < 0) begin : g_int_bits_negative
            $error("weighted_sum_3x3: int_bits = Q_WIDTH - FRAC_PART - 1 = %0d is negative",
                   Q_WIDTH - FRAC_PART - 1);
        end else if (Q_WIDTH - FRAC_PART - 1 >= 31) begin : g_int_bits_huge
        end else begin : g_check_int_bits
            localparam int INT_BITS = Q_WIDTH - FRAC_PART - 1;
            for (genvar k = 0; k < WINDOW_H*WINDOW_W; ++k) begin : g_coeff_k
                localparam int N_k = $signed(COEFF_N[k]);
                localparam int D_k = $signed(COEFF_D[k]);
                localparam int N_abs = (N_k < 0) ? -N_k : N_k;
                localparam int D_abs = (D_k < 0) ? -D_k : D_k;

                if (D_k == 0)
                    $error("weighted_sum_3x3: COEFF_D[%0d] must not be zero", k);

                // N_abs < D_abs << INT_BITS
                if (N_abs >= (D_abs << INT_BITS))
                    $error("weighted_sum_3x3: COEFF_N[%0d]/COEFF_D[%0d] = %0d/%0d \
                            does not fit into int_bits=%0d. Increase Q_WIDTH or decrease FRAC_PART.",
                           k, k, N_k, D_k, INT_BITS);
            end
        end

        if ($bits(COEFF_N) != 32 * WINDOW_H * WINDOW_W)
            $error("weighted_sum_3x3: COEFF_N length must be WINDOW_H*WINDOW_W (%0d)",
                   WINDOW_H*WINDOW_W);

        if ($bits(COEFF_D) != 32 * WINDOW_H * WINDOW_W)
            $error("weighted_sum_3x3: COEFF_D length must be WINDOW_H*WINDOW_W (%0d)",
                   WINDOW_H*WINDOW_W);
    endgenerate

    logic [7:0] wsr_r [0:WINDOW_H-1][0:WINDOW_W-1];
    logic [7:0] wsr_g [0:WINDOW_H-1][0:WINDOW_W-1];
    logic [7:0] wsr_b [0:WINDOW_H-1][0:WINDOW_W-1];
    logic [7:0] pixel_o_r, pixel_o_g, pixel_o_b;
    logic       valid_o_r, valid_o_g, valid_o_b;

    always_comb begin
        for (int i = 0; i < WINDOW_H; ++i) begin
            for (int j = 0; j < WINDOW_W; ++j) begin
                wsr_r[i][j] = wsr[i][j].R;
            end
        end 

        for (int i = 0; i < WINDOW_H; ++i) begin
            for (int j = 0; j < WINDOW_W; ++j) begin
                wsr_g[i][j] = wsr[i][j].G;
            end
        end

        for (int i = 0; i < WINDOW_H; ++i) begin
            for (int j = 0; j < WINDOW_W; ++j) begin
                wsr_b[i][j] = wsr[i][j].B;
            end
        end
    end

    assign pixel_o = pixel_t'{pixel_o_r, pixel_o_g, pixel_o_b};
    assign valid_o = valid_o_r & valid_o_g & valid_o_b;

    weighted_sum_3x3_1ch #(
        .WINDOW_W (WINDOW_W),
        .WINDOW_H (WINDOW_H),
        .Q_WIDTH  (Q_WIDTH),
        .FRAC_PART(FRAC_PART),
        .COEFF_N  (COEFF_N),
        .COEFF_D  (COEFF_D)
    ) u_ws_r (
        .clk(clk), .rst_n(rst_n),
        .do_proc_pixel(do_proc_pixel),
        .wsr_1ch(wsr_r),
        .pixel_o_1ch(pixel_o_r),
        .valid_o_1ch(valid_o_r)
    );
    
    weighted_sum_3x3_1ch #(
        .WINDOW_W(WINDOW_W),
        .WINDOW_H(WINDOW_H),
        .Q_WIDTH(Q_WIDTH),
        .FRAC_PART(FRAC_PART),
        .COEFF_N  (COEFF_N),
        .COEFF_D  (COEFF_D)
    ) u_ws_g (
        .clk(clk),
        .rst_n(rst_n),
        .do_proc_pixel(do_proc_pixel),
        .wsr_1ch(wsr_g),
        .pixel_o_1ch(pixel_o_g),
        .valid_o_1ch(valid_o_g)
    );

    weighted_sum_3x3_1ch #(
        .WINDOW_W(WINDOW_W),
        .WINDOW_H(WINDOW_H),
        .Q_WIDTH(Q_WIDTH),
        .FRAC_PART(FRAC_PART),
        .COEFF_N  (COEFF_N),
        .COEFF_D  (COEFF_D)
    ) u_ws_b (
        .clk(clk),
        .rst_n(rst_n),
        .do_proc_pixel(do_proc_pixel),
        .wsr_1ch(wsr_b),
        .pixel_o_1ch(pixel_o_b),
        .valid_o_1ch(valid_o_b)
    );

endmodule

module weighted_sum_3x3_1ch #(
    parameter WINDOW_W = 3,
    parameter WINDOW_H = 3,
    parameter Q_WIDTH = 16,
    parameter FRAC_PART = 15,
    parameter logic [WINDOW_H*WINDOW_W-1:0][31:0] COEFF_N = '{default: 32'd1},
    parameter logic [WINDOW_H*WINDOW_W-1:0][31:0] COEFF_D = '{default: 32'd9}
)( 
    input                clk,
    input                rst_n,
    input  logic         do_proc_pixel,

    input  logic [7:0]   wsr_1ch [0:WINDOW_H-1][0:WINDOW_W-1],
    output logic [7:0]   pixel_o_1ch,
    output logic         valid_o_1ch 
);

    localparam PROD_WIDTH = Q_WIDTH + 8;
    localparam SHIFT      = FRAC_PART;
    localparam SUM_WIDTH  = PROD_WIDTH + $clog2(WINDOW_H * WINDOW_W);

    typedef logic [7:0]                                       wsr_t          [0:WINDOW_H-1][0:WINDOW_W-1];
    typedef logic [WINDOW_H*WINDOW_W-1:0][31:0]               coeffs_2d_t;
    typedef logic signed [WINDOW_H*WINDOW_W-1:0][Q_WIDTH-1:0] q_coeffs_2d_t;
    typedef logic signed [PROD_WIDTH-1:0]                     pix_prod_2d_t  [0:WINDOW_H-1][0:WINDOW_W-1];

    generate
        for (genvar k = 0; k < WINDOW_H*WINDOW_W; ++k) begin : g_check_div
            if (COEFF_D[k] == 0)
                $error("weighted_sum_3x3_1ch: COEFF_D[%0d] must not be zero", k);
        end
    endgenerate

    function automatic q_coeffs_2d_t init_coeffs();
        automatic q_coeffs_2d_t result;
        for (int i = 0; i < WINDOW_H; ++i) begin
            for (int j = 0; j < WINDOW_W; ++j) begin
                automatic int k    = i * WINDOW_W + j;
                automatic int n    = COEFF_N[k];
                automatic int d    = COEFF_D[k];
                automatic int bias = (n >= 0) ? (d/2) : (-d/2);
                automatic int val  = ((1 << SHIFT) + bias) * n / d;
                result[k] = Q_WIDTH'(val);
            end
        end
        return result;
    endfunction

    localparam q_coeffs_2d_t Q_COEFFS = init_coeffs();

    logic do_proc_pixel_mul;
    logic do_proc_pixel_sum;
    logic do_proc_pixel_round;
    logic do_proc_pixel_shift;
    logic do_proc_pixel_sat;

    function automatic pix_prod_2d_t mul_coeffs_pixels_ch (
        input wsr_t wsr,
        input q_coeffs_2d_t q_coeffs
    );
        for (int i = 0; i < WINDOW_H; ++i) begin
            for (int j = 0; j < WINDOW_W; ++j) begin
                automatic int k = i * WINDOW_W + j;
                mul_coeffs_pixels_ch[i][j] = $signed({1'b0, wsr[i][j]}) * q_coeffs[k];
            end
        end
    endfunction

    function automatic logic signed [SUM_WIDTH-1:0] sum_multiplied_pixels_ch (
        input pix_prod_2d_t mul_pixels
    );
        automatic logic signed [SUM_WIDTH-1:0] temp_sum;
        temp_sum = 0;
        for (int i = 0; i < WINDOW_H; ++i) begin
            for (int j = 0; j < WINDOW_W; ++j) begin
                temp_sum += mul_pixels[i][j];
            end
        end
        sum_multiplied_pixels_ch = temp_sum;
    endfunction 

    pix_prod_2d_t multiplied_pixels;

    assign do_proc_pixel_mul = do_proc_pixel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            //multiplied_pixels <= '0; // expensive and unnecessary
            do_proc_pixel_sum <= '0;
        end else begin
            do_proc_pixel_sum <= do_proc_pixel_mul;
            if (do_proc_pixel_mul) begin
                multiplied_pixels <= mul_coeffs_pixels_ch(wsr_1ch, Q_COEFFS);
            end
        end
    end


    logic signed [SUM_WIDTH-1:0] sum;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum <= '0;
            do_proc_pixel_round <= '0;
        end else begin
            do_proc_pixel_round <= do_proc_pixel_sum;
            if (do_proc_pixel_sum) begin
                sum <= sum_multiplied_pixels_ch(multiplied_pixels);
            end
        end
    end

    

    logic signed [SUM_WIDTH:0] rounded; // prod width + 1 due to shift sum
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rounded <= '0; 
            do_proc_pixel_shift <= '0;
        end else begin
            do_proc_pixel_shift <= do_proc_pixel_round;
            if (do_proc_pixel_round) begin
                rounded <= sum + (1 <<< (SHIFT-1)); 
            end
        end
    end

    logic signed [SUM_WIDTH:0] shifted;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shifted <= '0; 
            do_proc_pixel_sat <= '0;
        end else begin
            do_proc_pixel_sat <= do_proc_pixel_shift;
            if (do_proc_pixel_shift) begin
                shifted <= rounded >>> SHIFT; 
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_o_1ch <= '0; 
            valid_o_1ch <= 1'b0;
        end else begin
            valid_o_1ch <= do_proc_pixel_sat;
            if (do_proc_pixel_sat) begin
                if (shifted > $signed({{(SUM_WIDTH+1-8){1'b0}}, 8'd255})) 
                    pixel_o_1ch <= 8'd255;
                else if (shifted < $signed({(SUM_WIDTH+1){1'b0}}))
                    pixel_o_1ch <= 8'd0;
                else 
                    pixel_o_1ch <= shifted[7:0];
            end
        end
    end

endmodule
