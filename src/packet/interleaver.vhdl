--! @title Avalon ST Packet Interleaver
--! @file interleaver.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 30-04-2025
--! @version 0.2

--! This entity interleaves multiple streams into a single stream
--! by adding an sideband identifier `src_channel_o`.
--! The interleaving is arbitrized by first giving priority to the
--! packets already in flight, otherwise using round robin arbiter.

--! Release log:
--! - 0.2 add packet boundary option (`g_INTERLEAVE_WORDS`)
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

entity interleaver is
  generic (
    g_NUM_INPUTS       : natural;
    g_DATA_WIDTH       : natural;
    --! if TRUE (default) words are interleaved to achieve maximum bandwidth,
    --! if FALSE packet boundaries are respected (no reuse of stall cycles)
    g_INTERLEAVE_WORDS : boolean := true
  );
  port (
    clk_i         : in    std_logic;
    reset_i       : in    std_logic;
    --! @virtualbus Avalon-ST @dir in sink
    snk_sop_i     : in    std_logic_vector(g_NUM_INPUTS - 1 downto 0);       --! start of packet
    snk_eop_i     : in    std_logic_vector(g_NUM_INPUTS - 1 downto 0);       --! end of packet
    snk_valid_i   : in    std_logic_vector(g_NUM_INPUTS - 1 downto 0);       --! packet valid
    snk_ready_o   : out   std_logic_vector(g_NUM_INPUTS - 1 downto 0);       --! ready to receive
    snk_data_i    : in    slv_array_t(g_NUM_INPUTS - 1 downto 0)
    (g_DATA_WIDTH - 1 downto 0);                                             --! data input
    snk_empty_i   : in    uns_array_t(g_NUM_INPUTS - 1 downto 0)
    (log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);                               --! empty input
    --! @end
    --! @virtualbus Avalon-ST @dir out source
    src_sop_o     : out   std_logic;                                         --! start of packet
    src_eop_o     : out   std_logic;                                         --! end of packet
    src_valid_o   : out   std_logic;                                         --! valid packet
    src_ready_i   : in    std_logic;                                         --! ready backpressure
    src_data_o    : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0);       --! packet data output
    src_empty_o   : out   unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0); --! packet empty
    src_channel_o : out   unsigned(log2ceil(g_NUM_INPUTS) - 1 downto 0)      --! input channel
  --! @end
  );
end entity interleaver;

architecture rtl of interleaver is

  signal int_sop    : std_logic;
  signal int_eop    : std_logic;
  signal int_valid  : std_logic;
  signal int_ready  : std_logic;
  signal int_data   : std_logic_vector(g_DATA_WIDTH + log2ceil(g_NUM_INPUTS) - 1 downto 0);
  signal piped_data : std_logic_vector(g_DATA_WIDTH + log2ceil(g_NUM_INPUTS) - 1 downto 0);
  signal int_empty  : unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);

  type reg_signals_t is record
    ready    : std_logic_vector(g_NUM_INPUTS - 1 downto 0); -- ready (grant)
    inpacket : std_logic_vector(g_NUM_INPUTS - 1 downto 0); -- packet tracker
    priority : std_logic_vector(g_NUM_INPUTS - 1 downto 0); -- priority
    channel  : natural range 0 to g_NUM_INPUTS;             -- NUM_INPUTS equal NO channel selected
  end record reg_signals_t;

  constant c_NO_CHANNEL : natural := g_NUM_INPUTS;

  constant c_REG_INIT : reg_signals_t :=
  (
    ready    => (others => '0'),
    inpacket => (others => '0'),
    priority => (0 => '1', others => '0'),
    channel  => c_NO_CHANNEL
  );

  signal rreg : reg_signals_t := c_REG_INIT;
  signal rcmb : reg_signals_t;

