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
	/*
	output wire [7:0] x,            // VGA pixel coordinates
	output wire [6:0] y,
	output wire [2:0] colour,       // VGA pixel colour (0-7)
	output wire plot,               // Pixel drawn when this is pulsed
	output wire vga_resetn          // VGA resets to black when this is pulsed
	*/
	// VGA pins (driven by the vga_adapter instantiated below)
	output wire [7:0] VGA_R,
	output wire [7:0] VGA_G,
	output wire [7:0] VGA_B,
	output wire VGA_HS,
	output wire VGA_VS,
	output wire VGA_BLANK_N,
	output wire VGA_SYNC_N,
	output wire VGA_CLK
	
);

	wire resetn = KEY[0]; 
	
	
	//GAME CLOCK
	reg [25:0] slow_count;
	wire tick = (slow_count == 26'd49999999); //currently 1Hz

    always @(posedge CLOCK_50) begin
        if (!resetn)
            slow_count <= 26'd0;
        else if (tick)
            slow_count <= 26'd0;
        else
            slow_count <= slow_count + 1'b1;
    end

	

	//instantiate the ps2 (keyboard)
	ps2 ps2_inst (
		.clk            (CLOCK_50),
		.rst_n          (resetn),       // KEY[0] is active-low, so it works as the reset
		.ps2_clk        (PS2_CLK),
		.ps2_data       (PS2_DAT),
		.byte_h_digit_h (HEX3),         // leftmost digit
		.byte_h_digit_l (HEX2),
		.byte_l_digit_h (HEX1),
		.byte_l_digit_l (HEX0)          // rightmost digit
	);
	
	//x and y depend on resolution -> current resolution = 160 x 120
	//640x480 -> [9:0], [8:0]
	//320x240 -> [8:0], [7:0]
	//160x120 -> [7:0], [6:0]
	wire [7:0]scr_x;
	wire [6:0]scr_y;
	
	//color -> {RRR, GGG, BBB}
	wire [8:0]colour;
	
	wire plot, done;
	
	
	//instantiate the VGA 
	vga_adapter VGA( 
		.resetn			(resetn), 
		.clock			(CLOCK_50), 
		.color			(colour), 
		.x					(scr_x), 
		.y					(scr_y), 
		.write			(plot),
      .VGA_R			(VGA_R), 
		.VGA_G			(VGA_G), 
		.VGA_B			(VGA_B), 
		.VGA_HS			(VGA_HS), 
		.VGA_VS			(VGA_VS), 
		.VGA_BLANK_N	(VGA_BLANK_N), 
		.VGA_SYNC_N		(VGA_SYNC_N), 
		.VGA_CLK			(VGA_CLK)
	);
	
	//draw the sprite
	wire[7:0] sprite_x = 8'd78;
	wire[6:0] sprite_y = 7'd56;
	
	reg draw_started;
	reg sprite_start;
	
	always @(posedge CLOCK_50) begin
		if (!resetn) begin
			draw_started <= 1'b0;
			sprite_start <= 1'b0;
		end else begin
			sprite_start <= 1'b0;
			if (!draw_started) begin
				sprite_start <= 1'b1;
				draw_started <= 1'b1;
			end
		end
	end
	
	draw_sprite sprite_inst (
		.clk          (CLOCK_50),
		.resetn       (resetn),
		.start        (sprite_start),
		.px           (sprite_x),
		.py           (sprite_y),
		.x            (scr_x),          // straight into the adapter
		.y            (scr_y),
		.color        (colour),
		.plot         (plot),
		.done         (done)
	);
	

	
	

endmodule

`default_nettype wire