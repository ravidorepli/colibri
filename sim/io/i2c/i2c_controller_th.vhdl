-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library uvvm_vvc_framework;
  use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_clock_generator;

library bitvis_vip_i2c;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.com_context;
  context vunit_lib.data_types_context;
  use vunit_lib.avalon_stream_pkg.all;
  use vunit_lib.stream_master_pkg.all;
  use vunit_lib.stream_slave_pkg.all;

library colibri;
  context colibri.common;

use work.tb_pkg.all;

entity i2c_controller_th is
end entity i2c_controller_th;

architecture sim of i2c_controller_th is

  signal clk         : std_logic                    := '1';
  signal reset       : std_logic                    := '1';
  signal cmd_data    : std_logic_vector(7 downto 0);
  signal cmd_address : std_logic_vector(6 downto 0) := 7x"3B";
  signal cmd_read    : std_logic;
  signal cmd_valid   : std_logic;
  signal cmd_ready   : std_logic;
  signal cmd_error   : std_logic;

  signal rd_data  : std_logic_vector(7 downto 0);
  signal rd_valid : std_logic;
  signal rd_ready : std_logic;

  signal sda_en : std_logic;
  signal sda_i  : std_logic;
  signal sda_o  : std_logic;
  signal i2c_if : i2c_if_t;

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
      valid => cmd_valid,
      ready => cmd_ready,
      sop   => cmd_read,
      eop   => open,
      data  => cmd_data
    );

  avalon_sink_vc : entity vunit_lib.avalon_sink
    generic map (
      SINK => c_avalon_sink_stream
    )
    port map (
      clk   => clk,
      valid => rd_valid,
      ready => rd_ready,
      sop   => '1',
      eop   => '1',
      data  => rd_data
    );

  i2c_slave_vvc : entity bitvis_vip_i2c.i2c_vvc
    generic map (
      GC_MASTER_MODE  => false,
      GC_I2C_CONFIG   => c_I2C_CONF,
      GC_INSTANCE_IDX => c_I2C_IDX
    )
    port map (
      i2c_vvc_if => i2c_if
    );

  i2c_controller_inst : entity colibri.i2c_controller
    generic map (
      g_CLOCK_PERIOD => c_CLK_PERIOD_40,
      g_I2C_PERIOD   => c_CLK_I2C_PERIOD
    )
    port map (
      clk_i         => clk,
      reset_i       => reset,
      scl_o         => i2c_if.scl,
      sda_i         => sda_i,
      sda_o         => sda_o,
      sda_en_o      => sda_en,
      cmd_data_i    => cmd_data,
      cmd_address_i => cmd_address,
      cmd_valid_i   => cmd_valid,
      cmd_error_o   => cmd_error,
      cmd_ready_o   => cmd_ready,
      cmd_read_i    => cmd_read,
      rd_data_o     => rd_data,
      rd_valid_o    => rd_valid,
      rd_ready_i    => rd_ready
    );

  i2c_if.sda <= sda_o when sda_en = '1' else
                'Z';
  sda_i      <= i2c_if.sda;
  i2c_if.scl <= 'H';
  i2c_if.sda <= 'H';

end architecture sim;
