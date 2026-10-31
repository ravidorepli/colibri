--! @title Avalon ST Packet De-interleaver
--! @file deinterleaver.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 06-05-2025
--! @version 0.1

--! This entity deinterleaves single stream packets tagged with
--! a sideband identifier `snk_channel_i` into multiple streams.

--! Release log:
--! - 0.1 first release

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

entity deinterleaver is
  generic (
    g_NUM_OUTPUTS : natural;
    g_DATA_WIDTH  : natural
  );
  port (
    clk_i         : in    std_logic;
    reset_i       : in    std_logic;
    --! @virtualbus Avalon-ST @dir in sink
    snk_sop_i     : in    std_logic;                                         --! start of packet
    snk_eop_i     : in    std_logic;                                         --! end of packet
    snk_valid_i   : in    std_logic;                                         --! valid packet
    snk_ready_o   : out   std_logic;                                         --! ready backpressure
    snk_data_i    : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! packet data output
    snk_empty_i   : in    unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0); --! packet empty
    snk_channel_i : in    unsigned(log2ceil(g_NUM_OUTPUTS) - 1 downto 0);    --! input channel
    --! @end
    --! @virtualbus Avalon-ST @dir out source
    src_sop_o     : out   std_logic_vector(g_NUM_OUTPUTS - 1 downto 0);      --! start of packet
    src_eop_o     : out   std_logic_vector(g_NUM_OUTPUTS - 1 downto 0);      --! end of packet
    src_valid_o   : out   std_logic_vector(g_NUM_OUTPUTS - 1 downto 0);      --! packet valid
    src_ready_i   : in    std_logic_vector(g_NUM_OUTPUTS - 1 downto 0);      --! ready to receive
    src_data_o    : out   slv_array_t(g_NUM_OUTPUTS - 1 downto 0)
    (g_DATA_WIDTH - 1 downto 0);                                             --! data output
    src_empty_o   : out   uns_array_t(g_NUM_OUTPUTS - 1 downto 0)
    (log2ceil(g_DATA_WIDTH / 8) - 1 downto 0)                                --! empty output
  --! @end
  );
end entity deinterleaver;

architecture rtl of deinterleaver is

  signal int_sop   : std_logic;
  signal int_eop   : std_logic;
  signal int_valid : std_logic;
  signal int_ready : std_logic;
  signal int_data  : std_logic_vector(g_DATA_WIDTH + log2ceil(g_NUM_OUTPUTS) - 1 downto 0);
  signal int_empty : unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);

begin

  pipeline_buffer_inst : entity colibri.pipeline_buffer
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH + log2ceil(g_NUM_OUTPUTS)
    )
    port map (
      clk_i       => clk_i,
      reset_i     => reset_i,
      snk_data_i  => std_logic_vector(snk_channel_i) & snk_data_i,
      snk_empty_i => snk_empty_i,
      snk_keep_i  => (others => '0'),
      snk_sop_i   => snk_sop_i,
      snk_eop_i   => snk_eop_i,
      snk_valid_i => snk_valid_i,
      snk_ready_o => snk_ready_o,
      src_data_o  => int_data,
      src_empty_o => int_empty,
      src_keep_o  => open,
      src_sop_o   => int_sop,
      src_eop_o   => int_eop,
      src_valid_o => int_valid,
      src_ready_i => int_ready
    );

  proc_main_cmb : process (all) is
  begin

    int_ready <= '0';

    for i in 0 to g_NUM_OUTPUTS - 1 loop

      src_sop_o(i)   <= '0';
      src_eop_o(i)   <= '0';
      src_valid_o(i) <= '0';
      src_data_o(i)  <= (others => '0');
      src_empty_o(i) <= (others => '0');

      if (unsigned(int_data(int_data'left downto g_DATA_WIDTH)) = i) then
        src_sop_o(i)   <= int_sop;
        src_eop_o(i)   <= int_eop;
        src_valid_o(i) <= int_valid;
        src_data_o(i)  <= int_data(g_DATA_WIDTH - 1 downto 0);
        src_empty_o(i) <= int_empty;
        int_ready      <= src_ready_i(i);
      end if;

    end loop;

  end process proc_main_cmb;

end architecture rtl;
