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

entity aurora_tx_tb is
  generic (
    RUNNER_CFG : string
  );
end entity aurora_tx_tb;

architecture bench of aurora_tx_tb is

  -- Clock period
  constant SNK_CLK_PERIOD         : time := 5 ns;
  constant SRC_CLK_PERIOD         : time := 5 ns;
  -- Generics
  constant G_N_LANES              : positive := 4;
  constant G_LANE_WIDTH           : positive := 32;
  -- Ports
  signal snk_clk                  : std_logic                                                := '1';
  signal reset                    : std_logic                                                := '1';
  signal src_clk                  : std_logic                                                := '1';
  signal snk_sop                  : std_logic;
  signal snk_eop                  : std_logic;
  signal snk_valid                : std_logic;
  signal snk_ready                : std_logic;
  signal snk_data                 : std_logic_vector(c_AURORA_DATA_WIDTH - 1 downto 0);
  signal snk_empty                : unsigned(log2ceil(c_AURORA_DATA_WIDTH / 8) - 1 downto 0) := (others => '0');
  signal src_data                 : slv_array_t(0 to g_N_LANES - 1)(G_LANE_WIDTH - 1 downto 0);
  signal src_valid                : std_logic_vector(G_N_LANES - 1 downto 0);
  signal src_ready                : std_logic_vector(G_N_LANES - 1 downto 0)                 := (others => '1');
  -- avalon interfaces
  constant c_AVALON_SOURCE_STREAM : avalon_source_t :=
    new_avalon_source(data_length => c_AURORA_DATA_WIDTH, valid_high_probability => 0.6);

begin

  aurora_tx_inst : entity colibri.aurora_tx
    generic map (
      g_N_LANES    => g_N_LANES,
      g_LANE_WIDTH => g_LANE_WIDTH
    )
    port map (
      snk_clk_i   => snk_clk,
      snk_reset_i => reset,
      src_clk_i   => src_clk,
      snk_sop_i   => snk_sop,
      snk_eop_i   => snk_eop,
      snk_valid_i => snk_valid,
      snk_ready_o => snk_ready,
      snk_data_i  => snk_data,
      snk_empty_i => snk_empty,
      src_data_o  => src_data,
      src_valid_o => src_valid,
      src_ready_i => src_ready
    );

  main : process is
  begin

    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      wait for 5 * SNK_CLK_PERIOD;
      reset <= '0';

      if run("test_alive") then
        info("WARNING!!! - THIS IS NOT A SELF CHECKING TESTBENCH");

        for i in 0 to 10 loop
          push_avalon_stream(net, c_avalon_source_stream, 64x"aabbccdd00112244", '1', '0');
          push_avalon_stream(net, c_avalon_source_stream, 64x"ffbbccdd001122ee", '0', '0');
          push_avalon_stream(net, c_avalon_source_stream, 64x"77bbccdd00112288", '0', '1');
          wait for 0 ns;
        end loop;

        wait for 10 us;
        test_runner_cleanup(runner);
      end if;

    end loop;

  end process main;

  snk_clk <= not snk_clk after SNK_CLK_PERIOD / 2;
  src_clk <= not src_clk after SRC_CLK_PERIOD / 2;

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

end architecture bench;
