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
	
	//charge logic: hold space to charge, release to launch
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
			end 
		end
		else if (space_release) begin
				move_dist <= hold_count;
				move_req <= (hold_count != 6'd0);
				hold_count <= 6'd0;
			
		end
	
	end
	
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
				  S_CLEAR		= 3'd5,	//repaint the whole screen white (after every reset)
				  S_GAMEOVER	= 3'd6;	//GameOver module owns the screen until reset
	reg[2:0] state;
	
	//score (two BCD digits, shown on HEX5/HEX4 by GameOver)
	reg [3:0] score_tens, score_ones;
	//a successful move = sprite finished erasing and did NOT run off the edge
	wire move_ok = (state == S_ERASE_WAIT) && done && !(X_MAX - sprite_x < move_dist);
	
	//white-clear counters (these are also the pixel being written during S_CLEAR)
	reg [7:0] clr_x;
	reg [6:0] clr_y;
	wire clr_done = (clr_x == 8'd159) && (clr_y == 7'd119);
	
	//who drives the VGA adapter right now
	wire go_active  = (state == S_GAMEOVER);
	wire clr_active = (state == S_CLEAR);

	//draw_sprite outputs (go through the mux, not straight to the adapter)
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

	GameOver overScreen (
		.clk        (CLOCK_50),
		.resetn     (resetn),
		.start      (go_active),		//level is fine: GameOver only looks at start while idle
		.score_tens (score_tens),
		.score_ones (score_ones),
		.x          (go_x),
		.y          (go_y),
		.color      (go_color),
		.plot       (go_plot),
		.hex_tens   (HEX5),
		.hex_ones   (HEX4)
	);
	
	//VGA write-port mux: GameOver > clear > sprite
	assign scr_x  = go_active ? go_x     : clr_active ? clr_x : spr_x;
	assign scr_y  = go_active ? go_y     : clr_active ? clr_y : spr_y;
	assign colour = go_active ? go_color : clr_active ? WHITE : spr_color;
	assign plot   = go_active ? go_plot  : clr_active ? 1'b1  : spr_plot;
	
	
	//main FSM
	always@(posedge CLOCK_50) begin
		if (!resetn) begin
			sprite_x <= 8'd78;
			sprite_y <= 7'd56;
			sprite_color <= BLACK;
			sprite_start <= 1'b0;
			state <= S_CLEAR;
		end else begin
			sprite_start <= 1'b0;
			case(state) 
				S_CLEAR:
					if (clr_done) state <= S_DRAW;
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
						sprite_x <= X_MAX;
						state <= S_GAMEOVER;	//would run off the right edge -> game over
					end else begin
						sprite_x <= sprite_x + move_dist;
						state <= S_DRAW;
					end
				end
				S_GAMEOVER: ;	//stay here until resetn
				default: state <= S_CLEAR;
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
	
	//white-clear counters: sweep 160 x 120 only while state == S_CLEAR
	always @(posedge CLOCK_50) begin
		if (!resetn || state != S_CLEAR) begin
			clr_x <= 8'd0;
			clr_y <= 7'd0;
		end else if (clr_x == 8'd159) begin
			clr_x <= 8'd0;
			clr_y <= clr_y + 1'b1;
		end else clr_x <= clr_x + 1'b1;
	end
	
	assign LEDR = {4'b0, space_down, space_press, space_release, s_down, w_down, space_down};
	

endmodule

`default_nettype wire
