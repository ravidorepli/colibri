--==================================================================================================
--! @brief Power-up reset generator
--!
--!  Generates a fixed duration reset pulse at the start-up. The polarity and
--!  duration of the reset output signal are determined by the generic parameters
--!  `g_POLARITY` and `g_DURATION`.
--!
--!  The external reset input (`reset_ext_i`) can be used to activate the reset
--!  output, which will be asserted (either active high or low) anytime the
--!  `reset_ext_i` is set to high. Reset output will be deasserted `g_DURATION`
--!  clock cycles after `reset_ext_i` is set to low.
--!
--!  The `reset_ext_i` signal is treated as asynchronous, while the generated 'reset_o'
--!  signal is synchronous to the input clock.
--!
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 31-01-2024 Created
--! @version 0.1
--! @copyright CERN 2024
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

----------------------------------------------------------------------------------------------------

entity powerup_reset is
  generic (
    g_POLARITY : std_logic := '1'; --! Output signal polarity ('1' = active high)
    g_DURATION : positive  := 16   --! Output signal duration in clock cycles
  );
  port (
    --! Clock signal
    clk_i : in    std_logic;

    --! External reset signal
    reset_ext_i : in    std_logic;

    --! Reset output signal
    reset_o : out   std_logic
  );
end entity powerup_reset;

----------------------------------------------------------------------------------------------------

architecture rtl of powerup_reset is

  -- A record containing all registered signals

  type reg_t is record
    counter : natural range 0 to g_DURATION;
    reset   : std_logic;
  end record reg_t;

  -- Initial register values
  constant c_REG_TYPE_INIT : reg_t :=
  (
    counter => 0,
    reset   => g_POLARITY
  );

  -- Registered signals
  signal r, rin : reg_t := c_REG_TYPE_INIT;

begin

  ----------------------------------------------------------------------------
  --! Two-process structure (see https://www.gaisler.com/doc/vhdl2proc.pdf)
  ----------------------------------------------------------------------------

  proc_comb : process (r) is

    variable v_reg : reg_t;

  begin

    -- Assign current registered values
    v_reg := r;

    -- Count reset signal active time
    if (r.reset = g_POLARITY) then
      v_reg.counter := r.counter + 1;
    end if;

    -- Deactivate the reset output after the set duration
    if (r.counter >= g_DURATION - 1) then
      v_reg.reset := not g_POLARITY;
    end if;

    -- Drive register inputs
    rin     <= v_reg;
    -- Drive outputs
    reset_o <= r.reset;

  end process proc_comb;

  ----------------------------------------------------------------------------
  proc_seq : process (clk_i, reset_ext_i) is
  begin

    -- Asynchronous reset (active high)
    if (reset_ext_i = '1') then
      r <= c_REG_TYPE_INIT;
    elsif rising_edge(clk_i) then
      r <= rin;
    end if;

  end process proc_seq;

end architecture rtl;

----------------------------------------------------------------------------------------------------
