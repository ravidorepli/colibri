--==================================================================================================
--! @brief Synchronizes fast pulses over clock domain boundaries
--!
--!  Pulses from the source clock domain are synchronized to single clock
--!  pulses in the destination domain. This is independent of the relation
--!  the clock frequencies (eg. source clock can be much faster thatn the
--!  destination).
--!
--!  Domain pulses will have 1 CC width independently of the original source
--!  pulse width.
--!
--!  IMPORTANT: There should be at least 2 destination clock cycles of delay
--!  between consecutive pulses in the source domain.
--!
--!  Work inspired from the article "Crossing the abyss: asynchronous signals
--!  in a synchronous world" By Mike Stein, Paradigm Works, available at
--!  https://www.edn.com/crossing-the-abyss-asynchronous-signals-in-a-synchronous-world/
--!
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 01-04-2025 Created
--! @version 0.1
--! @copyright CERN 2025
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
----------------------------------------------------------------------------------------------------

entity synchro_pulse is
  generic (
    --! Number of register stages (must be at least 2)
    g_NUM_STAGES : natural range 2 to natural'high := 2
  );
  port (
    --! Source clock
    src_clk_i : in    std_logic;
    --! Destination clock
    dst_clk_i : in    std_logic;

    --! Source single cycle pulse
    pulse_i : in    std_logic;
    --! Destination single cycle pulse
    pulse_o : out   std_logic
  );
end entity synchro_pulse;

----------------------------------------------------------------------------------------------------

architecture rtl of synchro_pulse is

  -- Delayed pulse for input rising edge detection
  signal pulse_d       : std_logic := '0';
  signal pulse_edge    : std_logic;
  -- Toggle signal in the source domain
  signal toggle_cmb    : std_logic;
  signal toggle_reg    : std_logic := '0';
  -- Synchronized to the destination
  signal toggle_sync   : std_logic;
  -- Delayed for output edge detection
  signal toggle_sync_d : std_logic := '0';

begin

  ------------------------------------------------------------------------------
  --! Input rising edge detection (to prevent multiple destination pulses)
  ------------------------------------------------------------------------------
  pulse_d    <= pulse_i when rising_edge(src_clk_i);
  pulse_edge <= pulse_i and not pulse_d;

  ------------------------------------------------------------------------------
  --! Toggle circuit in the source domain
  ------------------------------------------------------------------------------
  toggle_cmb <= not toggle_reg when pulse_edge else
                toggle_reg;
  toggle_reg <= toggle_cmb when rising_edge(src_clk_i);

  ------------------------------------------------------------------------------
  --! Synchronization FF chain for the toggle signal
  ------------------------------------------------------------------------------
  synchro_inst : entity colibri.synchro
    generic map (
      g_DATA_LENGTH => 1,
      g_NUM_STAGES  => g_NUM_STAGES
    )
    port map (
      clk_i     => dst_clk_i,
      reset_i   => '0',
      data_i    => (others => toggle_reg),
      data_o(0) => toggle_sync
    );

  ------------------------------------------------------------------------------
  --! Any edge detection generates the destination pulse
  ------------------------------------------------------------------------------
  toggle_sync_d <= toggle_sync when rising_edge(dst_clk_i);
  pulse_o       <= toggle_sync xor toggle_sync_d;

end architecture rtl;

----------------------------------------------------------------------------------------------------
