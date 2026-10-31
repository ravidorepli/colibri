--==================================================================================================
--! @brief Frequency Counter
--! @file frequency_counter.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 05-01-2025 Created
--! @version 0.1
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

--==================================================================================================
--! @brief Frequency Counter
--! @details
--!
--! This component measures arbitrary clocks against a known frequency clock.
--! The entity returns the frequency in Hz.
--! Sampling frequency can be customized using the g_SAMPLE_FREQ_HZ generic.
--! Note that if g_SAMPLE_FREQ_HZ != 2^n, multipliers could be instantiated by the synthesis tool.
--! Synchronizes
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity frequency_counter is
  generic (
    g_CLK_REF_FREQ_HZ : positive;       --! reference clock frequency in Hz
    g_NUM_CLOCKS      : positive := 1;  --! number of clocks to measure
    g_DATA_WIDTH      : positive := 32; --! output data register width
    g_SAMPLE_FREQ_HZ  : positive := 1   --! sampling frequency in Hz
  );
  port (
    --! known reference clock
    clk_ref_i    : in    std_logic;
    reset_i      : in    std_logic;
    --! arbitrary clocks vector
    clk_meas_i   : in    std_logic_vector(g_NUM_CLOCKS - 1 downto 0);
    --! frequency outputs
    freq_data_o  : out   uns_array_t(0 to g_NUM_CLOCKS - 1)(g_DATA_WIDTH - 1 downto 0);
    freq_valid_o : out   std_logic_vector(g_NUM_CLOCKS - 1 downto 0)
  );
end entity frequency_counter;

architecture rtl of frequency_counter is

  constant c_FREQ_DIV : natural := div_ceil(g_CLK_REF_FREQ_HZ, g_SAMPLE_FREQ_HZ);

  signal capture : std_logic;

  signal freq_data_r  : uns_array_t(0 to g_NUM_CLOCKS - 1)(g_DATA_WIDTH - 1 downto 0);
  signal freq_valid_r : std_logic_vector(g_NUM_CLOCKS - 1 downto 0);

begin

  -- reference clock counter defines sampling rate
  ref_counter_inst : entity work.counter
    generic map (
      g_MODULO => c_FREQ_DIV
    )
    port map (
      clk_i        => clk_ref_i,
      reset_i      => reset_i,
      enable_i     => '1',
      value_o      => open,
      wraparound_o => capture
    );

  gen_arb_counters : for i in 0 to g_NUM_CLOCKS - 1 generate
    signal capture_sync  : std_logic;
    signal freq_valid    : std_logic;
    signal freq_data     : unsigned(g_DATA_WIDTH - 1 downto 0);
    signal freq_data_reg : unsigned(g_DATA_WIDTH - 1 downto 0);
  begin
    -- syncronize sampling pulse
    synchro_capture_inst : entity work.synchro_pulse
      port map (
        src_clk_i => clk_ref_i,
        dst_clk_i => clk_meas_i(i),
        pulse_i   => capture,
        pulse_o   => capture_sync
      );

    -- arbitrary clock frequency counter
    arb_counter_inst : entity work.counter
      generic map (
        g_COUNTER_WIDTH => g_DATA_WIDTH
      )
      port map (
        clk_i        => clk_meas_i(i),
        reset_i      => capture_sync,
        enable_i     => '1',
        value_o      => freq_data,
        wraparound_o => open
      );

    -- sticky output to avoid metastability
    proc_sync_counter : process (clk_meas_i(i)) is
    begin

      if rising_edge(clk_meas_i(i)) then
        freq_valid <= '0';
        if (capture_sync) then
          freq_data_reg <= freq_data;
          freq_valid    <= '1';
        end if;
      end if;

    end process proc_sync_counter;

    -- syncronized pulsed valid
    synchro_valid_inst : entity work.synchro_pulse
      port map (
        src_clk_i => clk_meas_i(i),
        dst_clk_i => clk_ref_i,
        pulse_i   => freq_valid,
        pulse_o   => freq_valid_r(i)
      );

    freq_data_r(i) <= freq_data_reg;

  end generate gen_arb_counters;

  -- multiply and register output signals
  proc_drive_out : process (clk_ref_i) is
  begin

    if rising_edge(clk_ref_i) then
      if (reset_i = '1') then
        freq_data_o  <= (others => (others => '0'));
        freq_valid_o <= (others => '0');
      else

        for i in  0 to g_NUM_CLOCKS - 1 loop
          freq_data_o(i) <= resize(freq_data_r(i) * g_SAMPLE_FREQ_HZ, 32);
        end loop;

        freq_valid_o <= freq_valid_r;
      end if;
    end if;

  end process proc_drive_out;

end architecture rtl;
