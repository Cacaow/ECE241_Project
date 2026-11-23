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
	
	
	//sprite settings
	localparam [8:0] WHITE = 9'b111_111_111;
	localparam [8:0] BLACK = 9'b000_000_000;
	localparam [7:0] X_MAX = 160 - 4; //Edge of screen (MUST BE ADJUSTED IF SCREEN OR SPRITE SIZE CHANGED)
	
	reg[7:0] sprite_x = 8'd78;	//set initial position
	reg[6:0] sprite_y = 7'd56;
	reg [8:0] sprite_color = BLACK;
	reg sprite_start;
	
	//main FSM states
	localparam S_DRAW			= 3'd0,	//draw the sprite
				  S_DRAW_WAIT	= 3'd1,
				  S_IDLE			= 3'd2,
				  S_ERASE		= 3'd3,
				  S_ERASE_WAIT	= 3'd4,
				  S_GAMEOVER	= 3'd6;	//GameOver until reset
	reg[2:0] state;
	
	//DISTANCE
	localparam[9:0] MAX_DIST = 9'd200;
	reg[9:0] hold_count;
	reg[9:0] move_dist;
	reg move_req;
	
	
	//ANGLE
	localparam[9:0]MAX_ANGLE = 180;
	localparam[9:0]MIN_ANGLE = 0;
	reg[9:0] angle = 90;
	reg[9:0] move_angle;
	
	wire angle_up = w_press || (w_down && tick);
	wire angle_down = s_press || (s_down && tick);
	
	always @(posedge CLOCK_50) begin
		if (!resetn) begin
			angle <= 10'd90;
		end else if ((state == S_IDLE) && !space_down && !space_release && !move_req) begin
			if (angle_up && !angle_down) begin
				if (angle < MAX_ANGLE) begin
					angle <= angle + 1'b1;
				end
			end else if (angle_down && !angle_up) begin
				if (angle > MIN_ANGLE) begin
					angle <= angle - 1'b1;
				end
			end
		end
	end
	
	wire[9:0] jump_dx;
	wire[9:0] jump_dy;
	wire jump_side;
	
	jump_calc calc(
		.clk		(CLOCK_50),
		.angle	(move_angle),
		.dist 	(move_dist),
		.dx_mag	(jump_dx),
		.dx_side	(jump_side),
		.dy_mag	(jump_dy)
	);
	
	
	//Jump
	always @(posedge CLOCK_50) begin
		move_req <= 1'b0;
		if (!resetn) begin
			hold_count <= 9'd0;
			move_dist <= 9'd0;
			
		end else if (space_press) begin
			hold_count <= 9'd1;
			
		end else if (space_down) begin
			if (tick && (hold_count < MAX_DIST)) begin
				hold_count <= hold_count + 1'b1;
			end 
		end
		else if (space_release) begin
				move_dist <= hold_count;
				move_angle <= angle;
				move_req <= (hold_count != 9'd0);
				hold_count <= 9'd0;
			
		end
	end
	
	wire [7:0] spr_x;
	wire [6:0] spr_y;
	wire [8:0] spr_color;
	wire       spr_plot;
	

	draw_sprite sprite_inst (
		.clk          (CLOCK_50),
		.resetn       (resetn),
		.start        (sprite_start),
		.px           (sprite_x),
		.py           (sprite_y),
		.sprite_color (sprite_color),
		.x            (spr_x),		
		.y            (spr_y),
		.color        (spr_color),
		.plot         (spr_plot),
		.done         (done)
	);
	
	//game over screen outputs (also go through the mux)
	wire [7:0] go_x;
	wire [6:0] go_y;
	wire [8:0] go_color;
	wire       go_plot;
	reg [3:0] score_tens = 4'd0;
	reg [3:0] score_ones = 4'd0;
	reg move_ok;

	GameOver overScreen (
		.clk        (CLOCK_50),
		.resetn     (resetn),
		.start      (state == S_GAMEOVER),	
		.score_tens (score_tens),
		.score_ones (score_ones),
		.x          (go_x),
		.y          (go_y),
		.color      (go_color),
		.plot       (go_plot),
		.hex_tens   (HEX5),
		.hex_ones   (HEX4)
	);
	
	assign scr_x  = (state == S_GAMEOVER) ? go_x     : spr_x;
	assign scr_y  = (state == S_GAMEOVER) ? go_y     : spr_y;
	assign colour = (state == S_GAMEOVER) ? go_color : spr_color;
	assign plot   = (state == S_GAMEOVER) ? go_plot  : spr_plot;
	
	
	//main FSM
	always@(posedge CLOCK_50) begin
		move_ok <= 1'b0;	//one-cycle pulse (set below on a successful move)
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
					if (jump_dy > sprite_y) begin		//would leave the top of the screen
						state <= S_GAMEOVER;
					end else if (jump_side) begin	//jump to left
						if (jump_dx > sprite_x) begin	//would leave the left edge
							state <= S_GAMEOVER;
						end else begin
							sprite_x <= sprite_x - jump_dx;
							sprite_y <= sprite_y - jump_dy;
							move_ok <= 1'b1;
							state <= S_DRAW;
						end
					end else begin
						if (sprite_x + jump_dx > X_MAX) begin
							state <= S_GAMEOVER;
						end else begin
							sprite_x <= sprite_x + jump_dx;
							sprite_y <= sprite_y - jump_dy;
							move_ok <= 1'b1;
							state <= S_DRAW;
						end
					end
				end
				S_GAMEOVER: 
					sprite_color <= WHITE;	//stay here until resetn
				default: state <= S_DRAW;
			endcase
		end
	end
	
	//score counter (BCD): +1 per successful move, cleared on reset
	always @(posedge CLOCK_50) begin
		if (!resetn) begin
			score_tens <= 4'd0;
			score_ones <= 4'd0;
		end else if (move_ok) begin
			if (score_ones == 4'd9) begin
				score_ones <= 4'd0;
				score_tens <= score_tens + 1'b1;
			end else score_ones <= score_ones + 1'b1;
		end
	end
	
	assign LEDR = {7'b0, s_down, w_down, space_down};
	

endmodule

`default_nettype wire