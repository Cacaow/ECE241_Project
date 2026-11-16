module key_detect (
    input  wire       clk,
	 input  wire		 resetn,
    input  wire [6:0] HEX3,     // older byte, high digit  (HEX3)
    input  wire [6:0] HEX2,     // older byte, low digit   (HEX2)
    input  wire [6:0] HEX1,     // newest byte, high digit (HEX1)
    input  wire [6:0] HEX0,     // newest byte, low digit  (HEX0)
	 
    output reg        space_down,
    output wire       space_pressed,
    output wire       space_released,

    output reg        w_down,
    output wire       w_pressed,
    output wire       w_released,

    output reg        s_down,
    output wire       s_pressed,
    output wire       s_released
	 
);
	
	wire button_held_end;
	assign button_held_end = (HEX3 == ~7'h71) && (HEX2 == ~7'h3F);
	
	assign new_space = (HEX1 == ~7'h5B) && (HEX0 == ~7'h6F);
	assign new_w = (HEX1 == ~7'h06) && (HEX0 == ~7'h5E);  //W key
	assign new_s = (HEX1 == ~7'h06) && (HEX0 == ~7'h7C);	//S key
	//key_down = space_pressed & !button_held_end;
	
	reg press_init;
	reg press_end;
	
	//check for new key press (rising edge)
	reg [27:0]key_prev;
	wire [27:0]cur_key;
	assign cur_key	= {HEX3, HEX2, HEX1, HEX0};
	always @(posedge clk) begin
		key_prev <= cur_key;
		press_init = (cur_key != key_prev) && !button_held_end;
		press_end = (cur_key != key_prev) && button_held_end;
	end
	
	
	
	always @(posedge clk) begin
        if (!resetn) begin
            space_down <= 1'b0;
            w_down     <= 1'b0;
            s_down     <= 1'b0;
        end else begin
            if (press_init && new_space) space_down <= 1'b1;
            if (press_end  && new_space) space_down <= 1'b0;
            if (press_init && new_w)     w_down     <= 1'b1;
            if (press_end  && new_w)     w_down     <= 1'b0;
            if (press_init && new_s)     s_down     <= 1'b1;
            if (press_end  && new_s)     s_down     <= 1'b0;
        end
    end
	
	
	reg space_prev, w_prev, s_prev;
	always @(posedge clk) begin
		space_prev <= space_down;
      w_prev     <= w_down;
      s_prev     <= s_down;
	
	end
	
    assign space_pressed  =  space_down && !space_prev;
    assign space_released = !space_down &&  space_prev;
    assign w_pressed      =  w_down     && !w_prev;
    assign w_released     = !w_down     &&  w_prev;
    assign s_pressed      =  s_down     && !s_prev;
    assign s_released     = !s_down     &&  s_prev;
	
endmodule