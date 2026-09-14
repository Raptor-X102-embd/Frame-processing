`include "img_pkg.svh"

module pixel_stream #(
    parameter H_ACTIVE_PIX        = 640,
    parameter H_FRONT_PORCH_PIX   = 16,
    parameter H_SYNC_PIX          = 96,
    parameter H_BACK_PORCH_PIX    = 48,

    parameter V_ACTIVE_PIX        = 480,
    parameter V_FRONT_PORCH_LINES = 10,
    parameter V_SYNC_LINES        = 2,
    parameter V_BACK_PORCH_LINES  = 33
)(
    input                clk,
    input                rst_n,

    input  logic         frame_start,
    input  pixel_t       pixel_i,

    output pixel_t       pixel_o,
    output logic         valid_o,
    output logic         frame_end
);

    localparam H_ACTIVE_CNT      = H_ACTIVE_PIX;
    localparam H_FRONT_PORCH_CNT = H_ACTIVE_PIX + H_FRONT_PORCH_PIX;
    localparam H_SYNC_CNT        = H_FRONT_PORCH_CNT + H_SYNC_PIX;
    localparam H_BACK_PORCH_CNT  = H_SYNC_CNT + H_BACK_PORCH_PIX;

    localparam V_ACTIVE_CNT      = V_ACTIVE_PIX;
    localparam V_FRONT_PORCH_CNT = V_ACTIVE_PIX + V_FRONT_PORCH_LINES;
    localparam V_SYNC_CNT        = V_FRONT_PORCH_CNT + V_SYNC_LINES;
    localparam V_BACK_PORCH_CNT  = V_SYNC_CNT + V_BACK_PORCH_LINES;
    

    logic [$clog2(H_ACTIVE_PIX):0] h_cnt;
    logic [$clog2(V_ACTIVE_PIX):0] v_cnt;
    
    logic valid_i;
    logic processing;
    logic last_pix_in_row; 
    pixel_t pixel_proc;

    // line buffer
    pixel_t lb [0:H_ACTIVE_PIX-1]; // idx:  0  1  2  3        H_ACTIVE  H_ACTIVE+1
    //pixel_t lb [0:H_ACTIVE+1]; // idx:  0  1  2  3        H_ACTIVE  H_ACTIVE+1
    //                         // elem: p0 p0 p1 p2 ... pH_ACTIVE-1 pH_ACTIVE-1

    proc_img #(
        .FRAME_W (H_ACTIVE_PIX+2),
        .FRAME_H (V_ACTIVE_PIX+2),
        .WINDOW_W(3),
        .WINDOW_H(3)
    ) u_proc_img (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_i(pixel_proc),
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
        H_STREAMING, 
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
    h_state_t h_state;
    v_state_t v_state;

    // _ _ _ _ _ _ 
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ 0 0 0 0 _
    // _ _ _ _ _ _
    
    assign last_pix_in_row = (h_cnt == H_BACK_PORCH_CNT - 1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hp_state <= HP_IDLE;
            lb_head <= '0;
            valid_i <= 1'b0;
        end else begin
           // valid_i <= (vp_state != VP_IDLE && vp_state != WRITE_ROW_LAST && // inner pixels without replicants
           //             hp_state != HP_IDLE && h_cnt != H_ACTIVE_PIX-1);

            valid_i <= (h_cnt >= 2 && v_cnt >= 2);

            case (hp_state) 
                HP_IDLE: begin 
                    lb_head <= '0;
                    if (frame_start || processing) begin 
                        if (vp_state != REPLAY_ROW_LAST)
                            lb[lb_head] <= pixel_i;

                        lb_head     <= lb_head + 1; // works only if 1 cycle after HP_IDLE, of rst_n
                        hp_state    <= H_STREAMING; 
                        if (vp_state == VP_IDLE) begin
                            pixel_proc  <= pixel_i;
                        end else begin
                            pixel_proc  <= lb[lb_head];
                        end
                    end
                end

               // CAPTURE_PIXEL_0: begin
               //     lb[lb_head] <= pixel_i;
               //     pixel_proc  <= pixel_i;
               //     lb_head     <= lb_head + 1;
               //     //h_cnt       <= h_cnt + ;
               //     hp_state    <= H_STREAMING;
               // end
                H_STREAMING: begin
                    lb[lb_head] <= pixel_i;
                    pixel_proc  <= lb[lb_head-1];
                    lb_head     <= lb_head + 1;

                    if (h_cnt == H_ACTIVE_PIX-1)
                        hp_state <= REPLAY_PIXEL_LAST;
                end

                REPLAY_PIXEL_LAST: begin
                    pixel_proc  <= lb[lb_head];
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
                    if (v_cnt == '0 && last_pix_in_row)
                        vp_state <= V_STREAMING;
                end
               
                V_STREAMING: begin
                    if (v_cnt == V_ACTIVE_PIX-1 && last_pix_in_row)
                        vp_state <= WRITE_ROW_LAST;
                end

                WRITE_ROW_LAST: begin
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_state <= H_IDLE;
        end else begin
            h_cnt <= (frame_start || processing) ? h_cnt + 1 : '0; // works only if 1 cycle after HP_IDLE, of rst_n

            case (h_state) 
                H_IDLE: begin 
                    h_cnt <= '0;
                    if (frame_start || processing) begin 
                        h_state <= H_ACTIVE;
                    end
                end

                H_ACTIVE: begin 
                    if (h_cnt == H_ACTIVE_CNT - 1) begin 
                        h_state <= H_FRONT_PORCH;
                    end
                end
                
                H_FRONT_PORCH: begin 
                    if (h_cnt == H_FRONT_PORCH_CNT - 1) begin 
                        h_state <= H_SYNC;
                    end
                end

                H_SYNC: begin 
                    if (h_cnt == H_SYNC_CNT - 1) begin 
                        h_state <= H_BACK_PORCH;
                    end
                end

                H_BACK_PORCH: begin 
                    if (last_pix_in_row) begin 
                        h_state <= H_IDLE;
                        h_cnt <= '0;
                    end
                end
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_state <= V_IDLE;
            processing <= 1'b0;
            frame_end  <= 1'b0;
        end else begin
            frame_end  <= 1'b0;

            if (processing && last_pix_in_row) 
                v_cnt <= v_cnt + 1;

            if (frame_start)
                processing <= 1'b1;

            case (v_state) 
                V_IDLE: begin 
                    v_cnt <= '0;
                    if (processing && last_pix_in_row) begin 
                        v_state <= V_ACTIVE;
                        processing <= 1'b1;
                    end
                end

                V_ACTIVE: begin 
                    if (v_cnt == V_ACTIVE_CNT - 1 && last_pix_in_row) begin 
                        v_state <= V_FRONT_PORCH;
                    end
                end
                
                V_FRONT_PORCH: begin 
                    if (v_cnt == V_FRONT_PORCH_CNT - 1 && last_pix_in_row) begin 
                        v_state <= V_SYNC;
                    end
                end

                V_SYNC: begin 
                    if (v_cnt == V_SYNC_CNT - 1 && last_pix_in_row) begin 
                        v_state <= V_BACK_PORCH;
                    end
                end

                V_BACK_PORCH: begin 
                    if (v_cnt == V_BACK_PORCH_CNT - 1 && last_pix_in_row) begin 
                        v_state <= V_IDLE;
                        processing <= 1'b0;
                        frame_end  <= 1'b1;
                        v_cnt <= '0;
                    end
                end
            endcase
        end
    end
endmodule
