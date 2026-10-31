-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;
  use colibri.aurora_const.all;

--
library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

entity aurora_st_encoder_tb is
  generic (
    RUNNER_CFG : string
  );
end entity aurora_st_encoder_tb;

architecture bench of aurora_st_encoder_tb is

  -- Clock period
  constant SNK_CLK_PERIOD         : time := 5 ns;
  -- Generics
  constant G_N_LANES              : positive := 4;
  constant G_FIFO_WORDS           : positive := 8;
  -- Ports
  signal snk_clk                  : std_logic                                                := '1';
  signal reset                    : std_logic                                                := '1';
  signal snk_sop                  : std_logic;
  signal snk_eop                  : std_logic;
  signal snk_valid                : std_logic;
  signal snk_ready                : std_logic;

  
  signal snk_data                 : std_logic_vector((c_AURORA_DATA_WIDTH) - 1 downto 0);
  signal snk_empty                : unsigned(log2ceil(c_AURORA_DATA_WIDTH / 8) - 1 downto 0) := (others => '0');
  signal src_data                 : slv_array_t(0 to G_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
  signal src_ready                : std_logic_vector(G_N_LANES - 1 downto 0);
  signal src_valid                : std_logic_vector(G_N_LANES - 1 downto 0);
  -- avalon interfaces
  constant SLAVE_STALL_CONFIG     : stall_config_t  := new_stall_config(stall_probability => 0.6, MIN_STALL_CYCLES => 1, MAX_STALL_CYCLES => 8);
  constant c_AVALON_SOURCE_STREAM : avalon_source_t :=
    new_avalon_source(data_length => c_AURORA_DATA_WIDTH, valid_high_probability => 0.6);
  -- streaming read
  constant SLAVE_AXI_STREAM       : axi_stream_slave_t := new_axi_stream_slave(
                                                                               data_length => c_AURORA_ENC_WIDTH,
     STALL_CONFIG                                                                          => SLAVE_STALL_CONFIG
   );
  constant SLAVE_STREAM           : stream_slave_t     := as_stream(SLAVE_AXI_STREAM);

begin

  aurora_st_encoder_inst : entity colibri.aurora_st_encoder
    generic map (
      g_N_LANES    => g_N_LANES,
      g_FIFO_WORDS => g_FIFO_WORDS
    )
    port map (
      clk_i       => snk_clk,
      reset_i     => reset,
      snk_sop_i   => snk_sop,
      snk_eop_i   => snk_eop,
      snk_valid_i => snk_valid,
      snk_ready_o => snk_ready,
      snk_data_i  => snk_data,
      snk_empty_i => snk_empty,
      src_data_o  => src_data,
      src_ready_i => src_ready,
      src_valid_o => src_valid
    );

  --   proc_src : process is
  --   begin

  --   end process proc_src;

  --   proc_snk : process is
  --   begin

  --   end process proc_snk;

  main : process is

    variable v_vec : std_logic_vector(55 downto 0);

  begin

    test_runner_setup(runner, runner_cfg);
    reset <= '0';

    if run("simple") then
      info("simple encoding test");
      info("WARNING!!! - THIS IS NOT A SELF CHECKING TESTBENCH");

      for i in 0 to 10 loop

        for j in 0 to 6 loop
          v_vec(v_vec'left - (j * 8) downto v_vec'length - (j + 1) * 8) := std_logic_vector(to_unsigned(j + i * 16, 8));
        end loop;

        push_avalon_stream(net, c_avalon_source_stream, 8x"aa"&v_vec, '1', '0');
        push_avalon_stream(net, c_avalon_source_stream, 8x"bb"&v_vec, '0', '0');
        push_avalon_stream(net, c_avalon_source_stream, 8x"cc"&v_vec, '0', '0');
        push_avalon_stream(net, c_avalon_source_stream, 8x"dd"&v_vec, '0', '0');
        push_avalon_stream(net, c_avalon_source_stream, 8x"ee"&v_vec, '0', '1');
        wait for 0 ns;
      end loop;

      wait for 10 us;
    end if;

    test_runner_cleanup(runner);

  end process main;

  proc_rdy : process is
  begin

    wait until not reset;

    loop
      src_ready <= (others => '1');
      wait for SNK_CLK_PERIOD*3;
      src_ready <= (others => '0');
      wait for SNK_CLK_PERIOD;
    end loop;

  end process proc_rdy;

  snk_clk <= not snk_clk after SNK_CLK_PERIOD / 2;

  avalon_source_vc : entity vunit_lib.avalon_source
    generic map (
      SOURCE => c_avalon_source_stream
    )
    port map (
      clk   => snk_clk,
      valid => snk_valid,
      ready => snk_ready,
      sop   => snk_sop,
      eop   => snk_eop,
      data  => snk_data
    );

  --   axi_stream_slave_inst : entity vunit_lib.axi_stream_slave
  --     generic map (
  --       SLAVE => slave_axi_stream
  --     )
  --     port map (
  --       aclk     => src_clk,
  --       areset_n => not reset,
  --       tvalid   => src_valid(0),
  --       tready   => src_ready(0),
  --       tdata    => src_data(0)
  --     );

  test_runner_watchdog(runner, 300 us);

end architecture bench;
