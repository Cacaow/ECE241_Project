
`timescale 1ns / 1ps
`default_nettype none

module tb_GameOver();

reg clk = 0;
reg resetn = 0;
reg start = 0;

reg [3:0] score_tens = 0;
reg [3:0] score_ones = 5;

wire [7:0] x;
wire [6:0] y;
wire [8:0] color;
wire plot;

wire [6:0] hex_tens;
wire [6:0] hex_ones;

integer background_pixels = 0;
integer text_pixels = 0;
integer errors = 0;
integer cycles = 0;

// 20 ns clock period
always #10 clk = ~clk;

// DUT
GameOver DUT (
    .clk(clk),
    .resetn(resetn),
    .start(start),
    .score_tens(score_tens),
    .score_ones(score_ones),
    .x(x),
    .y(y),
    .color(color),
    .plot(plot),
    .hex_tens(hex_tens),
    .hex_ones(hex_ones)
);

// Advance the blink counter to its next tick.
// The normal counter threshold is 24,999,999.
task force_blink_tick;
    begin
        @(negedge clk);
        DUT.blink_count = 25'd24999998;

        // First edge increments the counter.
        // Second edge detects tick and changes blink_state.
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
    end
endtask

initial begin
    $display("Starting GameOver test...");

    // Reset
    resetn = 0;
    repeat (3) @(negedge clk);
    resetn = 1;

    // Start game-over screen
    @(negedge clk);
    start = 1;
    @(negedge clk);
    start = 0;

    // Monitor the background and text drawing
    while ((DUT.state != 2'd3) && (cycles < 30000)) begin
        @(negedge clk);
        cycles = cycles + 1;

        if (plot) begin
            if (color == 9'b111_111_111) begin
                background_pixels = background_pixels + 1;

                // Background should cover the whole screen
                if (x > 159 || y > 119) begin
                    $display("FAIL: Background pixel outside screen.");
                    errors = errors + 1;
                end
            end

            if (color == 9'b111_000_000) begin
                text_pixels = text_pixels + 1;

                // Text should be inside the expected drawing area
                if (x < 8 || x > 151 || y < 52 || y > 67) begin
                    $display("FAIL: Text pixel outside expected area.");
                    errors = errors + 1;
                end
            end
        end
    end

    // Check that the FSM reached S_HOLD
    if (DUT.state == 2'd3)
        $display("PASS: GameOver reached S_HOLD.");
    else begin
        $display("FAIL: GameOver did not reach S_HOLD.");
        errors = errors + 1;
    end

    // Check background
    if (background_pixels == 19200)
        $display("PASS: All 19200 background pixels were drawn.");
    else begin
        $display("FAIL: Expected 19200 background pixels, got %0d.",
                 background_pixels);
        errors = errors + 1;
    end

    // Check text
    if (text_pixels > 0)
        $display("PASS: GAME OVER text pixels were drawn (%0d pixels).",
                 text_pixels);
    else begin
        $display("FAIL: No GAME OVER text pixels were drawn.");
        errors = errors + 1;
    end

    // Check that score is initially visible
    if (hex_tens !== 7'b1111111 && hex_ones !== 7'b1111111)
        $display("PASS: Score is initially visible.");
    else begin
        $display("FAIL: Score should initially be visible.");
        errors = errors + 1;
    end

    // Advance blink state:
    // B_ON1 -> B_ON2 -> B_ON3 -> B_GAP
    force_blink_tick;
    force_blink_tick;
    force_blink_tick;

    // Score should now be blank
    if (hex_tens === 7'b1111111 && hex_ones === 7'b1111111)
        $display("PASS: Score turns off during blink gap.");
    else begin
        $display("FAIL: Score did not turn off.");
        errors = errors + 1;
    end

    // B_GAP -> B_ON1
    force_blink_tick;

    // Score should be visible again
    if (hex_tens !== 7'b1111111 && hex_ones !== 7'b1111111)
        $display("PASS: Score turns back on.");
    else begin
        $display("FAIL: Score did not turn back on.");
        errors = errors + 1;
    end

    if (errors == 0)
        $display("GAMEOVER TEST PASSED!");
    else
        $display("GAMEOVER TEST FAILED: %0d errors.", errors);

    #20;
    $finish;
end

endmodule
