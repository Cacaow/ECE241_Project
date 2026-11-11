`timescale 1ns / 1ps
`default_nettype none

module main (
	input wire CLOCK_50,            // On Board 50 MHz

	input wire PS2_CLK,             // PS/2 keyboard clock
	input wire PS2_DAT,             // PS/2 keyboard data

	input wire [9:0] SW,            // On board Switches
	input wire [3:0] KEY,           // On board push buttons
	output wire [6:0] HEX0,         // HEX displays
	output wire [6:0] HEX1,
	output wire [6:0] HEX2,
	output wire [6:0] HEX3,
	output wire [6:0] HEX4,
	output wire [6:0] HEX5,
	output wire [9:0] LEDR,         // LEDs
	output wire [7:0] x,            // VGA pixel coordinates
	output wire [6:0] y,
	output wire [2:0] colour,       // VGA pixel colour (0-7)
	output wire plot,               // Pixel drawn when this is pulsed
	output wire vga_resetn          // VGA resets to black when this is pulsed (NOT CURRENTLY AVAILABLE)
);

	// PS/2 keyboard scan code -> HEX3..HEX0
	ps2 ps2_inst (
		.clk            (CLOCK_50),
		.rst_n          (KEY[0]),       // KEY[0] is active-low, so it works as the reset
		.ps2_clk        (PS2_CLK),
		.ps2_data       (PS2_DAT),
		.byte_h_digit_h (HEX3),         // leftmost digit
		.byte_h_digit_l (HEX2),
		.byte_l_digit_h (HEX1),
		.byte_l_digit_l (HEX0)          // rightmost digit
	);

	// turn off the unused displays (active-low, so all 1s = off)
	assign HEX4 = 7'b1111111;
	assign HEX5 = 7'b1111111;

	// unused outputs tied off
	assign LEDR       = 10'b0;
	assign x          = 8'b0;
	assign y          = 7'b0;
	assign colour     = 3'b0;
	assign plot       = 1'b0;
	assign vga_resetn = 1'b1;

endmodule

`default_nettype wire