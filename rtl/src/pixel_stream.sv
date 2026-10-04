`include "img_pkg.svh"

import img_pkg::*;

module pixel_stream #(
    parameter H_ACTIVE_PIX        = 640,
    parameter H_FRONT_PORCH_PIX   = 16,
    parameter H_SYNC_PIX          = 96,
    parameter H_BACK_PORCH_PIX    = 48,

    parameter V_ACTIVE_LINES        = 480,
    parameter V_FRONT_PORCH_LINES = 10,
    parameter V_SYNC_LINES        = 2,
    parameter V_BACK_PORCH_LINES  = 33,

    // MUST be odd numbers to find cetral pixel in a window
    // TODO: odd check
    parameter WINDOW_W = 5,
    parameter WINDOW_H = 5
)(
    input                clk,
    input                rst_n,

    input  pixel_t       pixel_i,
    input  logic         h_sync_i,
    input  logic         v_sync_i,

    output pixel_t       pixel_o,
    output logic         valid_o
);

    localparam H_BACK_PORCH_CNT  = H_BACK_PORCH_PIX;
    localparam H_ACTIVE_CNT      = H_BACK_PORCH_CNT + H_ACTIVE_PIX;
    localparam H_FRONT_PORCH_CNT = H_ACTIVE_CNT + H_FRONT_PORCH_PIX;
    localparam H_SYNC_CNT        = H_FRONT_PORCH_CNT + H_SYNC_PIX;

    localparam V_BACK_PORCH_CNT  = V_BACK_PORCH_LINES;
    localparam V_ACTIVE_CNT      = V_BACK_PORCH_CNT + V_ACTIVE_LINES;
    localparam V_FRONT_PORCH_CNT = V_ACTIVE_CNT + V_FRONT_PORCH_LINES;
    localparam V_SYNC_CNT        = V_FRONT_PORCH_CNT + V_SYNC_LINES;

    localparam H_DEL_WIDTH       = WINDOW_W/2;
    localparam V_DEL_WIDTH       = WINDOW_H/2;

    logic [$clog2(H_ACTIVE_PIX):0] h_cnt;
    logic [$clog2(V_ACTIVE_LINES):0] v_cnt;
    
    logic last_pix_in_row; 
    logic do_proc_pixel;
    logic valid_i;
    pixel_t pixel_proc;

    //localparam LB_LINE_WIDTH = (V_DEL_WIDTH == 1) ? 2 : $clog2(V_DEL_WIDTH+1);
    localparam LB_LINE_WIDTH = (V_DEL_WIDTH >= 1) ? $clog2(V_DEL_WIDTH+1) : 1;
    logic [LB_LINE_WIDTH-1:0] lb_line_rd, lb_line_wr;
    logic [$clog2(H_ACTIVE_PIX)-1:0] lb_head_rd, lb_head_wr;

    // line buffer
    pixel_t lb [0:V_DEL_WIDTH][0:H_ACTIVE_PIX-1];

    generate
        if (WINDOW_W < 1)
            $error("pixel_stream: WINDOW_W must be >= 1 (got %0d)", WINDOW_W);

        if (WINDOW_H < 1)
            $error("pixel_stream: WINDOW_H must be >= 1 (got %0d)", WINDOW_H);

        if (WINDOW_W % 2 == 0)
            $error("pixel_stream: WINDOW_W must be odd (got %0d)", WINDOW_W);

        if (WINDOW_H % 2 == 0)
            $error("pixel_stream: WINDOW_H must be odd (got %0d)", WINDOW_H);

        if (WINDOW_W > H_ACTIVE_PIX)
            $error("pixel_stream: WINDOW_W (%0d) must be <= H_ACTIVE_PIX (%0d)",
                   WINDOW_W, H_ACTIVE_PIX);

        if (WINDOW_H > V_ACTIVE_LINES)
            $error("pixel_stream: WINDOW_H (%0d) must be <= V_ACTIVE_LINES (%0d)",
                   WINDOW_H, V_ACTIVE_LINES);

        if (H_ACTIVE_PIX < 2)
            $error("pixel_stream: H_ACTIVE_PIX must be >= 2 (got %0d)", H_ACTIVE_PIX);

        if (V_ACTIVE_LINES < 2)
            $error("pixel_stream: V_ACTIVE_LINES must be >= 2 (got %0d)", V_ACTIVE_LINES);

        localparam int PIPELINE_DELAY_H = 6;
        if (WINDOW_W + PIPELINE_DELAY_H > H_FRONT_PORCH_PIX + 1)
            $error("pixel_stream: WINDOW_W (%0d) + PIPELINE_DELAY_H (%0d) > H_FRONT_PORCH_PIX (%0d) + 1. \
                    Increase H_FRONT_PORCH_PIX or H_SYNC_PIX.",
                   WINDOW_W, PIPELINE_DELAY_H, H_FRONT_PORCH_PIX);

        localparam int PIPELINE_DELAY_V = 6;
        if ((WINDOW_H/2) + PIPELINE_DELAY_V > V_FRONT_PORCH_LINES + 1)
            $error("pixel_stream: V_DEL_WIDTH (%0d) + PIPELINE_DELAY_V (%0d) > V_FRONT_PORCH_LINES (%0d) + 1.",
                   WINDOW_H/2, PIPELINE_DELAY_V, V_FRONT_PORCH_LINES);


        if (H_FRONT_PORCH_PIX < 1)
            $error("pixel_stream: H_FRONT_PORCH_PIX must be >= 1");

        if (V_FRONT_PORCH_LINES < 1)
            $error("pixel_stream: V_FRONT_PORCH_LINES must be >= 1");

        if (H_ACTIVE_PIX < 2)
            $error("pixel_stream: H_ACTIVE_PIX must be >= 2 for lb_head_rd/wr");
    endgenerate

    proc_img #(
        .FRAME_W (H_ACTIVE_PIX + WINDOW_W - 1),
        .FRAME_H (V_ACTIVE_LINES + WINDOW_H - 1),
        .WINDOW_W(WINDOW_W),
        .WINDOW_H(WINDOW_H)
    ) u_proc_img (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_i(pixel_proc),
        .do_proc_pixel(do_proc_pixel),
        .valid_i(valid_i),
        .pixel_o(pixel_o),
        .valid_o(valid_o)
    );

    // _ _ _ _ _ _ 
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ _ _ _ _ _
    

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_proc <= pixel_t'{'0, '0, '0};
            valid_i <= 1'b0;
            do_proc_pixel <= 1'b0; 
        end else begin
            if (active) begin
                lb[lb_line_wr][lb_head_wr] <= pixel_i;
            end

            do_proc_pixel <= (h_cnt >= H_BACK_PORCH_CNT + WINDOW_W &&
                              h_cnt <  H_ACTIVE_CNT + WINDOW_W     &&
                              v_cnt >= V_BACK_PORCH_CNT + WINDOW_H - 1 &&
                              v_cnt <  V_ACTIVE_CNT + WINDOW_H - 1);

            valid_i <= 1'b0;
            if (h_cnt >= H_BACK_PORCH_CNT + 1 &&
                h_cnt < H_ACTIVE_CNT + WINDOW_W      &&
                v_cnt >= V_BACK_PORCH_CNT &&
                v_cnt < V_ACTIVE_CNT + WINDOW_H - 1
            ) begin    
                pixel_proc  <= lb[lb_line_rd][lb_head_rd];
                valid_i <= 1'b1;
            end
        end
    end

    assign last_pix_in_row = (h_cnt == H_SYNC_CNT - 1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lb_line_wr <= '0;
        end else begin
            if (v_cnt == V_BACK_PORCH_CNT-1 && last_pix_in_row) begin
                lb_line_wr <= '0;
            end else if (v_active && last_pix_in_row) begin
                lb_line_wr <= (lb_line_wr == V_DEL_WIDTH) ? '0 : lb_line_wr + 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lb_line_rd <= 0;
        end else begin
            if (v_cnt == V_BACK_PORCH_CNT-1 && last_pix_in_row) begin
                lb_line_rd <= 0;
            end else if (
                v_cnt >= V_BACK_PORCH_CNT + V_DEL_WIDTH && 
                v_cnt <  V_ACTIVE_CNT + V_DEL_WIDTH     && 
                last_pix_in_row
            ) begin
                lb_line_rd <= (lb_line_rd == V_DEL_WIDTH) ? 0 : lb_line_rd + 1;
            end
        end
    end 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lb_head_wr <= 0;
        end else begin
            if (h_cnt == H_BACK_PORCH_CNT-1) begin
                lb_head_wr <= 0;
            end else if (h_active) begin
                lb_head_wr <= lb_head_wr + 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lb_head_rd <= 0;
        end else begin
            if (h_cnt == H_BACK_PORCH_CNT-1) begin
                lb_head_rd <= 0;
            end else if (
                h_cnt >= H_BACK_PORCH_CNT + H_DEL_WIDTH + 1 &&  // 1 cycle delayed to wait write 0 pixel
                h_cnt <  H_ACTIVE_CNT + H_DEL_WIDTH // -1 to stay on the last head (639)
            ) begin
                lb_head_rd <= lb_head_rd + 1;
            end
        end
    end

    logic v_active, h_active, active;
    logic h_sync_end, v_sync_end;
    logic h_sync_r, v_sync_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            h_sync_r <= 1'b0;
            v_sync_r <= 1'b0;
        end else begin 
            h_sync_r <= h_sync_i;
            v_sync_r <= v_sync_i;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= '0;
            v_cnt <= '0;
        end else if (v_sync_end) begin
            h_cnt <= 1;
            v_cnt <= '0;
        end else if (h_sync_end) begin
            h_cnt <= 1;
            v_cnt <= (v_cnt == V_SYNC_CNT-1) ? '0 : v_cnt + 1'b1;
        end else begin
            h_cnt <= (h_cnt == H_SYNC_CNT-1) ? '0 : h_cnt + 1'b1;
        end
    end

    assign h_sync_end = ~h_sync_r & h_sync_i;
    assign v_sync_end = ~v_sync_r & v_sync_i;

    assign v_active = (v_cnt >= V_BACK_PORCH_CNT) && (v_cnt < V_ACTIVE_CNT);
    assign h_active = (h_cnt >= H_BACK_PORCH_CNT) && (h_cnt < H_ACTIVE_CNT);
    assign active = v_active && h_active;

endmodule
