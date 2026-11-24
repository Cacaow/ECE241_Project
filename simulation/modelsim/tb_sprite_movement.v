`timescale 1ns/1ps

// Verilog-2001 sprite movement testbench for main.v.
// Save as: simulation/modelsim/tb_sprite_movement.v
//
// This tests the movement FSM and the REAL draw_sprite module.
// To keep simulation quick, it forces the decoded Space signals and the
// 100 ms game tick. The PS/2 protocol and actual VGA hardware are not tested.
//
// Compile from simulation/modelsim (assuming the .v design files are in
// the project root):
//   vlib work
//   vlog ../../main.v ../../draw_sprite.v ../../key_detect.v \
//        ../../ps2.v ../../deb.v ../../hex.v tb_sprite_movement.v
//   vsim -voptargs=+acc work.tb_sprite_movement
//   run -all
//
// IMPORTANT: Do not compile vga_adapter.v into the same work library:
// the VGA stub at the bottom of this file replaces it for this test.

module tb_sprite_movement;
    reg CLOCK_50;
    reg PS2_CLK;
    reg PS2_DAT;
    reg [9:0] SW;
    reg [3:0] KEY;

    wire [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
    wire [9:0] LEDR;
    wire [7:0] VGA_R, VGA_G, VGA_B;
    wire VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK;

    localparam [8:0] BLACK = 9'b000_000_000;
    localparam [8:0] WHITE = 9'b111_111_111;
    localparam [2:0] S_IDLE = 3'd2;
    localparam integer SPRITE_PIXELS = 32; // 4x8 pixels

    integer pixel_count;
    integer segment;
    integer offset;
    integer base_x;
    integer expected_x;
    integer expected_y;
    reg [8:0] expected_color;

    main dut (
        .CLOCK_50(CLOCK_50),
        .PS2_CLK(PS2_CLK),
        .PS2_DAT(PS2_DAT),
        .SW(SW),
        .KEY(KEY),
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2),
        .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
        .LEDR(LEDR),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N), .VGA_CLK(VGA_CLK)
    );

    // 50 MHz, as on the board.
    always #10 CLOCK_50 = ~CLOCK_50;

    // End the whole simulation on the first failed check.
    task fail;
        input [1023:0] reason;
        begin
            $display("FAIL at %0t: %0s", $time, reason);
            $finish;
        end
    endtask

    // Verify EACH sprite pixel in draw/erase/redraw order:
    // 0: black x=78; 1: white x=78; 2: black x=83;
    // 3: white x=83; 4: black x=84; 5: white x=84;
    // 6: black x=124.
    always @(negedge CLOCK_50) begin
        if (KEY[0] && dut.plot === 1'b1) begin
            segment = pixel_count / SPRITE_PIXELS;
            offset  = pixel_count % SPRITE_PIXELS;
            case (segment)
                0, 1: base_x = 78;
                2, 3: base_x = 83;
                4, 5: base_x = 84;
                6:    base_x = 124;
                default: fail("Unexpected extra sprite pixel write");
            endcase

            expected_x = base_x + (offset % 4);
            expected_y = 56 + (offset / 4);
            if (segment == 1 || segment == 3 || segment == 5)
                expected_color = WHITE;
            else
                expected_color = BLACK;

            if (dut.scr_x !== expected_x ||
                dut.scr_y !== expected_y ||
                dut.colour !== expected_color) begin
                $display("Pixel %0d: got x=%0d y=%0d color=%03h; expected x=%0d y=%0d color=%03h",
                    pixel_count, dut.scr_x, dut.scr_y, dut.colour,
                    expected_x, expected_y, expected_color);
                fail("Sprite pixel coordinates or color are incorrect");
            end
            pixel_count = pixel_count + 1;
        end
    end

    // Wait for an expected number of writes and return to the idle state.
    task wait_for_idle;
        input integer expected_pixels;
        integer cycles;
        begin
            cycles = 0;
            while ((dut.state !== S_IDLE || pixel_count != expected_pixels)
                   && cycles < 250) begin
                @(negedge CLOCK_50);
                #1;
                cycles = cycles + 1;
            end
            if (cycles == 250) begin
                $display("state=%0d pixels=%0d expected=%0d",
                    dut.state, pixel_count, expected_pixels);
                fail("Timeout waiting for drawing to finish");
            end
        end
    endtask

    // Simulate the decoded Space key PRESS, without sending PS/2 bits.
    task press_space;
        begin
            @(negedge CLOCK_50);
            #1;
            force dut.space_down  = 1'b1;
            force dut.space_press = 1'b1;
            @(negedge CLOCK_50);
            #1;
            release dut.space_press;
            if (dut.hold_count !== 6'd1)
                fail("Space press did not set hold_count to 1");
        end
    endtask

    // Advance the held-key counter by n game ticks without waiting 100 ms.
    task hold_for_ticks;
        input integer n;
        begin
            @(negedge CLOCK_50);
            #1;
            force dut.tick = 1'b1;
            repeat (n) @(posedge CLOCK_50);
            @(negedge CLOCK_50);
            #1;
            release dut.tick;
        end
    endtask

    // Simulate the decoded Space key RELEASE.
    task release_space;
        begin
            @(negedge CLOCK_50);
            #1;
            force dut.space_down    = 1'b0;
            force dut.space_release = 1'b1;
            @(negedge CLOCK_50);
            #1;
            release dut.space_release;
            release dut.space_down;
        end
    endtask

    initial begin
        CLOCK_50 = 1'b0;
        PS2_CLK = 1'b1;
        PS2_DAT = 1'b1;
        SW = 10'b0;
        KEY = 4'b1110; // KEY[0]=0 applies reset
        pixel_count = 0;

        repeat (5) @(negedge CLOCK_50);
        #1;
        KEY[0] = 1'b1; // release reset

        // Test 1: Initial sprite position and black pixels.
        wait_for_idle(32);
        if (dut.sprite_x !== 8'd78 || dut.sprite_y !== 7'd56)
            fail("Incorrect initial position (expected 78,56)");
        $display("PASS: initial black sprite at (78,56)");

        // Test 2: Count starts at 1, plus 4 ticks = 5-pixel movement.
        press_space;
        hold_for_ticks(4);
        if (dut.hold_count !== 6'd5 || dut.sprite_x !== 8'd78)
            fail("Hold should count 5, without moving before release");
        release_space;
        wait_for_idle(96);
        if (dut.sprite_x !== 8'd83 || dut.move_dist !== 6'd5)
            fail("Expected move of 5 pixels: x=78 to x=83");
        $display("PASS: held Space -> erase, move +5, redraw at x=83");

        // Test 3: A short tap moves only one pixel.
        press_space;
        release_space;
        wait_for_idle(160);
        if (dut.sprite_x !== 8'd84 || dut.move_dist !== 6'd1)
            fail("Expected short tap to move 1 pixel: x=83 to x=84");
        $display("PASS: short tap -> erase, move +1, redraw at x=84");

        // Test 4: Holding longer than 40 ticks must cap movement at 40.
        press_space;
        hold_for_ticks(45);
        if (dut.hold_count !== 6'd40)
            fail("Hold counter should saturate at 40");
        release_space;
        wait_for_idle(224);
        if (dut.sprite_x !== 8'd124 || dut.move_dist !== 6'd40)
            fail("Expected capped move of 40 pixels: x=84 to x=124");
        $display("PASS: long hold -> capped +40, redraw at x=124");

        // Test 5: No unintended movement/drawing during idle.
        repeat (20) @(negedge CLOCK_50);
        #1;
        if (dut.sprite_x !== 8'd124 ||
            pixel_count != 224 || dut.state !== S_IDLE)
            fail("Sprite moved or drew again without another Space release");
        $display("PASS: stationary during idle");
        $display("ALL TESTS PASSED: %0d sprite pixel writes verified", pixel_count);
        $finish;
    end

    // Global timeout, in case a test cannot make forward progress.
    initial begin
        #200000;
        fail("Global simulation timeout");
    end
endmodule

// Lightweight VGA stub, used ONLY for this movement simulation.
// The actual vga_adapter.v is intentionally omitted from compilation.
module vga_adapter (
    input wire resetn,
    input wire clock,
    input wire [8:0] color,
    input wire [7:0] x,
    input wire [6:0] y,
    input wire write,
    output wire [7:0] VGA_R,
    output wire [7:0] VGA_G,
    output wire [7:0] VGA_B,
    output wire VGA_HS,
    output wire VGA_VS,
    output wire VGA_BLANK_N,
    output wire VGA_SYNC_N,
    output wire VGA_CLK
);
    assign VGA_R = 8'd0;
    assign VGA_G = 8'd0;
    assign VGA_B = 8'd0;
    assign VGA_HS = 1'b1;
    assign VGA_VS = 1'b1;
    assign VGA_BLANK_N = 1'b1;
    assign VGA_SYNC_N = 1'b0;
    assign VGA_CLK = clock;
endmodule
