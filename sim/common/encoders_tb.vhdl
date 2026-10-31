-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  context colibri.common;

library vunit_lib;
  context vunit_lib.vunit_context;

----------------------------------------------------------------------------------------------------

entity encoders_tb is
  generic (
    RUNNER_CFG : string
  );
end entity encoders_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of encoders_tb is

  signal test_vec : unsigned(7 downto 0);
  signal encoded  : unsigned(log2ceil(test_vec'length) - 1 downto 0);
  signal expected : integer;

begin

  ----------------------------------------------------------------------------
  --! Verification process (VUnit)
  ----------------------------------------------------------------------------
  proc_vunit : process is
  begin

    ------------ VUNIT SETUP ------------
    test_runner_setup(runner, RUNNER_CFG);

    if (run("priority_encoder")) then

      for i in 0 to 2 ** test_vec'length -1 loop
        test_vec <= to_unsigned(i, test_vec'length);

        if (i > 0) then
          expected <= (integer(floor(log2(real(i)))));
        else
          expected <= 0;
        end if;

        wait for 0 ns;
        encoded <= priority_encode(std_logic_vector(test_vec));
        wait for 10 ns;
        check(expected = to_integer(encoded), "Check right priority encoding: "&to_string(encoded)&"=/="&to_string(expected));
      end loop;

    end if;

    ----------- VUNIT CLEANUP -----------
    test_runner_cleanup(runner);

  end process proc_vunit;

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
