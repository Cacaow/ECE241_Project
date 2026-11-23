module GameOver(	 
	 input  wire       clk,
    input  wire       resetn,
    input  wire       start,
    input  wire [3:0] score_tens,     // BCD digits
    input  wire [3:0] score_ones,
	 
    output reg  [7:0] x,
    output reg  [6:0] y,
    output reg  [8:0] color,
    output reg        plot,
	 
    // active-low 7-seg outputs for HEX5 / HEX4
    output wire [6:0] hex_tens,
    output wire [6:0] hex_ones
	 ); 
	 
	/*
	GAME OVER Screen: Fills the screen with background colour and writes "GAME OVER"
	and blinks the score on HEX4 and HEX5
	
	- Stays in GAME_OVER state until resetn is pressed (KEY[0])
	- Same style as draw_sprite where x/y/color/plot are plugged into VGA adapter
	*/
	
	
	//settings
	localparam [8:0] BG = 9'b111_111_111; //white
	localparam [8:0] TEXT_COLOR = 9'b111_000_000;  //red
   localparam [7:0] X0 = 8; // (160 - 9*16) / 2
   localparam [6:0] Y0 = 52; // (120 - 16) / 2
	
	//FSM	
	localparam S_IDLE = 2'd0, 
				  S_FILL = 2'd1, 
				  S_TEXT = 2'd2, 
				  S_HOLD = 2'd3;
				  
	reg [1:0] state;
				  
	//counters for filling bg:
   reg [7:0] cx; //fills 0 to 159
   reg [6:0] cy; //fills 0 to 119
	
	//counters for text: 
	reg [7:0] tx;  //9 chars * 16 px = 0..143
	reg [4:0] ty; //8 font rows * 2 = 0..15
				  
	
	//character codes for GAMEOVER
	localparam [3:0] C_SP=4'd0, 
						  C_G=4'd1, 
						  C_A=4'd2, 
						  C_M=4'd3, 
						  C_E=4'd4, 
						  C_O=4'd5, 
						  C_V=4'd6, 
						  C_R=4'd7;
	 
	//font ROM
	wire [3:0] idx  = tx[7:4];   // which character in the string: tx/16
   wire [2:0] gcol = tx[3:1];   // font column (0..4 used) since 5 cols per character (divides tx by 2)
   wire [2:0] grow = ty[3:1];   // font row    (0..6 used) since 7 rows per character (divides ty by 2)

	reg [3:0] ch;
	
	always @(*) begin
		 case (idx)               // "GAME OVER"
			4'd0: ch = C_G;
			4'd1: ch = C_A;
			4'd2: ch = C_M;
			4'd3: ch = C_E;
			4'd4: ch = C_SP;
			4'd5: ch = C_O;
			4'd6: ch = C_V;
			4'd7: ch = C_E;
			4'd8: ch = C_R;
			default: ch = C_SP;
	  endcase
	end	
		
		
   reg [4:0] bits;              // one row of the glyph, leftmost pixel = bit 4
	always @(*) begin
       case ({ch, grow})
			{C_G,3'd0}: bits = 5'b01110;
         {C_G,3'd1}: bits = 5'b10001;
         {C_G,3'd2}: bits = 5'b10000;
         {C_G,3'd3}: bits = 5'b10111;
         {C_G,3'd4}: bits = 5'b10001;
         {C_G,3'd5}: bits = 5'b10001;
         {C_G,3'd6}: bits = 5'b01110;

         {C_A,3'd0}: bits = 5'b01110;
         {C_A,3'd1}: bits = 5'b10001;
         {C_A,3'd2}: bits = 5'b10001;
         {C_A,3'd3}: bits = 5'b11111;
         {C_A,3'd4}: bits = 5'b10001;
         {C_A,3'd5}: bits = 5'b10001;
         {C_A,3'd6}: bits = 5'b10001;

         {C_M,3'd0}: bits = 5'b10001;
         {C_M,3'd1}: bits = 5'b11011;
         {C_M,3'd2}: bits = 5'b10101;
         {C_M,3'd3}: bits = 5'b10101;
         {C_M,3'd4}: bits = 5'b10001;
         {C_M,3'd5}: bits = 5'b10001;
         {C_M,3'd6}: bits = 5'b10001;

         {C_E,3'd0}: bits = 5'b11111;
         {C_E,3'd1}: bits = 5'b10000;
         {C_E,3'd2}: bits = 5'b10000;
         {C_E,3'd3}: bits = 5'b11110;
         {C_E,3'd4}: bits = 5'b10000;
         {C_E,3'd5}: bits = 5'b10000;
         {C_E,3'd6}: bits = 5'b11111;

         {C_O,3'd0}: bits = 5'b01110;
         {C_O,3'd1}: bits = 5'b10001;
         {C_O,3'd2}: bits = 5'b10001;
         {C_O,3'd3}: bits = 5'b10001;
         {C_O,3'd4}: bits = 5'b10001;
         {C_O,3'd5}: bits = 5'b10001;
         {C_O,3'd6}: bits = 5'b01110;

         {C_V,3'd0}: bits = 5'b10001;
         {C_V,3'd1}: bits = 5'b10001;
         {C_V,3'd2}: bits = 5'b10001;
         {C_V,3'd3}: bits = 5'b10001;
         {C_V,3'd4}: bits = 5'b10001;
         {C_V,3'd5}: bits = 5'b01010;
         {C_V,3'd6}: bits = 5'b00100;

         {C_R,3'd0}: bits = 5'b11110;
         {C_R,3'd1}: bits = 5'b10001;
         {C_R,3'd2}: bits = 5'b10001;
         {C_R,3'd3}: bits = 5'b11110;
         {C_R,3'd4}: bits = 5'b10100;
         {C_R,3'd5}: bits = 5'b10010;
         {C_R,3'd6}: bits = 5'b10001;

			default:    bits = 5'b00000;   // space, and font row 7
		endcase
	end	
		
		
	reg pixel_on;
	always @(*) begin
		case(gcol)
			3'd0: pixel_on = bits[4];
			3'd1: pixel_on = bits[3];
			3'd2: pixel_on = bits[2];
			3'd3: pixel_on = bits[1];
			3'd4: pixel_on = bits[0];
			default: pixel_on = 1'b0;
		endcase
	end		
		
	//main sequential logic

	always@(posedge clk) begin
	
		plot <= 1'b0;
		
		if(!resetn) begin
			state <= S_IDLE;
			cx <= 0;
			cy <= 0;
			tx <= 0;
			ty <= 0;
		end
		
		else case(state)
		
			S_IDLE: 
				if(start) begin
					cx <= 0;
					cy <= 0;
					tx <= 0;
					ty <= 0;
					state <= S_FILL;
			end
			
			S_FILL: begin
				x <= cx;
				y <= cy;
				color <= BG;
				plot <= 1'b1;
				
				//use two counters to iterate through x and y
				
				if(cx == 8'd159)begin
					cx <= 0;
					if(cy == 7'd119) state <= S_TEXT;
					else cy <= cy +1'b1;
				end
				else cx <= cx + 1'b1;
				
				//x goes from 0 to 159 (160 x 120)
				//y goes from 0 to 119
				
			end
			
			S_TEXT: begin
				x <= X0 + tx;  
				y <= Y0 + ty;  
				color <= TEXT_COLOR;
            plot <= pixel_on;               // only letter pixels get written
				
            if (tx == 8'd143) begin
               tx <= 0;
               if (ty == 5'd15) state <= S_HOLD;
               else ty <= ty + 1'b1;
            end else tx <= tx + 1'b1;
			end
				
			S_HOLD: ; //stay at hold until resetn
		endcase
	end
	
	
	//blink score on HEX4 and HEX5: 1.5s on, 0.5s off
	
	 // FSM states (variable assignment)
    localparam [1:0] B_ON1 = 2'd0,
                     B_ON2  = 2'd1,
                     B_ON3  = 2'd2,
                     B_GAP  = 2'd3;
    
	 reg [1:0] blink_state;
	 reg [24:0] blink_count;
 
    wire tick = (blink_count == 25'd24999999); //ticks every 0.5 sec
	 //for modelsim
	 //wire tick = (blink_count == 25'd4); 
 
    always @(posedge clk) begin
        if (!resetn || tick || state != S_HOLD)
            blink_count <= 25'd0;
        else
            blink_count <= blink_count + 1'b1;
    end
	
	always@(posedge clk) begin
		
        if (!resetn || state != S_HOLD) 
            blink_state <= B_ON1;
        else if(tick)
            blink_state <= blink_state + 1'b1;
   end

	wire show = (state==S_HOLD) && (blink_state != B_GAP);

	wire [6:0] seg_tens, seg_ones;
   hex h_tens (.in(score_tens), .out(seg_tens));
   hex h_ones (.in(score_ones), .out(seg_ones));

   assign hex_tens = show ? seg_tens : 7'b1111111;   // active-low, so all 1s = off
   assign hex_ones = show ? seg_ones : 7'b1111111;
	 
endmodule 