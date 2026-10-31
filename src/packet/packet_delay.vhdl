--! @file packet_delay.vhdl
--! @brief Delays Avalon-ST packets by a configurable number of clock cycles
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 23-01-2026 Created
--! @version 0.1
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.types.all;
  use colibri.utils.all;

--==================================================================================================
--! @brief Delays Avalon-ST packets by a configurable number of clock cycles
--! @details
--!
--!  The delay (in terms of clock cycles) is configured via the `delay_i` port.
--!  Delay is counted from the start of packet (SoP) handshake at the input interface
--!  (`snk_sop_i` asserted) to the SoP on the output interface (`src_sop_i` asserted).
--!
--!  In case multiple packets are in flight at the same time, the subsequent packets
--!  might get delayed more, if the output is still busy with a previous packet.
--!  The component can count the delay for up to `g_N_PACKETS` simultaneous packets
--!  in flight. In case the maximum is reached, the input is blocked until
--!  a packet passes on the output releasing a spot.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity packet_delay is
  generic (
    --! Symbol width
    g_SYM_WIDTH   : positive := 8;
    --! Data width in terms of symbols
    g_DATA_SYM    : positive := 4;
    --! Number of simoultaneous packets to handle
    g_N_PACKETS   : positive := 3;
    --! FIFO storage depth in terms of Avalon-ST beats
    g_NUM_BEATS   : positive := 8;
    --! Width of the delay configuration port in bits
    g_DELAY_WIDTH : positive := 4
  );
  port (
    --! Clock and reset
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! Delay value in clock cycles
    delay_i : in    unsigned(g_DELAY_WIDTH - 1 downto 0);

    --! Avalon-ST input interface
    snk_data_i  : in    std_logic_vector(g_DATA_SYM * g_SYM_WIDTH - 1 downto 0);
    snk_empty_i : in    unsigned(maximum(log2ceil(g_DATA_SYM), 1) - 1 downto 0);
    snk_sop_i   : in    std_logic;
    snk_eop_i   : in    std_logic;
    snk_valid_i : in    std_logic;
    snk_ready_o : out   std_logic;

    --! Avalon-ST output interface
    src_data_o  : out   std_logic_vector(g_DATA_SYM * g_SYM_WIDTH - 1 downto 0);
    src_empty_o : out   unsigned(maximum(log2ceil(g_DATA_SYM), 1) - 1 downto 0);
    src_sop_o   : out   std_logic;
    src_eop_o   : out   std_logic;
    src_valid_o : out   std_logic;
    src_ready_i : in    std_logic
  );
end entity packet_delay;

----------------------------------------------------------------------------------------------------

architecture rtl of packet_delay is

  --! A record containing all registered signals
  type reg_t is record
    hold_input   : std_logic;                                  --! Hold the input handshake
    hold_output  : std_logic;                                  --! Hold the output handshake
    cnt_idx      : integer range 0 to g_N_PACKETS - 1;         --! Current counter index
    next_cnt_idx : integer range 0 to g_N_PACKETS - 1;         --! Next counter index
    cnt_reset    : std_logic_vector(g_N_PACKETS - 1 downto 0); --! Delay counter resets
    cnt_enable   : std_logic_vector(g_N_PACKETS - 1 downto 0); --! Delay counter enables
  end record reg_t;

  --! Initial register values
  constant c_REG_TYPE_INIT : reg_t :=
  (
    hold_input   => '0',
    hold_output  => '1',
    cnt_idx      => 0,
    next_cnt_idx => 0,
    cnt_reset    => (others => '0'),
    cnt_enable   => (others => '0')
  );

  --! Registered signals
  signal r, rin : reg_t := c_REG_TYPE_INIT;

  --! Avalon-ST FIFO ready for input
  signal fifo_ready : std_logic;
  --! Avalon-ST FIFO output valid
  signal fifo_valid : std_logic;

  --! Delay counter values
  signal delay_cnt : uns_array_t(0 to g_N_PACKETS - 1)(g_DELAY_WIDTH - 1 downto 0);

