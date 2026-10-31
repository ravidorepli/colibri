-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.types.all;

library vunit_lib;
  context vunit_lib.vunit_context;

----------------------------------------------------------------------------------------------------

entity array_shift_tb is
  generic (
    RUNNER_CFG  : string;
    g_ELEM_SIZE : natural := 16;
    g_ARRAY_LEN : natural := 16
  );
end entity array_shift_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of array_shift_tb is

  signal test_array : slv_array_t(0 to g_ARRAY_LEN - 1)(g_ELEM_SIZE - 1 downto 0);

begin

  ----------------------------------------------------------------------------
  --! Verification process (VUnit)
  ----------------------------------------------------------------------------
  proc_vunit : process is

    variable v_shifted_array : test_array'subtype;

  begin

    ------------ VUNIT SETUP ------------
    test_runner_setup(runner, RUNNER_CFG);

    for i in test_array'range loop
      test_array(i) <= std_logic_vector(to_unsigned(i, g_ELEM_SIZE));
    end loop;

    while test_suite loop

      --------------------------------------------------------------------------
      -- TEST 1: Test left shift
      --------------------------------------------------------------------------
      if run("shift_left") then

        for i in test_array'range loop
          v_shifted_array := shift_left(test_array, i);

          for j in test_array'left to test_array'right - i loop
            check(v_shifted_array(j) = test_array(j + i),
                  "Incorrect left shift by " & to_string(i) & " at element " & to_string(j));
          end loop;

          for j in test_array'right - i + 1 to test_array'right loop
            check(v_shifted_array(j) = std_logic_vector(to_unsigned(0, g_ELEM_SIZE)),
                  "Non-zero new element after left shift by " & to_string(i) & " at element " & to_string(j));
          end loop;

        end loop;

      end if;

      --------------------------------------------------------------------------
      -- TEST 2: Test right shift
      --------------------------------------------------------------------------
      if run("shift_right") then

        for i in test_array'range loop
          v_shifted_array := shift_right(test_array, i);

          for j in test_array'left to test_array'left + i - 1 loop
            check(v_shifted_array(j) = std_logic_vector(to_unsigned(0, g_ELEM_SIZE)),
                  "Non-zero new element after right shift by " & to_string(i) & " at element " & to_string(j));
          end loop;

          for j in test_array'left + i to test_array'right loop
            check(v_shifted_array(j) = test_array(j - i),
                  "Incorrect right shift by " & to_string(i) & " at element " & to_string(j));
          end loop;

        end loop;

      end if;

    end loop;

    ----------- VUNIT CLEANUP -----------
    test_runner_cleanup(runner);

  end process proc_vunit;

  test_runner_watchdog(runner, 10 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
