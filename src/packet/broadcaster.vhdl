--! @title Avalon ST Packet Broadcaster
--! @file broadcaster.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 07-05-2025
--! @version 0.1

--! This entity broadcasts packet from a single stream to multiple streams.
--! The outputs are fully decoupled using independent pipeline buffers.

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

entity broadcaster is
  generic (
    g_NUM_OUTPUTS : natural;
    g_DATA_WIDTH  : natural
  );
  port (
    clk_i       : in    std_logic;
    reset_i     : in    std_logic;
    --! @virtualbus Avalon-ST @dir in sink
    snk_sop_i   : in    std_logic;                                         --! start of packet
    snk_eop_i   : in    std_logic;                                         --! end of packet
    snk_valid_i : in    std_logic;                                         --! valid packet
    snk_ready_o : out   std_logic;                                         --! ready backpressure
    snk_data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! packet data output
    snk_empty_i : in    unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0); --! packet empty
    --! @end
    --! @virtualbus Avalon-ST @dir out source
    src_sop_o   : out   std_logic_vector(g_NUM_OUTPUTS - 1 downto 0);      --! start of packet
    src_eop_o   : out   std_logic_vector(g_NUM_OUTPUTS - 1 downto 0);      --! end of packet
    src_valid_o : out   std_logic_vector(g_NUM_OUTPUTS - 1 downto 0);      --! packet valid
    src_ready_i : in    std_logic_vector(g_NUM_OUTPUTS - 1 downto 0);      --! ready to receive
    src_data_o  : out   slv_array_t(g_NUM_OUTPUTS - 1 downto 0)
    (g_DATA_WIDTH - 1 downto 0);                                           --! data output
    src_empty_o : out   uns_array_t(g_NUM_OUTPUTS - 1 downto 0)
    (log2ceil(g_DATA_WIDTH / 8) - 1 downto 0)                              --! empty output
  --! @end
  );
end entity broadcaster;

architecture rtl of broadcaster is

  signal int_ready : std_logic_vector(g_NUM_OUTPUTS - 1 downto 0);
  signal int_valid : std_logic;

begin

  snk_ready_o <= and(int_ready);
  int_valid   <= snk_ready_o and snk_valid_i;

  gen_buffers : for i in 0 to g_NUM_OUTPUTS - 1 generate

    pipeline_buffer_inst : entity colibri.pipeline_buffer
      generic map (
        g_DATA_WIDTH => g_DATA_WIDTH
      )
      port map (
        clk_i       => clk_i,
        reset_i     => reset_i,
        snk_data_i  => snk_data_i,
        snk_empty_i => snk_empty_i,
        snk_keep_i  => (others => '0'),
        snk_sop_i   => snk_sop_i,
        snk_eop_i   => snk_eop_i,
        snk_valid_i => int_valid,
        snk_ready_o => int_ready(i),
        src_data_o  => src_data_o(i),
        src_empty_o => src_empty_o(i),
        src_keep_o  => open,
        src_sop_o   => src_sop_o(i),
        src_eop_o   => src_eop_o(i),
        src_valid_o => src_valid_o(i),
        src_ready_i => src_ready_i(i)
      );

  end generate gen_buffers;

end architecture rtl;