begin ----------------------------------------------------------------------------------------------

  ------------------------------------------------------------------------------
  --! Avalon-ST FIFO storage
  ------------------------------------------------------------------------------
  u_avst_fifo : entity work.avst_fifo
    generic map (
      g_SYM_WIDTH    => g_SYM_WIDTH,
      g_DATA_SYM     => g_DATA_SYM,
      g_NUM_BEATS    => g_NUM_BEATS,
      g_ASYNC_CLOCKS => false
    )
    port map (
      snk_clk_i   => clk_i,
      src_clk_i   => clk_i,
      snk_reset_i => reset_i,

      snk_ready_o => fifo_ready,
      snk_valid_i => snk_valid_i and (not r.hold_input),
      snk_sop_i   => snk_sop_i,
      snk_eop_i   => snk_eop_i,
      snk_empty_i => snk_empty_i,
      snk_data_i  => snk_data_i,

      src_ready_i => src_ready_i and (not r.hold_output),
      src_valid_o => fifo_valid,
      src_sop_o   => src_sop_o,
      src_eop_o   => src_eop_o,
      src_empty_o => src_empty_o,
      src_data_o  => src_data_o
    );

  snk_ready_o <= fifo_ready and (not r.hold_input);
  src_valid_o <= fifo_valid and (not r.hold_output);

  ------------------------------------------------------------------------------
  --! Delay counters
  ------------------------------------------------------------------------------
  gen_counters : for i in 0 to g_N_PACKETS - 1 generate

    u_counter : entity work.counter
      generic map (
        g_COUNTER_WIDTH => g_DELAY_WIDTH
      )
      port map (
        clk_i        => clk_i,
        reset_i      => reset_i or r.cnt_reset(i),
        enable_i     => r.cnt_enable(i),
        value_o      => delay_cnt(i),
        wraparound_o => open
      );

  end generate gen_counters;

  ------------------------------------------------------------------------------
  --! Two-process structure (see https://www.gaisler.com/doc/vhdl2proc.pdf)
  ------------------------------------------------------------------------------
  proc_comb : process (all) is

    --! Registered signals
    variable v : reg_t;

  begin --------------------------------------------------------------------------------------------

    -- Assign current registered values
    v := r;

    -- Resets are 1CC pulses
    v.cnt_reset := (others => '0');

    -- Input SoP: Progress next counter
    if (snk_sop_i and snk_valid_i and snk_ready_o) then
      v.cnt_enable(r.next_cnt_idx) := '1';
      if (r.next_cnt_idx = g_N_PACKETS - 1) then
        v.next_cnt_idx := 0;
      else
        v.next_cnt_idx := r.next_cnt_idx + 1;
      end if;
    end if;

    -- Output EoP: Progress current counter
    if (src_eop_o and src_valid_o and src_ready_i) then
      if (r.cnt_idx = g_N_PACKETS - 1) then
        v.cnt_idx := 0;
      else
        v.cnt_idx := r.cnt_idx + 1;
      end if;
      v.hold_output := '1'; -- Hold the output handshake by default
    end if;

    -- Release the output handshake if delay is reached
    if (((r.cnt_enable(v.cnt_idx) = '1' or delay_cnt(v.cnt_idx) > 0)
         and delay_cnt(v.cnt_idx) >= delay_i - 1
       ) or delay_i = 0) then
      v.hold_output           := '0';
      v.cnt_enable(v.cnt_idx) := '0';
      v.cnt_reset(v.cnt_idx)  := '1';
    end if;

    -- Hold the input handshake when all counters are busy
    v.hold_input := bool_to_sl(v.next_cnt_idx = v.cnt_idx) and ((not v.hold_output) or v.cnt_enable(v.cnt_idx));

    -- Prevent overflow on any of the counters
    for i in 0 to g_N_PACKETS - 1 loop

      if (delay_cnt(i) = 2 ** g_DELAY_WIDTH - 2) then
        v.cnt_enable(i) := '0';
      end if;

    end loop;

    -- Synchronous reset
    if (reset_i) then
      v := c_REG_TYPE_INIT;
    end if;

    -- Drive register inputs
    rin <= v;

  end process proc_comb;

  -- Drive sequential logic
  r <= rin when rising_edge(clk_i);

end architecture rtl;

----------------------------------------------------------------------------------------------------
