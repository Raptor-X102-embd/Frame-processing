`include "img_pkg.svh"
import img_pkg::*;

module inverse_filter #(
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

    localparam PROC_PIX_X = WINDOW_W / 2;
    localparam PROC_PIX_Y = WINDOW_H / 2;

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
