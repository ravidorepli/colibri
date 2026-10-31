create_clock -add -name clk_100m -period 10.000 [get_ports { clk_i }];
create_clock -add -name clk_100m -period 10.000 [get_ports { snk_clk_i }];
create_clock -add -name clk2_40m -period 25.000 [get_ports { src_clk_i }];
