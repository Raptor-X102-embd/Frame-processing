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

    parameter WINDOW_W = 3,
    parameter WINDOW_H = 3
)(
    input                clk,
    input                rst_n,

    input  pixel_t       pixel_i,
    input  logic         h_sync_i,
    input  logic         v_sync_i,

    output pixel_t       pixel_o,
    output logic         valid_o
);

   // localparam H_ACTIVE_CNT      = H_ACTIVE_PIX;
   // localparam H_FRONT_PORCH_CNT = H_ACTIVE_PIX + H_FRONT_PORCH_PIX;
   // localparam H_SYNC_CNT        = H_FRONT_PORCH_CNT + H_SYNC_PIX;
   // localparam H_BACK_PORCH_CNT  = H_SYNC_CNT + H_BACK_PORCH_PIX;

   // localparam V_ACTIVE_CNT      = V_ACTIVE_LINES;
   // localparam V_FRONT_PORCH_CNT = V_ACTIVE_LINES + V_FRONT_PORCH_LINES;
   // localparam V_SYNC_CNT        = V_FRONT_PORCH_CNT + V_SYNC_LINES;
   // localparam V_BACK_PORCH_CNT  = V_SYNC_CNT + V_BACK_PORCH_LINES;
    
    localparam H_BACK_PORCH_CNT  = H_BACK_PORCH_PIX;
    localparam H_ACTIVE_CNT      = H_BACK_PORCH_CNT + H_ACTIVE_PIX;
    localparam H_FRONT_PORCH_CNT = H_ACTIVE_CNT + H_FRONT_PORCH_PIX;
    localparam H_SYNC_CNT        = H_FRONT_PORCH_CNT + H_SYNC_PIX;

    localparam V_BACK_PORCH_CNT  = V_BACK_PORCH_LINES;
    localparam V_ACTIVE_CNT      = V_BACK_PORCH_CNT + V_ACTIVE_LINES;
    localparam V_FRONT_PORCH_CNT = V_ACTIVE_CNT + V_FRONT_PORCH_LINES;
    localparam V_SYNC_CNT        = V_FRONT_PORCH_CNT + V_SYNC_LINES;

    logic [$clog2(H_ACTIVE_PIX):0] h_cnt;
    logic [$clog2(V_ACTIVE_LINES):0] v_cnt;
    
    logic do_proc_pixel;
    logic valid_i;
    logic last_pix_in_row; 
    pixel_t pixel_proc;
    pixel_t pixel_del;
    pixel_t pixel_last;
    logic [$clog2(H_ACTIVE_PIX)-1:0] lb_head;

    // line buffer
    pixel_t lb [0:H_ACTIVE_PIX-1];

    proc_img #(
        .FRAME_W (H_ACTIVE_PIX+2),
        .FRAME_H (V_ACTIVE_LINES+2),
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

    typedef enum logic [2:0] {
        VP_IDLE, 
        //CAPTURE_ROW_0, 
        //REPLAY_ROW_0, 
        V_STREAMING, 
        WRITE_ROW_LAST, 
        REPLAY_ROW_LAST 
    } v_paddind_state_t;

    typedef enum logic [2:0] {
        HP_IDLE, 
        CAPTURE_PIXEL_0, 
        //REPLAY_PIXEL_0, 
        HP_REPLAY_FIRST,
        HP_STREAMING, 
        //CAPTURE_PIXEL_LAST, 
        REPLAY_PIXEL_LAST 
    } h_paddind_state_t;

    typedef enum logic [2:0] {
        H_IDLE, 
        H_ACTIVE, 
        H_FRONT_PORCH, 
        H_SYNC, 
        H_BACK_PORCH 
    } h_state_t;

    typedef enum logic [2:0] {
        V_IDLE, 
        V_ACTIVE, 
        V_FRONT_PORCH, 
        V_SYNC, 
        V_BACK_PORCH 
    } v_state_t;

    h_paddind_state_t hp_state;
    v_paddind_state_t vp_state;
   // h_state_t h_state;
   // v_state_t v_state;

    // _ _ _ _ _ _ 
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ _ _ _ _ _
    
    assign last_pix_in_row = (h_cnt == H_FRONT_PORCH_CNT - 1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hp_state      <= HP_IDLE;
            lb_head       <= '0;
            do_proc_pixel <= 1'b0;
            valid_i       <= 1'b0; 
        end else begin
            do_proc_pixel <= (h_cnt >= H_BACK_PORCH_CNT + WINDOW_W - 1 && // pixel [2] of row
                              h_cnt < H_ACTIVE_CNT + WINDOW_W - 1     && // replicated last pixel
                              v_cnt >= V_BACK_PORCH_CNT + WINDOW_H - 1 && // row [2]
                              v_cnt < V_ACTIVE_CNT + WINDOW_H - 1);      // replicated last row

            valid_i <= (h_cnt >= H_BACK_PORCH_CNT && // replicated pixel [0] of row
                        h_cnt < H_ACTIVE_CNT + WINDOW_W - 1     && // replicated last pixel
                        v_cnt >= V_BACK_PORCH_CNT && // replicated row [0]
                        v_cnt < V_ACTIVE_CNT + WINDOW_H - 1);      // replicated last row

            case (hp_state) 
                HP_IDLE: begin 
                    lb_head <= '0;
                    if (h_active_start && v_active) begin 
                        pixel_del <= pixel_i;
                      //  if (vp_state != WRITE_ROW_LAST)
                       //     lb[lb_head] <= pixel_i;

                      //  lb_head     <= lb_head + 1; // works only if 1 cycle after HP_IDLE, of rst_n
                        hp_state    <= HP_REPLAY_FIRST; 
                        if (vp_state == VP_IDLE) begin
                            pixel_proc  <= pixel_i;
                        end else begin
                            pixel_proc  <= lb[lb_head];
                        end
                    end
                end

                HP_REPLAY_FIRST: begin
                    if (vp_state != WRITE_ROW_LAST) begin
                        lb[lb_head] <= pixel_del;
                    end

                    pixel_del   <= pixel_i;
                    lb_head     <= lb_head + 1;
                    if (vp_state == VP_IDLE) begin
                        pixel_proc  <= pixel_del;
                    end else begin
                        pixel_proc  <= lb[lb_head];
                    end 
                    
                    hp_state    <= HP_STREAMING; 
                end

                HP_STREAMING: begin
                    if (vp_state != WRITE_ROW_LAST)
                        lb[lb_head] <= pixel_del;

                    pixel_del   <= pixel_i;
                    if (vp_state == VP_IDLE) begin
                        pixel_proc  <= pixel_del;
                    end else begin
                        pixel_proc  <= lb[lb_head];
                    end  
                    lb_head     <= lb_head + 1;

                    if (h_cnt == H_ACTIVE_CNT) begin
                        pixel_last <= lb[lb_head];
                        pixel_del  <= pixel_del;
                        hp_state   <= REPLAY_PIXEL_LAST;
                        lb_head    <= lb_head;
                    end
                end

                REPLAY_PIXEL_LAST: begin
                    if (vp_state == VP_IDLE) begin
                        pixel_proc  <= pixel_del;
                    end else begin
                        pixel_proc  <= pixel_last;
                    end 
                    hp_state    <= HP_IDLE;
                    lb_head <= '0;
                end
            endcase
        end
    end
 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vp_state <= VP_IDLE;
        end else begin
            case (vp_state) 
                VP_IDLE: begin 
                    if (v_cnt == V_BACK_PORCH_CNT && last_pix_in_row) // [0] active row
                        vp_state <= V_STREAMING;
                end
               
                V_STREAMING: begin
                    if (v_cnt == V_ACTIVE_CNT-1 && last_pix_in_row)
                        vp_state <= WRITE_ROW_LAST;
                end

                WRITE_ROW_LAST: begin // writing last row without saving invalid delay pixels
                    if (last_pix_in_row)
                        vp_state <= REPLAY_ROW_LAST;
                end

                REPLAY_ROW_LAST: begin
                    if (last_pix_in_row)
                        vp_state <= VP_IDLE;
                end

            endcase
        end
    end

    logic h_active_start, v_active;
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

    assign h_active_start = h_cnt == H_BACK_PORCH_CNT;
    assign v_active = (v_cnt >= V_BACK_PORCH_CNT) && (v_cnt <= V_ACTIVE_CNT + 1);

endmodule
