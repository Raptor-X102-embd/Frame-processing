`include "img_pkg.svh"
import img_pkg::*;

module box_blur3x3 #(
    parameter WINDOW_W = 3,
    parameter WINDOW_H = 3
)( 
    input                clk,
    input                rst_n,
    input  logic         do_proc_pixel,

    input  pixel_t       wsr [0:WINDOW_H-1][0:WINDOW_W-1],
    output pixel_t       pixel_o,
    output logic         valid_o 
);
    
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

    box_blur3x3_1ch #(
        .WINDOW_W(WINDOW_W),
        .WINDOW_H(WINDOW_H)
    ) u_blur_r (
        .clk(clk),
        .rst_n(rst_n),
        .do_proc_pixel(do_proc_pixel),
        .wsr_1ch(wsr_r),
        .pixel_o_1ch(pixel_o_r),
        .valid_o_1ch(valid_o_r)
    );
    
    box_blur3x3_1ch #(
        .WINDOW_W(WINDOW_W),
        .WINDOW_H(WINDOW_H)
    ) u_blur_g (
        .clk(clk),
        .rst_n(rst_n),
        .do_proc_pixel(do_proc_pixel),
        .wsr_1ch(wsr_g),
        .pixel_o_1ch(pixel_o_g),
        .valid_o_1ch(valid_o_g)
    );

    box_blur3x3_1ch #(
        .WINDOW_W(WINDOW_W),
        .WINDOW_H(WINDOW_H)
    ) u_blur_b (
        .clk(clk),
        .rst_n(rst_n),
        .do_proc_pixel(do_proc_pixel),
        .wsr_1ch(wsr_b),
        .pixel_o_1ch(pixel_o_b),
        .valid_o_1ch(valid_o_b)
    );

endmodule

module box_blur3x3_1ch #(
    parameter WINDOW_W = 3,
    parameter WINDOW_H = 3
)( 
    input                clk,
    input                rst_n,
    input  logic         do_proc_pixel,

    input  logic [7:0]   wsr_1ch [0:WINDOW_H-1][0:WINDOW_W-1],
    output logic [7:0]   pixel_o_1ch,
    output logic         valid_o_1ch 
);

    localparam Q_WIDTH = 16;
    localparam FRAC_PART = 15;
    localparam int SHIFT = FRAC_PART;
    localparam int SUM_WIDTH = 8 + $clog2(WINDOW_H * WINDOW_W);
    localparam int PROD_WIDTH = Q_WIDTH + SUM_WIDTH;
    // --- 1/9 in Q1.15 --------------------------------------------------------
    localparam logic signed [Q_WIDTH-1:0] K_ONE_NINTH = 16'(((1 << SHIFT) + 9/2) * 1 / 9);

    logic do_proc_pixel_sum; 
    logic do_proc_pixel_prod;
    logic do_proc_pixel_round;
    logic do_proc_pixel_shift;
    logic do_proc_pixel_sat;

    function automatic logic [SUM_WIDTH-1:0] sum_pixels_channel (
        input logic [7:0] wsr [0:WINDOW_H-1][0:WINDOW_W-1]
    );
        automatic logic [SUM_WIDTH-1:0] temp_sum;
        temp_sum = 0;
        for (int i = 0; i < WINDOW_H; ++i) begin
            for (int j = 0; j < WINDOW_W; ++j) begin
                temp_sum += wsr[i][j];
            end
        end
        sum_pixels_channel = temp_sum;
    endfunction 

    assign do_proc_pixel_sum = do_proc_pixel;

    logic signed [PROD_WIDTH-1:0] sum; // pre-extended for product
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum <= '0;
            do_proc_pixel_prod <= '0;
        end else begin
            do_proc_pixel_prod <= do_proc_pixel_sum;
            if (do_proc_pixel_sum) begin
                sum <= $signed({{(PROD_WIDTH-SUM_WIDTH){1'b0}}, sum_pixels_channel(wsr_1ch)});
            end
        end
    end

    logic signed [PROD_WIDTH-1:0] prod;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod <= '0;
            do_proc_pixel_round <= '0;
        end else begin
            do_proc_pixel_round <= do_proc_pixel_prod;
            if (do_proc_pixel_prod) begin
                prod <= sum * K_ONE_NINTH;
            end
        end
    end

    logic signed [PROD_WIDTH:0] rounded; // prod width + 1 due to shift sum
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rounded <= '0; 
            do_proc_pixel_shift <= '0;
        end else begin
            do_proc_pixel_shift <= do_proc_pixel_round;
            if (do_proc_pixel_round) begin
                rounded <= prod + (1 <<< (SHIFT-1)); 
            end
        end
    end

    logic signed [PROD_WIDTH:0] shifted;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shifted <= '0; 
            do_proc_pixel_sat <= '0;
        end else begin
            do_proc_pixel_sat <= do_proc_pixel_shift;
            if (do_proc_pixel_round) begin
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
                if (shifted > $signed({{(PROD_WIDTH+1-8){1'b0}}, 8'd255})) 
                    pixel_o_1ch <= 8'd255;
                else if (shifted < $signed({(PROD_WIDTH+1){1'b0}}))
                    pixel_o_1ch <= 8'd0;
                else 
                    pixel_o_1ch <= shifted[7:0];
            end
        end
    end

endmodule
