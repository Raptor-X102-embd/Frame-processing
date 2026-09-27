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
    localparam PROC_PIX_X = WINDOW_W / 2;
    localparam PROC_PIX_Y = WINDOW_H / 2;

    // line buffers
    pixel_t lb [0:LINE_BUF_AMOUNT-1][0:FRAME_W-1];
    logic [$clog2(FRAME_W)-1:0] lb_head;

    // window shift registers
    pixel_t wsr [0:WINDOW_H-1][0:WINDOW_W-1];

    generate
        if (WINDOW_W > FRAME_W) begin : window_w_illegal
            $error("Elaboration Error: WINDOW_W mustn't be greater than FRAME_W. Current values: WINDOW_W=%0d, FRAME_W=%0d", WINDOW_W, FRAME_W);
        end

        if (WINDOW_H > FRAME_H) begin : window_h_illegal
            $error("Elaboration Error: WINDOW_H mustn't be greater than FRAME_H. Current values: WINDOW_H=%0d, FRAME_H=%0d", WINDOW_H, FRAME_H);
        end
    endgenerate

    assign wsr[0][0] = pixel_i;
    //assign lb[0][lb_head] = pixel_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lb_head <= '0;
           // for (int i = 0; i < LINE_BUF_AMOUNT; ++i)
           //     for (int j = 0; j < LINE_BUF_AMOUNT; ++j)
           //         lb[i][j] <= '0;

           // for (int i = 0; i < WINDOW_H; ++i)
           //     for (int j = 0; j < WINDOW_W; ++j)
           //         wsr[i][j] <= '0;

        end else if (valid_i) begin
            lb[0][lb_head] <= pixel_i;
            for (int i = 1; i < LINE_BUF_AMOUNT; ++i) begin
                lb[i][lb_head] <= lb[i-1][lb_head];
            end

            wsr[0][1:WINDOW_W-1] <= wsr[0][0:WINDOW_W-2];
            for (int i = 1; i < WINDOW_H; ++i) begin
                wsr[i] <= {lb[i-1][lb_head], wsr[i][0:WINDOW_W-2]};
            end

            lb_head <= lb_head + 1;
            if (lb_head == FRAME_W-1) begin
                lb_head <= '0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_o <= 1'b0;
        end else begin
            valid_o <= 1'b0;
            if (do_proc_pixel) begin
                pixel_o.R <= 8'hFF - wsr[PROC_PIX_Y][PROC_PIX_X].R;
                pixel_o.G <= 8'hFF - wsr[PROC_PIX_Y][PROC_PIX_X].G;
                pixel_o.B <= 8'hFF - wsr[PROC_PIX_Y][PROC_PIX_X].B;

                valid_o <= 1'b1;
            end
        end
    end
endmodule
