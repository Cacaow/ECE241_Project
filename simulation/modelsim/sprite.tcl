vlib work
vlog ../../draw_sprite.v
vlog tb_draw_sprite.v
vsim work.tb_draw_sprite
add wave *
run -all