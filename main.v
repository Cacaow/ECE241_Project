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

	//power-on reset: holds everything in reset for ~15 clocks after the FPGA is programmed,
	//so the platforms and the FSM are set up even if KEY0 is never pressed
	reg [3:0] por = 4'd0;
	always @(posedge CLOCK_50)
		if (por != 4'hF) por <= por + 4'd1;
	wire resetn = KEY[0] & (por == 4'hF);
	
	
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
	
	
	//=====================================================================
	//  constants
	//=====================================================================
	localparam [8:0] WHITE      = 9'b111_111_111;
	localparam [8:0] BLACK      = 9'b000_000_000;
	localparam [8:0] PLAT_COLOR = 9'b100_010_000;		//brown

	localparam [7:0] SPRITE_W       = 8'd4;
	localparam [7:0] SPRITE_H       = 8'd8;
	localparam [7:0] SPRITE_START_X = 8'd78;		//sprite's resting screen position (left edge)
	localparam [6:0] SPRITE_START_Y = 7'd56;
	localparam integer SPRITE_HALF  = 2;			//SPRITE_W / 2: the sprite's "centre" column = x + 2

	localparam [6:0] PLAT_Y = 7'd64;			//top of every platform = bottom of the sprite (56 + 8)
	localparam [7:0] PLAT_H = 8'd4;
	localparam [2:0] N_PLAT = 3'd4;				//platform slots (only 2 used for now)
	localparam [2:0] IDX_SPRITE = 3'd4;			//draw_idx value meaning "draw the sprite"

	
	//=====================================================================
	//  game state
	//=====================================================================
	//sprite position (screen coordinates)
	reg [7:0] sprite_x = SPRITE_START_X;
	reg [6:0] sprite_y = SPRITE_START_Y;

	//platforms: left edge (SIGNED, so a platform can later slide partly off the left of the screen)
	//and width. width 0 = empty slot. All platforms share the same y and height.
	reg signed [9:0] plat_x [0:3];
	reg        [7:0] plat_w [0:3];
	reg        [1:0] cur_idx;				//which platform the sprite is standing on

	//inputs of the rectangle drawer: the FSM loads these, then pulses draw_start
	reg signed [9:0] d_x;
	reg        [6:0] d_y;
	reg        [7:0] d_w, d_h;
	reg        [8:0] d_color;
	reg              draw_start;
	reg        [2:0] draw_idx;				//0..3 = platform slot, 4 = the sprite

	//room for the screen shift (next step)
	reg              pending_shift;				//set when the sprite landed on a NEW platform
	reg        [7:0] shift_left;				//how far everything must slide left to re-centre the sprite

	//main FSM states
	localparam S_DRAW			= 3'd0,	//draw platforms (idx 0..3) and the sprite (idx 4), one rectangle at a time
				  S_DRAW_WAIT	= 3'd1,
				  S_IDLE			= 3'd2,	//wait for a jump
				  S_ERASE		= 3'd3,	//erase the sprite at its old position
				  S_ERASE_WAIT	= 3'd4,	//landing check happens here
				  S_CLEAR		= 3'd5,	//repaint the whole screen white (after every reset)
				  S_GAMEOVER	= 3'd6,	//GameOver module owns the screen until reset
				  S_SHIFT		= 3'd7;	//(placeholder) slide the screen so the sprite is centred again
	reg[2:0] state;
	
	//score (two BCD digits, shown on HEX5/HEX4 by GameOver)
	reg [3:0] score_tens, score_ones;

	
	//=====================================================================
	//  landing check: where would the sprite's centre be after the jump?
	//=====================================================================
	wire [7:0] new_x = sprite_x + move_dist;				//left edge after the jump
	wire signed [9:0] nc = $signed({2'b00, new_x}) + SPRITE_HALF;		//centre column (signed to compare with plat_x)

	wire [3:0] hit;

	assign hit[0] = (plat_w[0] != 0) &&
						 (nc >= plat_x[0]) &&
						 (nc < plat_x[0] + plat_w[0]);

	assign hit[1] = (plat_w[1] != 0) &&
						 (nc >= plat_x[1]) &&
						 (nc < plat_x[1] + plat_w[1]);

	assign hit[2] = (plat_w[2] != 0) &&
						 (nc >= plat_x[2]) &&
						 (nc < plat_x[2] + plat_w[2]);

	assign hit[3] = (plat_w[3] != 0) &&
						 (nc >= plat_x[3]) &&
						 (nc < plat_x[3] + plat_w[3]);

	wire any_hit = |hit;

	wire [1:0] hit_idx =
		 hit[3] ? 2'd3 :
		 hit[2] ? 2'd2 :
		 hit[1] ? 2'd1 : 2'd0;
	//a successful jump to a DIFFERENT platform scores a point
	wire score_inc = (state == S_ERASE_WAIT) && done && any_hit && (hit_idx != cur_idx);
	
	
	//white-clear counters (these are also the pixel being written during S_CLEAR)
	reg [7:0] clr_x;
	reg [6:0] clr_y;
	wire clr_done = (clr_x == 8'd159) && (clr_y == 7'd119);
	
	//who drives the VGA adapter right now
	wire go_active  = (state == S_GAMEOVER);
	wire clr_active = (state == S_CLEAR);

	//rectangle drawer outputs (go through the mux, not straight to the adapter)
	wire [7:0] spr_x;
	wire [6:0] spr_y;
	wire [8:0] spr_color;
	wire       spr_plot;

	draw_sprite sprite_inst (
		.clk          (CLOCK_50),
		.resetn       (resetn),
		.start        (draw_start),
		.px           (d_x),
		.py           (d_y),
		.w            (d_w),
		.h            (d_h),
		.sprite_color (d_color),
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
	
	//VGA write-port mux: GameOver > clear > rectangle drawer
	assign scr_x  = go_active ? go_x     : clr_active ? clr_x : spr_x;
	assign scr_y  = go_active ? go_y     : clr_active ? clr_y : spr_y;
	assign colour = go_active ? go_color : clr_active ? WHITE : spr_color;
	assign plot   = go_active ? go_plot  : clr_active ? 1'b1  : spr_plot;
	
	
	//=====================================================================
	//  main FSM
	//=====================================================================
	always@(posedge CLOCK_50) begin
		if (!resetn) begin
			sprite_x      <= SPRITE_START_X;
			sprite_y      <= SPRITE_START_Y;
			d_x           <= 0;
			d_y           <= 0;
			d_w           <= 0;
			d_h           <= 0;
			d_color       <= BLACK;
			draw_start    <= 1'b0;
			draw_idx      <= 3'd0;
			cur_idx       <= 2'd0;
			pending_shift <= 1'b0;
			shift_left    <= 8'd0;
			//platform 0 = the one the sprite starts on (66..89), platform 1 = the first target (106..129)
			plat_x[0] <= 66;   plat_w[0] <= 24;
			plat_x[1] <= 106;  plat_w[1] <= 24;
			plat_x[2] <= 0;    plat_w[2] <= 0;
			plat_x[3] <= 0;    plat_w[3] <= 0;
			state         <= S_CLEAR;
		end else begin
			draw_start <= 1'b0;
			case(state) 
				S_CLEAR:
					if (clr_done) begin
						draw_idx <= 3'd0;		//start drawing from platform 0
						state <= S_DRAW;
					end

				//load the drawer with the rectangle for draw_idx, then start it
				S_DRAW: begin
					if (draw_idx < N_PLAT) begin
						if (plat_w[draw_idx] == 8'd0)
							draw_idx <= draw_idx + 1'b1;		//empty slot: skip it
						else begin
							d_x <= plat_x[draw_idx];
							d_y <= PLAT_Y;
							d_w <= plat_w[draw_idx];
							d_h <= PLAT_H;
							d_color <= PLAT_COLOR;
							draw_start <= 1'b1;
							state <= S_DRAW_WAIT;
						end
					end else begin						//draw_idx == IDX_SPRITE
						d_x <= sprite_x;
						d_y <= sprite_y;
						d_w <= SPRITE_W;
						d_h <= SPRITE_H;
						d_color <= BLACK;
						draw_start <= 1'b1;
						state <= S_DRAW_WAIT;
					end
				end

				S_DRAW_WAIT:
					if (done) begin
						if (draw_idx == IDX_SPRITE)
							state <= pending_shift ? S_SHIFT : S_IDLE;	//sprite is always drawn last
						else begin
							draw_idx <= draw_idx + 1'b1;
							state <= S_DRAW;
						end
					end

				S_IDLE:
					if (move_req) state <= S_ERASE;

				//erase the sprite at its old position (white)
				S_ERASE: begin
					d_x <= sprite_x;
					d_y <= sprite_y;
					d_w <= SPRITE_W;
					d_h <= SPRITE_H;
					d_color <= WHITE;
					draw_start <= 1'b1;
					state <= S_ERASE_WAIT;
				end

				//erase finished: did the jump land on a platform?
				S_ERASE_WAIT: if (done) begin
					if (!any_hit) begin
						state <= S_GAMEOVER;			//landed in a gap (or past the last platform)
					end else begin
						sprite_x <= new_x;			//commit the jump
						draw_idx <= IDX_SPRITE;			//redraw just the sprite
						if (hit_idx != cur_idx) begin		//reached a different platform
							cur_idx <= hit_idx;
							pending_shift <= 1'b1;
							shift_left <= new_x - SPRITE_START_X;
						end
						state <= S_DRAW;
					end
				end

				//PLACEHOLDER for the screen shift. For now it does nothing and returns to IDLE.
				//Next step: slide every platform left by shift_left in small steps
				//  (erase the platform band, subtract a few pixels from every plat_x, redraw, wait one frame),
				//  then move the sprite back to SPRITE_START_X, and add the next platform.
				S_SHIFT: begin
					pending_shift <= 1'b0;
					state <= S_IDLE;
				end

				S_GAMEOVER: ;	//stay here until resetn
				default: state <= S_CLEAR;
			endcase
		end
	end
	
	//score counter (BCD): +1 per successful jump to a new platform, cleared on reset
	always @(posedge CLOCK_50) begin
		if (!resetn) begin
			score_tens <= 4'd0;
			score_ones <= 4'd0;
		end else if (score_inc) begin
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
