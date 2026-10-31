--==================================================================================================
--! @brief Clock Domain Boundary Synchronizer with Handshake
--! @file synchro_handshake.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 01-08-2025 Created
--! @version 0.1
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

--==================================================================================================
--! @brief Clock Domain Boundary Synchronizer with Handshake
--! @details
--!
--! This component allows the synchronization of simple streams interfaces
--! composed of data (std_logic_vector), valid, and ready signals.
--! The component implements the backpressure propagation using a two way handshake mechanism.
--! The roundtrip latency is proportional to the number of synchronizers' stages (g_NUM_STAGES).
--! The minimum propagation latency is 4 clock cycles for the valid, 6 clock cycles for the ready.
--!
--! This component should be used for not frequently changing signals to avoid using cc_fifo.
--! For high throughput performance, a cc_fifo should be used instead.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity synchro_handshake is
  generic (
    --! Data length
    g_DATA_WIDTH : positive;
    --! Number of register stages (must be at least 2)
    g_NUM_STAGES : natural range 2 to natural'high := 2
  );
  port (
    --! clocks
    snk_clk_i   : in    std_logic;
    src_clk_i   : in    std_logic;
    reset_i     : in    std_logic;
    --! Sink interface
    snk_data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    snk_valid_i : in    std_logic;
    snk_ready_o : out   std_logic;
    --! Source interface
    src_data_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    src_valid_o : out   std_logic;
    src_ready_i : in    std_logic
  );
end entity synchro_handshake;

----------------------------------------------------------------------------------------------------

architecture rtl of synchro_handshake is

  -- synced resets
  signal snk_reset       : std_logic;
  signal src_reset       : std_logic;
  -- helper signal
  signal snk_feedback    : std_logic;
  signal snk_feedforward : std_logic;
  signal src_feedforward : std_logic;
  signal int_ready       : std_logic;

  -- registers
  signal src_feedback : std_logic := '0';
  signal feedback_reg : std_logic := '1';
  signal handshake    : std_logic := '0';

  -- cdc data regs
  signal snk_data_reg : snk_data_i'subtype := (others => '0');
  -- needed for attributes
  signal src_data_reg : src_data_o'subtype := (others => '0');

  -- CDC attributes for ALTERA/INTEL
  attribute preserve                       : boolean;
  attribute altera_attribute               : string;
  attribute preserve of snk_data_reg         : signal is true;
  attribute preserve of src_data_reg         : signal is true;
  attribute preserve of src_feedback         : signal is true;
  attribute preserve of feedback_reg         : signal is true;
  attribute altera_attribute of snk_data_reg : signal is
     "-name SYNCHRONIZER_IDENTIFICATION ""FORCED IF ASYNCHRONOUS""";
  attribute altera_attribute of src_data_reg : signal is
     "-name SYNCHRONIZER_IDENTIFICATION ""FORCED IF ASYNCHRONOUS""";
  -- CDC attributes for XILINX/AMD
  attribute async_reg : boolean;
  attribute dont_touch : boolean;
  attribute dont_touch of snk_data_reg : signal is TRUE;
  attribute dont_touch of src_data_reg : signal is TRUE;
  attribute dont_touch of src_feedback : signal is TRUE;
  attribute dont_touch of feedback_reg : signal is TRUE;

begin

  proc_snk : process (snk_clk_i) is
  begin

    if rising_edge(snk_clk_i) then
      if (snk_reset) then
        feedback_reg <= '1';
      else
        if (snk_ready_o and snk_valid_i) then
          snk_data_reg <= snk_data_i;
          -- acknowledge source is ready
          feedback_reg <= snk_feedback;
        end if;
      end if;
    end if;

  end process proc_snk;

  -- ready when transition is seen
  snk_ready_o <= snk_feedback xor feedback_reg;
  -- signal new sink data is captured
  snk_feedforward <= feedback_reg;

  proc_src : process (src_clk_i) is
  begin

    if rising_edge(src_clk_i) then
      if (src_reset) then
        src_feedback <= '0';
        handshake    <= '1';
        src_valid_o  <= '0';
        src_data_reg <= (others => '0');
      else
        -- if new data available and source reg is free
        if (int_ready and not src_valid_o) then
          src_valid_o  <= '1';
          src_data_reg <= snk_data_reg;
          -- signal to sink that data is captured at source
          src_feedback <= not src_feedback;
        end if;
        -- acknowledge a read
        if (src_ready_i and src_valid_o) then
          src_valid_o <= '0';
          handshake   <= not handshake;
        end if;
      end if;
    end if;

  end process proc_src;

  -- drive output
  src_data_o <= src_data_reg;
  -- toggle ready
  int_ready <= src_feedforward xor handshake;
  --! sync feedback signal (i.e. source reg ready) to sink process
  sync_feedback_inst : entity work.synchro
    generic map (
      g_DATA_LENGTH => 1,
      g_INIT_VALUE  => (others => '1'),
      g_NUM_STAGES  => g_NUM_STAGES
    )
    port map (
      clk_i     => snk_clk_i,
      reset_i   => reset_i,
      data_i(0) => src_feedback,
      data_o(0) => snk_feedback
    );

  --! sync feedforward signal (i.e. sink new data available) to source
  sync_feedforward_inst : entity work.synchro
    generic map (
      g_DATA_LENGTH => 1,
      g_INIT_VALUE  => (others => '1'),
      g_NUM_STAGES  => g_NUM_STAGES
    )
    port map (
      clk_i     => src_clk_i,
      reset_i   => reset_i,
      data_i(0) => snk_feedforward,
      data_o(0) => src_feedforward
    );

  -- sync resets
  snk_reset_inst : entity work.synchro_reset

    port map (
      clk_i   => snk_clk_i,
      reset_i => reset_i,
      reset_o => snk_reset
    );

  src_reset_inst : entity work.synchro_reset

    port map (
      clk_i   => src_clk_i,
      reset_i => reset_i,
      reset_o => src_reset
    );

end architecture rtl;

----------------------------------------------------------------------------------------------------
