-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.com_context;
  context vunit_lib.data_types_context;
  use vunit_lib.avalon_stream_pkg.all;
  use vunit_lib.stream_master_pkg.all;
  use vunit_lib.stream_slave_pkg.all;

library colibri;
use work.tb_pkg.all;

entity uart_th is
end entity uart_th;

architecture sim of uart_th is

  -- Ports
  signal clk      : std_logic := '1';
  signal reset    : std_logic := '1';
  signal tx_data  : std_logic_vector(7 downto 0);
  signal tx_valid : std_logic;
  signal tx_ready : std_logic;
  signal rx_data  : std_logic_vector(7 downto 0);
  signal rx_valid : std_logic;
  signal rx_pin   : std_logic;
  signal tx_pin   : std_logic;

begin

  reset <= '0' after c_CLK_PERIOD_40;

  uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine(func);

  clock_gen : entity bitvis_vip_clock_generator.clock_generator_vvc
    generic
      map (
      GC_CLOCK_PERIOD    => c_CLK_PERIOD_40,
      GC_CLOCK_HIGH_TIME => c_CLK_PERIOD_40 / 2,
      GC_INSTANCE_IDX    => c_CLK_40
    )
    port map (
      clk => clk
    );

  avalon_source_vc : entity vunit_lib.avalon_source
    generic map (
      SOURCE => c_avalon_source_stream
    )
    port map (
      clk   => clk,
      valid => tx_valid,
      ready => tx_ready,
      sop   => open,
      eop   => open,
      data  => tx_data
    );

  avalon_sink_vc : entity vunit_lib.avalon_sink
    generic map (
      SINK => c_avalon_sink_stream
    )
    port map (
      clk   => clk,
      valid => rx_valid,
      ready => open,
      sop   => '1',
      eop   => '1',
      data  => rx_data
    );

  uart_inst : entity colibri.uart
    generic map (
      g_CLOCK_PERIOD => c_CLK_PERIOD_40,
      g_BAUD_RATE    => c_BAUD_RATE
    )
    port map (
      clk_i      => clk,
      reset_i    => reset,
      tx_data_i  => tx_data,
      tx_valid_i => tx_valid,
      tx_ready_o => tx_ready,
      rx_data_o  => rx_data,
      rx_valid_o => rx_valid,
      rx_pin_i   => rx_pin,
      tx_pin_o   => tx_pin
    );

  rx_pin <= tx_pin;

end architecture sim;