begin

  rreg <= rcmb when rising_edge(clk_i);

  -- arbiter process with packet and round robin priority
  proc_main_cmb : process (all) is

    variable v_int : reg_signals_t;

    function select_channel (valid : std_logic_vector(g_NUM_INPUTS - 1 downto 0); var : reg_signals_t) return natural is
    begin

      -- prioritize packets in flight
      for i in 0 to g_NUM_INPUTS - 1 loop

        if (valid(i) = '1' and var.inpacket(i) = '1') then
          return i;
        end if;

      end loop;

      -- use priority vector to balance it out
      for i in 0 to g_NUM_INPUTS - 1 loop

        if (valid(i) = '1' and var.priority(i) = '1') then
          return i;
        end if;

      end loop;

      -- else
      for i in 0 to g_NUM_INPUTS - 1 loop

        if (valid(i) = '1') then
          return i;
        end if;

      end loop;

      return c_NO_CHANNEL;

    end function select_channel;

  begin

    v_int := rreg;

    if (g_INTERLEAVE_WORDS) then
      v_int.channel := c_NO_CHANNEL;
    end if;

    v_int.ready := (others => '0');

    -- if output is ready
    if (int_ready) then
      if (g_INTERLEAVE_WORDS) then
        v_int.channel := select_channel(snk_valid_i, rreg);
      else
        -- keep packet boundaries by looking at the packet state
        if (rreg.channel /= c_NO_CHANNEL and rreg.inpacket(rreg.channel) = '1') then
          v_int.channel := rreg.channel;
        else
          v_int.channel := select_channel(snk_valid_i, rreg);
        end if;
      end if;
      -- if channel is selected
      if (v_int.channel /= c_NO_CHANNEL) then
        v_int.ready(v_int.channel) := '1';
      else
        v_int.ready := rreg.priority; -- select the prioritized channel
      end if;

      -- if input is valid and selected
      if (v_int.channel /= c_NO_CHANNEL and snk_valid_i(v_int.channel) = '1') then
        -- update packet state

        if (snk_eop_i(v_int.channel) = '1') then
          v_int.inpacket(v_int.channel) := '0';
          -- rotate priority
          v_int.priority                := std_logic_vector(rotate_left(unsigned(rreg.priority), 1));
        elsif (snk_sop_i(v_int.channel) = '1') then
          v_int.inpacket(v_int.channel) := '1';
        end if;
      end if;
    end if;

    if (reset_i) then
      v_int := c_REG_INIT;
    end if;

    rcmb <= v_int;

  end process proc_main_cmb;

  -- connect arbited ready to imput
  snk_ready_o <= rcmb.ready;

  proc_mux_streams : process (all) is
  begin

    int_sop   <= '0';
    int_eop   <= '0';
    int_valid <= '0';
    int_data  <= (others => '0');
    int_empty <= (others => '0');

    for i in 0 to g_NUM_INPUTS - 1 loop

      if (rcmb.channel = i) then
        int_sop   <= snk_sop_i(i);
        int_eop   <= snk_eop_i(i);
        int_valid <= snk_valid_i(i);
        int_data  <= std_logic_vector(to_unsigned(i, src_channel_o'length)) & snk_data_i(i);
        int_empty <= snk_empty_i(i);
      end if;

    end loop;

  end process proc_mux_streams;

  pipeline_buffer_inst : entity colibri.pipeline_buffer
    generic map (
      g_DATA_WIDTH => g_DATA_WIDTH + log2ceil(g_NUM_INPUTS)
    )
    port map (
      clk_i       => clk_i,
      reset_i     => reset_i,
      snk_data_i  => int_data,
      snk_empty_i => int_empty,
      snk_keep_i  => (others => '0'),
      snk_sop_i   => int_sop,
      snk_eop_i   => int_eop,
      snk_valid_i => int_valid,
      snk_ready_o => int_ready,
      src_data_o  => piped_data,
      src_empty_o => src_empty_o,
      src_keep_o  => open,
      src_sop_o   => src_sop_o,
      src_eop_o   => src_eop_o,
      src_valid_o => src_valid_o,
      src_ready_i => src_ready_i
    );

  src_data_o    <= piped_data(g_DATA_WIDTH - 1 downto 0);
  src_channel_o <= unsigned(piped_data(piped_data'left downto g_DATA_WIDTH));

end architecture rtl;
