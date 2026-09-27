`timescale 1ns/1ps
`include "img_pkg.svh"

module tb_top();

    localparam H_ACTIVE_PIX        = 640;
    localparam H_FRONT_PORCH_PIX   = 16;
    localparam H_SYNC_PIX          = 96;
    localparam H_BACK_PORCH_PIX    = 48;

    localparam V_ACTIVE_LINES      = 480;
    localparam V_FRONT_PORCH_LINES = 10;
    localparam V_SYNC_LINES        = 2;
    localparam V_BACK_PORCH_LINES  = 33;

    localparam H_TOTAL = H_ACTIVE_PIX + H_FRONT_PORCH_PIX + H_SYNC_PIX + H_BACK_PORCH_PIX;
    localparam V_TOTAL = V_ACTIVE_LINES + V_FRONT_PORCH_LINES + V_SYNC_LINES + V_BACK_PORCH_LINES;

    localparam H_BACK_PORCH_CNT  = H_BACK_PORCH_PIX;
    localparam H_ACTIVE_CNT      = H_BACK_PORCH_CNT + H_ACTIVE_PIX;
    localparam H_FRONT_PORCH_CNT = H_ACTIVE_CNT + H_FRONT_PORCH_PIX;
    localparam H_SYNC_CNT        = H_FRONT_PORCH_CNT + H_SYNC_PIX;

    localparam V_BACK_PORCH_CNT  = V_BACK_PORCH_LINES;
    localparam V_ACTIVE_CNT      = V_BACK_PORCH_CNT + V_ACTIVE_LINES;
    localparam V_FRONT_PORCH_CNT = V_ACTIVE_CNT + V_FRONT_PORCH_LINES;
    localparam V_SYNC_CNT        = V_FRONT_PORCH_CNT + V_SYNC_LINES;

    logic clk, rst_n;
    pixel_t pixel_i;
    logic   h_sync_i, v_sync_i;
    pixel_t pixel_o;
    logic   valid_o;

    pixel_stream #(
        .H_ACTIVE_PIX        (H_ACTIVE_PIX),
        .H_FRONT_PORCH_PIX   (H_FRONT_PORCH_PIX),
        .H_SYNC_PIX          (H_SYNC_PIX),
        .H_BACK_PORCH_PIX    (H_BACK_PORCH_PIX),
        .V_ACTIVE_LINES      (V_ACTIVE_LINES),
        .V_FRONT_PORCH_LINES (V_FRONT_PORCH_LINES),
        .V_SYNC_LINES        (V_SYNC_LINES),
        .V_BACK_PORCH_LINES  (V_BACK_PORCH_LINES)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .pixel_i(pixel_i),
        .h_sync_i(h_sync_i), .v_sync_i(v_sync_i),
        .pixel_o(pixel_o), .valid_o(valid_o)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    // -----------------------------------------------------------------
    // Счётчики: стартуем в начале синхроимпульса
    // -----------------------------------------------------------------
    localparam int H_W = $clog2(H_TOTAL);
    localparam int V_W = $clog2(V_TOTAL);

    logic [H_W-1:0] tb_h_cnt;
    logic [V_W-1:0] tb_v_cnt;
    logic [H_W-1:0] tb_h_cnt_nxt;
    logic [V_W-1:0] tb_v_cnt_nxt;

    always_comb begin
        if (tb_h_cnt == H_TOTAL[H_W-1:0] - 1'b1) begin
            tb_h_cnt_nxt = '0;
            tb_v_cnt_nxt = (tb_v_cnt == V_TOTAL[V_W-1:0] - 1'b1) ? '0 : (tb_v_cnt + 1'b1);
        end else begin
            tb_h_cnt_nxt = tb_h_cnt + 1'b1;
            tb_v_cnt_nxt = tb_v_cnt;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tb_h_cnt <= H_FRONT_PORCH_CNT[H_W-1:0];
            tb_v_cnt <= V_FRONT_PORCH_CNT[V_W-1:0];
        end else begin
            tb_h_cnt <= tb_h_cnt_nxt;
            tb_v_cnt <= tb_v_cnt_nxt;
        end
    end

    assign h_sync_i = ~((tb_h_cnt >= H_FRONT_PORCH_CNT) && (tb_h_cnt < H_SYNC_CNT));
    assign v_sync_i = ~((tb_v_cnt >= V_FRONT_PORCH_CNT) && (tb_v_cnt < V_SYNC_CNT));

    logic tb_h_active, tb_v_active, tb_h_active_nxt, tb_v_active_nxt;
    assign tb_h_active     = (tb_h_cnt     >= H_BACK_PORCH_CNT) && (tb_h_cnt     < H_ACTIVE_CNT);
    assign tb_v_active     = (tb_v_cnt     >= V_BACK_PORCH_CNT) && (tb_v_cnt     < V_ACTIVE_CNT);
    assign tb_h_active_nxt = (tb_h_cnt_nxt >= H_BACK_PORCH_CNT) && (tb_h_cnt_nxt < H_ACTIVE_CNT);
    assign tb_v_active_nxt = (tb_v_cnt_nxt >= V_BACK_PORCH_CNT) && (tb_v_cnt_nxt < V_ACTIVE_CNT);

    // -----------------------------------------------------------------
    // File I/O
    // -----------------------------------------------------------------
    int fd_in, fd_out;
    logic [7:0] r_byte, g_byte, b_byte;
    int pixel_count, out_pixel_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_i.R   <= 8'h00;
            pixel_i.G   <= 8'h00;
            pixel_i.B   <= 8'h00;
            pixel_count <= 0;
        end else if (tb_h_active_nxt && tb_v_active_nxt) begin
            void'($fread(r_byte, fd_in));
            void'($fread(g_byte, fd_in));
            void'($fread(b_byte, fd_in));
          //  $display("T=%0t h=%0d r_byte=%h pixel_i=%h tb_h_active=%b",
          //   $time, tb_h_cnt, r_byte, pixel_i.R, tb_h_active);
            pixel_i.R   <= r_byte;
            pixel_i.G   <= g_byte;
            pixel_i.B   <= b_byte;
            pixel_count <= pixel_count + 1;
        end else begin
            pixel_i.R <= 8'h00;
            pixel_i.G <= 8'h00;
            pixel_i.B <= 8'h00;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) out_pixel_count <= 0;
        else if (valid_o) begin
            $fwrite(fd_out, "%c", pixel_o.R);
            $fwrite(fd_out, "%c", pixel_o.G);
            $fwrite(fd_out, "%c", pixel_o.B);
            out_pixel_count <= out_pixel_count + 1;
        end
    end

    initial begin
        fd_in  = $fopen("images/lemme_chex.raw",     "rb");
        fd_out = $fopen("images/lemme_chex_inv.raw", "wb");
        if (fd_in  == 0) begin $display("ERROR: in");  $finish; end
        if (fd_out == 0) begin $display("ERROR: out"); $finish; end

        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;

        // Один полный кадр + 64 такта на выгрузку последнего valid_o
        repeat (H_TOTAL * V_TOTAL + 64) @(posedge clk);

        $display("INFO: pixels read    = %0d", pixel_count);
        $display("INFO: pixels written = %0d", out_pixel_count);
        $display("INFO: expected       = %0d", H_ACTIVE_PIX * V_ACTIVE_LINES);

        $fclose(fd_in);
        $fclose(fd_out);
        $finish;
    end

    initial begin
        $dumpfile("build/wave.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
