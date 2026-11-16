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
	wire score = 0;
	
	
	//GAME CLOCK
	reg [25:0] slow_count;
	wire tick = (slow_count == 26'd4999999); //every 100ms (adjust to 60fps later)

    always @(posedge CLOCK_50) begin
        if (!resetn || tick)
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
	/*
	defparam VGA.RESOLUTION = "160x120";
	defparam VGA.COLOR_DEPTH = 9;
	defparam VGA.BACKGROUND_IMAGE = "white.mif";
	*/
	
	
	//key tracking
	wire space_down, space_press, space_release;
	wire w_down, w_press, w_release;
	wire s_down, s_press, s_release;
	
	key_detect keys (
		.clk            (CLOCK_50),
		.resetn         (resetn),
		.HEX3		       (HEX3),
		.HEX2		       (HEX2),
		.HEX1		       (HEX1),
		.HEX0		       (HEX0),
		.space_down     (space_down),
		.space_pressed  (space_press),
		.space_released (space_release),
		.w_down         (w_down),
		.w_pressed      (w_press),
		.w_released     (w_release),
		.s_down         (s_down),
		.s_pressed      (s_press),
		.s_released     (s_release)
	);
	
	localparam[5:0] MAX_DIST = 6'd40;
	reg[5:0] hold_count;
	reg[5:0] move_dist;
	reg move_req;
	
	always @(posedge CLOCK_50) begin
		move_req <= 1'b0;
		if (!resetn) begin
			hold_count <= 6'd0;
			move_dist <= 6'd0;
			
		end else if (space_press) begin
			hold_count <= 6'd1;
			
		end else if (space_down) begin
			if (tick && (hold_count < MAX_DIST)) begin
				hold_count <= hold_count + 1'b1;
			end else if (space_release) begin
				move_dist <= hold_count;
				move_req <= (hold_count != 6'd0);
				hold_count <= 6'd0;
			end
		end
	
	end
	
	//draw the sprite
	localparam [8:0] WHITE = 9'b111_111_111;
	localparam [8:0] BLACK = 9'b000_000_000;
	localparam [7:0] X_MAX = 160 - 4; //Edge of screen (MUST BE ADJUSTED IF SCREEN OR SPRITE SIZE CHANGED)
	
	reg[7:0] sprite_x = 8'd78;	//set initial position
	reg[6:0] sprite_y = 7'd56;
	reg [8:0] sprite_color = BLACK;
	reg sprite_start;
	
	draw_sprite sprite_inst (
		.clk          (CLOCK_50),
		.resetn       (resetn),
		.start        (sprite_start),
		.px           (sprite_x),
		.py           (sprite_y),
		.sprite_color (sprite_color),
		.x            (scr_x),          // straight into the adapter
		.y            (scr_y),
		.color        (colour),
		.plot         (plot),
		.done         (done)
	);
	
	localparam S_DRAW			= 3'd0,	//draw the sprite
				  S_DRAW_WAIT	= 3'd1,
				  S_IDLE			= 3'd2,
				  S_ERASE		= 3'd3,
				  S_ERASE_WAIT	= 3'd4;
	reg[2:0] state;
	
	always@(posedge CLOCK_50) begin
		if (!resetn) begin
			sprite_x <= 8'd78;
			sprite_y <= 7'd56;
			sprite_color <= BLACK;
			sprite_start <= 1'b0;
			state <= S_DRAW;
		end else begin
			sprite_start <= 1'b0;
			case(state) 
				S_DRAW: begin
					sprite_color <= BLACK;
					sprite_start <= 1'b1;
					state <= S_DRAW_WAIT;
				end
				S_DRAW_WAIT:
					if (done) state <= S_IDLE;
				S_IDLE:
					if (move_req) state <= S_ERASE;
				S_ERASE: begin
					sprite_color <= WHITE;
					sprite_start <= 1'b1;
					state <= S_ERASE_WAIT;
				end
				S_ERASE_WAIT: if (done) begin
					if (X_MAX - sprite_x < move_dist) begin
						sprite_x <= X_MAX; //TEMPORARY
						//SET GAME OVER CONDITION
					end else begin
						sprite_x <= sprite_x + move_dist;
						state <= S_DRAW;
					end
				end
				default: state <= S_DRAW;
			endcase
		end
	end
	
	assign LEDR = {7'b0, s_down, w_down, space_down};
	

endmodule

`default_nettype wire