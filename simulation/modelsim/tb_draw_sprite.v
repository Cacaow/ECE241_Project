
`timescale 1ns/1ps
`default_nettype none

module tb_draw_sprite();

reg clk = 0;
reg resetn = 0;
reg start = 0;

reg [7:0] px = 78;
reg [6:0] py = 56;
reg [8:0] sprite_color = 9'b000_000_000;

wire [7:0] x;
wire [6:0] y;
wire [8:0] color;
wire plot;
wire done;

integer pixel_count = 0;
integer errors = 0;
integer expected_x;
integer expected_y;

// 20 ns clock period
always #10 clk = ~clk;

// DUT
draw_sprite DUT (
    .clk(clk),
    .resetn(resetn),
    .start(start),
    .px(px),
    .py(py),
    .sprite_color(sprite_color),
    .x(x),
    .y(y),
    .color(color),
    .plot(plot),
    .done(done)
);

initial begin
    $display("Starting draw_sprite test...");

    // Reset
    resetn = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    resetn = 1;

    // Give the DUT one cycle to settle
    @(negedge clk);

    // Start drawing
    start = 1;
    @(negedge clk);
    start = 0;

    // Check every pixel as it is drawn
    while (!done) begin
        @(negedge clk);

        if (plot) begin
            expected_x = 78 + (pixel_count % 4);
            expected_y = 56 + (pixel_count / 4);

            if (x !== expected_x || y !== expected_y) begin
                $display("FAIL: Pixel %0d has wrong coordinates: (%0d,%0d)",
                         pixel_count, x, y);
                errors = errors + 1;
            end

            if (color !== sprite_color) begin
                $display("FAIL: Pixel %0d has wrong colour", pixel_count);
                errors = errors + 1;
            end

            pixel_count = pixel_count + 1;
        end
    end

    // Check final results
    if (pixel_count == 32)
        $display("PASS: Exactly 32 pixels were drawn.");
    else begin
        $display("FAIL: Expected 32 pixels, got %0d.", pixel_count);
        errors = errors + 1;
    end

    if (done)
        $display("PASS: done activated when drawing finished.");
    else begin
        $display("FAIL: done did not activate.");
        errors = errors + 1;
    end

    if (errors == 0)
        $display("DRAW_SPRITE TEST PASSED!");
    else
        $display("DRAW_SPRITE TEST FAILED: %0d errors.", errors);

    #20;
    $finish;
end

endmodule
