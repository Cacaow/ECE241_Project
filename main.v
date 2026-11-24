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
	reg        [1:0] prev_idx;				//the platform it just left (deleted after a landing on a new platform)

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

	//main FSM states (4 bits now: S_PAUSE and S_SLIDE are the 9th and 10th states)
	localparam S_DRAW			= 4'd0,	//draw platforms (idx 0..3) and the sprite (idx 4), one rectangle at a time
				  S_DRAW_WAIT	= 4'd1,
				  S_IDLE			= 4'd2,	//wait for a jump
				  S_ERASE		= 4'd3,	//erase the sprite at its old position
				  S_ERASE_WAIT	= 4'd4,	//landing check happens here
				  S_CLEAR		= 4'd5,	//repaint the whole screen white (after every reset)
				  S_GAMEOVER	= 4'd6,	//GameOver module owns the screen until reset
				  S_SHIFT		= 4'd7,	//after landing on a new platform: delete the one it left, start the slide-back
				  S_PAUSE		= 4'd8,	//wait 1 s after a jump, then a short pause between slide steps
				  S_SLIDE		= 4'd9;	//platform erased: move the sprite AND its platform 1 pixel, then redraw
	reg[3:0] state;

	//score (two BCD digits, shown on HEX5/HEX4 by GameOver)
	reg [3:0] score_tens = 4'd0;
	reg [3:0] score_ones = 4'd0;
	reg move_ok;


	//screen rolling: after a jump lands wait 1 second, then slide back to the starting position
	localparam [25:0] WAIT_1S     = 26'd49999999;	//1 second at 50 MHz
	localparam [25:0] SLIDE_DELAY = 26'd499999;		//10 ms between slide steps (the sprite moves 1 pixel per step)
	reg [25:0] wait_count;
	reg landed;		//a jump just landed
	reg sliding;	//sliding back to the starting position
	wire at_home = (sprite_x == SPRITE_START_X) && (sprite_y == SPRITE_START_Y);


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
					angle <= (angle + 3'd7 > MAX_ANGLE) ? MAX_ANGLE : angle + 3'd7;	//clamp: 90 + 7k never lands exactly on 180
				end
			end else if (angle_down && !angle_up) begin
				if (angle > MIN_ANGLE) begin
					angle <= (angle < 3'd7) ? MIN_ANGLE : angle - 3'd7;		//clamp: no wrap-around below 0
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
			move_angle <= 10'd90;

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


	//=====================================================================
	//  landing check: where would the sprite's centre be after the jump?
	//=====================================================================
	wire [9:0] new_x = jump_side ? ({2'b00, sprite_x} - jump_dx) : ({2'b00, sprite_x} + jump_dx);	//left edge after the jump
	wire signed [9:0] nc = $signed(new_x) + SPRITE_HALF;		//centre column (signed to compare with plat_x)

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
	//a successful jump to a DIFFERENT platform scores a point (not while sliding back: jump_dx is stale then)
	wire score_inc = (state == S_ERASE_WAIT) && done && !sliding && any_hit && (hit_idx != cur_idx);


	//white-clear counters (these are also the pixel being written during S_CLEAR)
	reg [7:0] clr_x;
	reg [6:0] clr_y;
	wire clr_done = (clr_x == 8'd159) && (clr_y == 7'd119);

	//who drives the VGA adapter right now
	wire go_active  = (state == S_GAMEOVER);
	wire clr_active = (state == S_CLEAR);

	always @(posedge CLOCK_50) begin
		if (!resetn || !clr_active) begin
			clr_x <= 8'd0;
			clr_y <= 7'd0;
		end else if (!clr_done) begin
			if (clr_x == 8'd159) begin
				clr_x <= 8'd0;
				clr_y <= clr_y + 1'b1;
			end else
				clr_x <= clr_x + 1'b1;
		end
	end

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

	//VGA write-port mux: GameOver > clear > rectangle drawer
	assign scr_x  = go_active ? go_x     : clr_active ? clr_x : spr_x;
	assign scr_y  = go_active ? go_y     : clr_active ? clr_y : spr_y;
	assign colour = go_active ? go_color : clr_active ? WHITE : spr_color;
	assign plot   = go_active ? go_plot  : clr_active ? 1'b1  : spr_plot;


	//=====================================================================
	//  main FSM
	//=====================================================================
	always@(posedge CLOCK_50) begin
		move_ok <= 1'b0;	//one-cycle pulse (set below on a successful move)
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
			prev_idx      <= 2'd0;
			pending_shift <= 1'b0;
			shift_left    <= 8'd0;
			landed        <= 1'b0;
			sliding       <= 1'b0;
			wait_count    <= 26'd0;
			//platform 0 = the one the sprite starts on (68..91, centred under the sprite: its centre column is 80),
			//platform 1 = the first target (106..129)
			plat_x[0] <= 68;   plat_w[0] <= 24;
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
						if (draw_idx == IDX_SPRITE) begin			//sprite is always drawn last
							wait_count <= 26'd0;
							state <= (landed || sliding) ? S_PAUSE : S_IDLE;	//after a jump or a slide step, wait first
						end else begin
							draw_idx <= draw_idx + 1'b1;
							state <= S_DRAW;
						end
					end

				//1 s after a jump, then a short pause between slide steps
				S_PAUSE: begin
					if (wait_count < (sliding ? SLIDE_DELAY : WAIT_1S)) begin
						wait_count <= wait_count + 1'b1;
					end else begin
						landed <= 1'b0;
						if (pending_shift) begin		//landed on a NEW platform: delete the old one first
							state <= S_SHIFT;
						end else if (at_home) begin
							sliding <= 1'b0;
							state <= S_IDLE;
						end else begin
							sliding <= 1'b1;
							state <= S_ERASE;		//erase, move 1 pixel toward the start, draw
						end
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

				//erase finished: slide step, or did the jump land on a platform?
				S_ERASE_WAIT: if (done) begin
					if (sliding) begin
						//sprite is erased: now erase the platform it stands on (it slides with the sprite)
						d_x <= plat_x[cur_idx];
						d_y <= PLAT_Y;
						d_w <= plat_w[cur_idx];
						d_h <= PLAT_H;
						d_color <= WHITE;
						draw_start <= 1'b1;
						state <= S_SLIDE;
					end else if (jump_dy > sprite_y) begin		//would leave the top of the screen
						state <= S_GAMEOVER;
					end else if (jump_side && (jump_dx > sprite_x)) begin	//jump to the left, would leave the left edge
						state <= S_GAMEOVER;
					end else if (!any_hit) begin
						state <= S_GAMEOVER;			//landed in a gap (or past the last platform)
					end else begin
						sprite_x <= new_x[7:0];			//commit the jump
						sprite_y <= sprite_y - jump_dy[6:0];
						move_ok <= 1'b1;
						landed <= 1'b1;				//after the redraw: wait 1 s, then slide back
						draw_idx <= IDX_SPRITE;			//redraw just the sprite
						if (hit_idx != cur_idx) begin		//reached a different platform
							prev_idx <= cur_idx;
							cur_idx <= hit_idx;
							pending_shift <= 1'b1;
							shift_left <= new_x[7:0] - SPRITE_START_X;
						end
						state <= S_DRAW;
					end
				end

				//slide step: move the sprite 1 pixel toward the start (x and y at the same time)
				//and the platform it stands on 1 pixel in x, then redraw everything
				S_SLIDE: if (done) begin
					if (sprite_x < SPRITE_START_X) begin
						sprite_x <= sprite_x + 1'b1;
						plat_x[cur_idx] <= plat_x[cur_idx] + 1'b1;
					end else if (sprite_x > SPRITE_START_X) begin
						sprite_x <= sprite_x - 1'b1;
						plat_x[cur_idx] <= plat_x[cur_idx] - 1'b1;
					end
					if (sprite_y < SPRITE_START_Y) sprite_y <= sprite_y + 1'b1;
					else if (sprite_y > SPRITE_START_Y) sprite_y <= sprite_y - 1'b1;
					draw_idx <= 3'd0;			//redraw the platforms, then the sprite
					state <= S_DRAW;
				end

				//screen shift, part 1: the sprite landed on a new platform, so delete the one it left
				//(white rectangle over it, width 0 = empty slot). Then the slide-back starts.
				//Next step (not done yet): add the next platform to the empty slot.
				S_SHIFT: begin
					d_x <= plat_x[prev_idx];
					d_y <= PLAT_Y;
					d_w <= plat_w[prev_idx];
					d_h <= PLAT_H;
					d_color <= WHITE;
					draw_start <= 1'b1;
					plat_w[prev_idx] <= 8'd0;
					pending_shift <= 1'b0;
					sliding <= 1'b1;
					draw_idx <= IDX_SPRITE;		//S_DRAW_WAIT then goes to S_PAUSE (sliding)
					state <= S_DRAW_WAIT;
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

	assign LEDR = {7'b0, s_down, w_down, space_down};


endmodule

`default_nettype wire