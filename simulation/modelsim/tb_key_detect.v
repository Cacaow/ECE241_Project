
`timescale 1ns / 1ps
`default_nettype none

module tb_key_detect();

reg clk = 0;
reg resetn = 0;

reg [6:0] HEX3 = 7'h7F;
reg [6:0] HEX2 = 7'h7F;
reg [6:0] HEX1 = 7'h7F;
reg [6:0] HEX0 = 7'h7F;

wire space_down;
wire space_pressed;
wire space_released;

wire w_down;
wire w_pressed;
wire w_released;

wire s_down;
wire s_pressed;
wire s_released;

integer errors = 0;
integer press_count;
integer release_count;
integer i;

// 20 ns clock period
always #10 clk = ~clk;

// DUT
key_detect DUT (
    .clk(clk),
    .resetn(resetn),
    .HEX3(HEX3),
    .HEX2(HEX2),
    .HEX1(HEX1),
    .HEX0(HEX0),
    .space_down(space_down),
    .space_pressed(space_pressed),
    .space_released(space_released),
    .w_down(w_down),
    .w_pressed(w_pressed),
    .w_released(w_released),
    .s_down(s_down),
    .s_pressed(s_pressed),
    .s_released(s_released)
);

// Test one key.
// which = 0 for Space, 1 for W, 2 for S.
task test_key;
    input [6:0] code_hi;
    input [6:0] code_lo;
    input integer which;

    begin
        // Clear previous displayed bytes
        HEX3 = 7'h7F;
        HEX2 = 7'h7F;
        HEX1 = 7'h7F;
        HEX0 = 7'h7F;
        repeat (3) @(negedge clk);

        // Send the key make code
        HEX1 = ~code_hi;
        HEX0 = ~code_lo;

        press_count = 0;

        // Observe the press detection
        repeat (6) begin
            @(negedge clk);
            case (which)
                0: if (space_pressed) press_count = press_count + 1;
                1: if (w_pressed)     press_count = press_count + 1;
                2: if (s_pressed)     press_count = press_count + 1;
            endcase
        end

        // Check that the key is held
        case (which)
            0: if (space_down !== 1'b1) begin
                   $display("FAIL: Space did not become held.");
                   errors = errors + 1;
               end
            1: if (w_down !== 1'b1) begin
                   $display("FAIL: W did not become held.");
                   errors = errors + 1;
               end
            2: if (s_down !== 1'b1) begin
                   $display("FAIL: S did not become held.");
                   errors = errors + 1;
               end
        endcase

        if (press_count == 1)
            $display("PASS: Key %0d press pulse occurred once.", which);
        else begin
            $display("FAIL: Key %0d press pulse count = %0d.",
                     which, press_count);
            errors = errors + 1;
        end

        // Send the break code F0 while keeping the key code
        HEX3 = ~7'h71;
        HEX2 = ~7'h3F;

        release_count = 0;

        repeat (6) begin
            @(negedge clk);
            case (which)
                0: if (space_released) release_count = release_count + 1;
                1: if (w_released)     release_count = release_count + 1;
                2: if (s_released)     release_count = release_count + 1;
            endcase
        end

        // Check that the key is no longer held
        case (which)
            0: if (space_down !== 1'b0) begin
                   $display("FAIL: Space did not release.");
                   errors = errors + 1;
               end
            1: if (w_down !== 1'b0) begin
                   $display("FAIL: W did not release.");
                   errors = errors + 1;
               end
            2: if (s_down !== 1'b0) begin
                   $display("FAIL: S did not release.");
                   errors = errors + 1;
               end
        endcase

        if (release_count == 1)
            $display("PASS: Key %0d release pulse occurred once.", which);
        else begin
            $display("FAIL: Key %0d release pulse count = %0d.",
                     which, release_count);
            errors = errors + 1;
        end
    end
endtask

initial begin
    $display("Starting key_detect test...");

    // Reset and allow the previous-key registers to initialize
    resetn = 0;
    repeat (3) @(negedge clk);
    resetn = 1;
    repeat (3) @(negedge clk);

    // Space scan code = 29
    $display("Testing Space...");
    test_key(7'h02, 7'h09, 0);

    // W scan code = 1D
    $display("Testing W...");
    test_key(7'h01, 7'h0D, 1);

    // S scan code = 1B
    $display("Testing S...");
    test_key(7'h01, 7'h0B, 2);

    if (errors == 0)
        $display("KEY_DETECT TEST PASSED!");
    else
        $display("KEY_DETECT TEST FAILED: %0d errors.", errors);

    #20;
    $finish;
end

endmodule
