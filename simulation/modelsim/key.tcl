vlog ../../key_detect.v
vlog tb_key_detect.v
vsim work.tb_key_detect
add wave *
run -all