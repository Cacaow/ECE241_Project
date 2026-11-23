module draw_sprite(
    input  wire              clk,
    input  wire              resetn,
    input  wire              start,
    input  wire signed [9:0] px,            // left edge. SIGNED so a rectangle can sit partly off the left side of the screen
    input  wire        [6:0] py,            // top edge
    input  wire        [7:0] w,             // width  in pixels (>= 1)
    input  wire        [7:0] h,             // height in pixels (>= 1)
    input  wire        [8:0] sprite_color,  // RRR GGG BBB
    output reg         [7:0] x,             // pixel being written (to the VGA adapter)
    output reg         [6:0] y,
    output reg         [8:0] color,
    output reg               plot,          // high only for pixels that are actually on screen
    output reg               done           // one-cycle pulse after the last pixel
);

    // Draws a w x h filled rectangle with its top-left corner at (px, py), one pixel per clock.
    // Used for everything: the sprite, platforms, erasing (draw in white), even a full-screen clear
    // (x = 0, y = 0, w = 160, h = 120).
    //
    // - The inputs are copied when 'start' is accepted, so main can change px/py/w/h/color
    //   immediately afterwards (e.g. to set up the next rectangle) without disturbing this one.
    // - Pixels outside 0..159 (x) or 0..119 (y) are skipped: plot stays low for them.

    reg signed [9:0] rx;                    // latched copies of the inputs
    reg        [6:0] ry;
    reg        [7:0] rw, rh;
    reg        [8:0] rc;

    reg [7:0] dx, dy;                       // offset of the current pixel from the corner
    reg       busy;

    wire signed [10:0] sx = rx + $signed({3'b000, dx});   // screen x of the current pixel (can be negative)
    wire        [7:0]  sy = ry + dy;                      // screen y of the current pixel
    wire in_range = (sx >= 0) && (sx < 160) && (sy < 120);

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
                busy <= 1;  dx <= 0;  dy <= 0;
                rx <= px;  ry <= py;  rw <= w;  rh <= h;  rc <= sprite_color;
            end else if (busy) begin
                x <= sx[7:0];  y <= sy[6:0];
                color <= rc;
                plot  <= in_range;
                if (dx == rw - 1) begin
                    dx <= 0;
                    if (dy == rh - 1) begin busy <= 0; done <= 1; end
                    else dy <= dy + 1;
                end else dx <= dx + 1;
            end else plot <= 0;
        end
    end
endmodule
