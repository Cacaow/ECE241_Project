# ECE241_Project

## PS2:
Keyboard    | Return Value
Up Arrow    |  75
Down Arrow  |  72
Space Bar   |  29

## VGA
vga_adaptor.v               ->   wires VGA modules together
vga_address_translator.v    ->   convert x, y into memory address
vga_controller.v            ->   Colour based on timing and grid size
vga_pll.v                   ->   50MHz clock to 25MHz clock

NOTE: The y-axis is flipped relative to the cartesian plane (0, 0) is at the top left corner of the screen
