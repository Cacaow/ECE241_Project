module draw_sprite(    
	 input  wire       clk,
    input  wire       resetn,
    input  wire       start,
    input  wire [7:0] px,
    input  wire [6:0] py,
    output reg  [7:0] x,
    output reg  [6:0] y,
    output reg  [8:0] color,
    output reg        plot,
    output reg        done
	 ); 

	//px, py = top left corner of the sprite
	//x, y = position of the pixel on the screen
	//sprite_color = color of the pixel
	
	parameter W = 4, H = 8;
	parameter sprite_color = 9'b000_000_000;
	reg [3:0] dx, dy;           // offset of the current pixel from the corner
	reg busy;
	
	always @(posedge clk) begin
        if (!resetn) begin
            busy  <= 0;
            plot  <= 0;
            done  <= 0;
            dx    <= 0;
            dy    <= 0;
            x     <= 0;
            y     <= 0;
            color <= 0;
        end else begin
            done <= 0;
            if (start && !busy) begin
                busy <= 1; dx <= 0; dy <= 0;
            end else if (busy) begin
                x <= px + dx;  y <= py + dy;
                color <= sprite_color;  plot <= 1;
                if (dx == W-1) begin
                    dx <= 0;
                    if (dy == H-1) begin busy <= 0; done <= 1; end
                    else dy <= dy + 1;
                end else dx <= dx + 1;
            end else plot <= 0;
        end
    end
endmodule

