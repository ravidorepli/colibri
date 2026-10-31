--! @title Round-Robin Arbiter
--! @file arbiter.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 09-01-2024
--! @version 0.1

--! This module arbitrates a bus connected to a resource.
--! Inspired by https://github.com/chclau/arbiter_rr
--! Release log:
--! - 0.1 first release
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity arbiter is
  generic (

    --! constraint needed for formal verification
    g_NUM_INPUTS : integer := 4
  );
  port (
    clk_i      : in    std_logic;
    reset_i    : in    std_logic;
    --! Vector holding requests to access the resource
    requests_i : in    std_logic_vector(g_NUM_INPUTS - 1 downto 0);
    --! vector holding grants to the requesters
    grants_o   : out   std_logic_vector(g_NUM_INPUTS - 1 downto 0)
  );
end entity arbiter;

architecture rtl of arbiter is

  signal double_req : unsigned(2 * requests_i'length - 1 downto 0);
  signal double_gnt : unsigned(2 * requests_i'length - 1 downto 0);
  signal priority   : unsigned(requests_i'range);
  signal last_reqs  : requests_i'subtype;
  signal reg_grants : grants_o'subtype;
  signal cmb_grants : grants_o'subtype;

begin

  double_req <= unsigned(requests_i & requests_i);
  -- this guarantees only one bit is set in the double_gnt vector
  double_gnt <= double_req and not (double_req - priority);

  proc_clk_arbiter : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        reg_grants <= (others => '0');
        last_reqs  <= (others => '0');
        priority   <= (0 => '1', others => '0'); -- assign priority to the first req
      else
        last_reqs  <= requests_i;
        reg_grants <= cmb_grants;
        if (or (reg_grants and requests_i) = '0') then
          -- update priority register
          priority <= rotate_left(priority, 1);
        end if;
      end if;
    end if;

  end process proc_clk_arbiter;

  proc_cmb_arbiter : process (all) is
  begin

    cmb_grants <= reg_grants;

    if (or (reg_grants and requests_i) = '0') then
      cmb_grants <= std_logic_vector(double_gnt(requests_i'range))
        or std_logic_vector(double_gnt(double_gnt'left downto double_gnt'length / 2));
    end if;

  end process proc_cmb_arbiter;

  grants_o <= cmb_grants;

end architecture rtl;
