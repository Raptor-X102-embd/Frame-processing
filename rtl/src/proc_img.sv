`include "img_pkg.svh"
import img_pkg::*;

module proc_img #(
    parameter FRAME_W  = 640,
    parameter FRAME_H  = 480,
    parameter WINDOW_W = 3,
    parameter WINDOW_H = 3
)(
    input                clk,
    input                rst_n,
    input  pixel_t       pixel_i,
    input  logic         valid_i,
    input  logic         do_proc_pixel,
    output pixel_t       pixel_o,
    output logic         valid_o
);

    // window shift registers
    pixel_t wsr [0:WINDOW_H-1][0:WINDOW_W-1];
    logic do_proc_pixel_pr;

    generate
        if (WINDOW_W < 1)
            $error("proc_img: WINDOW_W must be >= 1 (got %0d)", WINDOW_W);

        if (WINDOW_H < 1)
            $error("proc_img: WINDOW_H must be >= 1 (got %0d)", WINDOW_H);

        if (WINDOW_W > FRAME_W)
            $error("proc_img: WINDOW_W (%0d) must be <= FRAME_W (%0d)", WINDOW_W, FRAME_W);

        if (WINDOW_H > FRAME_H)
            $error("proc_img: WINDOW_H (%0d) must be <= FRAME_H (%0d)", WINDOW_H, FRAME_H);

        if (FRAME_W < 2)
            $error("proc_img: FRAME_W must be >= 2 for $clog2(FRAME_W) >= 1 (got %0d)", FRAME_W);

        if (FRAME_H < 2)
            $error("proc_img: FRAME_H must be >= 2 (got %0d)", FRAME_H);

        if (FRAME_W < WINDOW_W)
            $error("proc_img: FRAME_W must be >= WINDOW_W");

        if (FRAME_H < WINDOW_H)
            $error("proc_img: FRAME_H must be >= WINDOW_H");

        if (WINDOW_W % 2 == 0)
            $warning("proc_img: WINDOW_W=%0d is even; center pixel index = WINDOW_W/2 (right of two)",
                     WINDOW_W);

        if (WINDOW_H % 2 == 0)
            $warning("proc_img: WINDOW_H=%0d is even; center pixel index = WINDOW_H/2 (right of two)",
                     WINDOW_H);
    endgenerate

    generate 
        if (WINDOW_H > 1) begin : window_height_normal_proc
            localparam LINE_BUF_AMOUNT = WINDOW_H-1; // current line is not needed to be saved

            // line buffers
            pixel_t lb_mem [0:LINE_BUF_AMOUNT-1][0:FRAME_W-1];

            // BRAM read pixels
            pixel_t pixel_lb_rd [0:LINE_BUF_AMOUNT-1];

            logic [$clog2(FRAME_W)-1:0] lb_head_rd, lb_head_wr;
            pixel_t pixel_i_rd, pixel_i_wr;
            logic   valid_i_rd, valid_i_wr;
            logic   do_proc_pixel_rd, do_proc_pixel_wr;

            assign pixel_i_rd       = pixel_i;
            assign valid_i_rd       = valid_i;
            assign do_proc_pixel_rd = do_proc_pixel;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin 
                    pixel_i_wr       <= pixel_t'{'0, '0, '0};
                    valid_i_wr       <= '0;
                    do_proc_pixel_wr <= '0;
                    do_proc_pixel_pr <= '0;
                end else begin
                    pixel_i_wr       <= pixel_i_rd;
                    valid_i_wr       <= valid_i_rd;
                    do_proc_pixel_wr <= do_proc_pixel_rd;
                    do_proc_pixel_pr <= do_proc_pixel_wr;
                end
            end

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    lb_head_rd <= '0;
                    lb_head_wr <= '0;
                end else begin
                    if (valid_i_rd) begin
                        for (int i = 0; i < LINE_BUF_AMOUNT; ++i)
                            pixel_lb_rd[i] <= lb_mem[i][lb_head_rd];

                        lb_head_wr <= lb_head_rd;
                        lb_head_rd <= (lb_head_rd == FRAME_W-1) ? '0 : lb_head_rd + 1'b1;
                    end

                    if (valid_i_wr) begin
                        lb_mem[0][lb_head_wr] <= pixel_i_wr;
                        for (int i = 1; i < LINE_BUF_AMOUNT; ++i)
                            lb_mem[i][lb_head_wr] <= pixel_lb_rd[i-1];

                        // row 0: shift by 1, insert new pixel at column 0
                        for (int j = WINDOW_W-1; j > 0; --j)
                            wsr[0][j] <= wsr[0][j-1];
                        wsr[0][0] <= pixel_i_wr;

                        // other rows: shift by 1, insert line-buffer pixel at column 0
                        for (int i = 1; i < WINDOW_H; ++i) begin
                            for (int j = WINDOW_W-1; j > 0; --j)
                                wsr[i][j] <= wsr[i][j-1];
                            wsr[i][0] <= pixel_lb_rd[i-1];
                        end
                    end
                end
            end
        end else begin : window_height_1_proc
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    do_proc_pixel_pr <= '0;
                end else begin
                    do_proc_pixel_pr <= valid_i;

                    if (valid_i) begin
                        for (int j = WINDOW_W-1; j > 0; --j)
                            wsr[0][j] <= wsr[0][j-1];
                        wsr[0][0] <= pixel_i;
                    end
                end
            end 
        end
    endgenerate

    // For colour retention D = sum(N), 
    // Q_WIDTH − FRAC_PART − 1  ≥  ceil(log2(max|N/D|))
    // FRAC_PART ≥ 8 + log2(WINDOW_H*WINDOW_W) 
    
    // 1) fills all elements with default_val
    // 2) inserts elements where override_mask[i] == 1'b1

    localparam int N_ELEMS = WINDOW_H * WINDOW_W;
    function automatic logic [N_ELEMS-1:0][31:0] make_coeffs (
        input logic [31:0]                default_val,
        input logic [N_ELEMS-1:0]         override_mask,
        input logic [N_ELEMS-1:0][31:0]   override_vals
    );
        automatic logic [N_ELEMS-1:0][31:0] result;
        for (int i = 0; i < N_ELEMS; ++i)
            result[i] = override_mask[i] ? override_vals[i] : default_val;
        return result;
    endfunction

    // COEFF_N: all zeros, except center = 1
    generate
        // COEFF_D: all 1
        localparam logic [N_ELEMS-1:0][31:0] COEFF_D = make_coeffs(
            32'd1,
            '0,
            '{default: 32'd0}
        );

        if (N_ELEMS == 1) begin : window_1x1
            localparam logic [N_ELEMS-1:0][31:0] COEFF_N = make_coeffs(
                32'd0,                          // default: all zeros
                '{1'b1},      // mask: only center
                '{default: 32'd0, (N_ELEMS/2): 32'd1}
            );

            weighted_sum_3x3 #(
                .WINDOW_W (WINDOW_W),
                .WINDOW_H (WINDOW_H),
                .Q_WIDTH  (20),
                .FRAC_PART(15),
                .COEFF_N  (COEFF_N),
                .COEFF_D  (COEFF_D)
            ) u_filter (
                .clk          (clk),
                .rst_n        (rst_n),
                .do_proc_pixel(do_proc_pixel_pr),
                .wsr          (wsr),
                .pixel_o      (pixel_o),
                .valid_o      (valid_o)
            );
        end else begin : window_normal
            localparam logic [N_ELEMS-1:0][31:0] COEFF_N = make_coeffs(
                32'd0,                          // default: all zeros
                '{(N_ELEMS/2){1'b0}, 1'b1,(N_ELEMS/2){1'b0}},      // mask: only center
                '{default: 32'd0, (N_ELEMS/2): 32'd1}
            );

            weighted_sum_3x3 #(
                .WINDOW_W (WINDOW_W),
                .WINDOW_H (WINDOW_H),
                .Q_WIDTH  (20),
                .FRAC_PART(15),
                .COEFF_N  (COEFF_N),
                .COEFF_D  (COEFF_D)
            ) u_filter (
                .clk          (clk),
                .rst_n        (rst_n),
                .do_proc_pixel(do_proc_pixel_pr),
                .wsr          (wsr),
                .pixel_o      (pixel_o),
                .valid_o      (valid_o)
            );
        end
    endgenerate

   // box_blur3x3 #(
   //     .WINDOW_W(WINDOW_W),
   //     .WINDOW_H(WINDOW_H)
   // ) u_filter (
   //     .clk(clk),
   //     .rst_n(rst_n),
   //     .do_proc_pixel(do_proc_pixel_pr),
   //     .wsr(wsr),
   //     .pixel_o(pixel_o),
   //     .valid_o(valid_o)
   // );
endmodule
