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

    localparam LINE_BUF_AMOUNT = WINDOW_H-1; // current line is not needed to be saved

    // line buffers
    pixel_t lb_mem [0:LINE_BUF_AMOUNT-1][0:FRAME_W-1];

    // window shift registers
    pixel_t wsr [0:WINDOW_H-1][0:WINDOW_W-1];

    // BRAM read pixels
    pixel_t pixel_lb_rd [0:LINE_BUF_AMOUNT-1];

    logic [$clog2(FRAME_W)-1:0] lb_head_rd, lb_head_wr;
    pixel_t pixel_i_rd, pixel_i_wr;
    logic   valid_i_rd, valid_i_wr;
    logic   do_proc_pixel_rd, do_proc_pixel_wr, do_proc_pixel_pr;

    assign pixel_i_rd       = pixel_i;
    assign valid_i_rd       = valid_i;
    assign do_proc_pixel_rd = do_proc_pixel;

    generate
        if (WINDOW_W > FRAME_W) begin : window_w_illegal
            $error("Elaboration Error: WINDOW_W mustn't be greater than FRAME_W. Current values: WINDOW_W=%0d, FRAME_W=%0d", WINDOW_W, FRAME_W);
        end

        if (WINDOW_H > FRAME_H) begin : window_h_illegal
            $error("Elaboration Error: WINDOW_H mustn't be greater than FRAME_H. Current values: WINDOW_H=%0d, FRAME_H=%0d", WINDOW_H, FRAME_H);
        end
    endgenerate

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
           // for (int i = 0; i < LINE_BUF_AMOUNT; ++i)
           //     for (int j = 0; j < LINE_BUF_AMOUNT; ++j)
           //         lb_mem[i][j] <= '0;

           // for (int i = 0; i < WINDOW_H; ++i)
           //     for (int j = 0; j < WINDOW_W; ++j)
           //         wsr[i][j] <= '0;

        end else begin
            if (valid_i_rd) begin
                for (int i = 0; i < LINE_BUF_AMOUNT; ++i) begin
                    pixel_lb_rd[i] <= lb_mem[i][lb_head_rd];
                end

                lb_head_wr <= lb_head_rd;
                lb_head_rd <= lb_head_rd + 1;
                if (lb_head_rd == FRAME_W-1) begin
                    lb_head_rd <= '0;
                end
            end

            if (valid_i_wr) begin
                lb_mem[0][lb_head_wr] <= pixel_i_wr;
                for (int i = 1; i < LINE_BUF_AMOUNT; ++i) begin
                    lb_mem[i][lb_head_wr] <= pixel_lb_rd[i-1];
                end

                wsr[0][0:WINDOW_W-1] <= {pixel_i_wr, wsr[0][0:WINDOW_W-2]};
                for (int i = 1; i < WINDOW_H; ++i) begin
                    wsr[i] <= {pixel_lb_rd[i-1], wsr[i][0:WINDOW_W-2]};
                end
            end
        end
    end

    inverse_filter #(
        .WINDOW_W(WINDOW_W),
        .WINDOW_H(WINDOW_H)
    ) u_filter (
        .clk(clk),
        .rst_n(rst_n),
        .do_proc_pixel(do_proc_pixel_pr),
        .wsr(wsr),
        .pixel_o(pixel_o),
        .valid_o(valid_o)
    ); 

endmodule
