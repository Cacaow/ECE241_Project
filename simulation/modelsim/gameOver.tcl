vlog ../../hex.v
vlog ../../GameOver.v
vlog tb_GameOver.v
vsim work.tb_GameOver
add wave *
run -all