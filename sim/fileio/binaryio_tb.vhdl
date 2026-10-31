--! @title Binary File I/O Test Bench
--! @file binaryio_tb.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 21-03-2025
--! @version 0.2

--!  Two tests are performed:
--!   1. Basic write and readback of a std_logic_vector
--!   2. Streaming from a file with configurable width and incomplete final word

--! Release log:
--! - 0.2 (mvodnik) added incomplete read functionality
--! - 0.1 first release

-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;
  use colibri.binaryio.all;

library osvvm;
  use osvvm.randompkg.all;

library vunit_lib;
  context vunit_lib.vunit_context;

----------------------------------------------------------------------------------------------------

entity binaryio_tb is
  generic (
    RUNNER_CFG   : string;
    --! Width of the read data stream in bytes
    g_READ_BYTES : natural := 16
  );
end entity binaryio_tb;

----------------------------------------------------------------------------------------------------

architecture bench of binaryio_tb is

  -- Set the number of written bytes so that the last read word is partially empty
  constant c_WRITE_BYTES : natural := 31 * g_READ_BYTES + g_READ_BYTES / 3;
  constant c_READ_WORDS  : natural := div_ceil(c_WRITE_BYTES, g_READ_BYTES);

  -- OSSVM vars
  shared variable v_rv       : RandomPType;
  constant        c_TEST_VEC : std_logic_vector(8 * c_WRITE_BYTES - 1 downto 0) := v_rv.randSlv(8 * c_WRITE_BYTES);

begin

  proc_main : process is

    file     v_file   : binary_file_t;
    variable v_status : file_open_status;

    --! Direct readback of the file (TEST 1)
    variable v_readback : c_TEST_VEC'subtype;

    --! Reading file through a stream (TEST 2)
    variable v_read_stream : std_logic_vector(8 * g_READ_BYTES - 1 downto 0);
    variable v_expected    : std_logic_vector(8 * g_READ_BYTES - 1 downto 0);
    variable v_empty       : natural;

  begin

    ------------------------------- VUNIT SETUP --------------------------------
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      --------------------------------------------------------------------------
      -- TEST 1: Check basic functionality
      --------------------------------------------------------------------------
      if run("test_alive") then
        info("writing to file");
        file_open(v_status, v_file, "testfile.bin", WRITE_MODE);
        write(v_file, c_TEST_VEC);
        wait for 1 ns;
        file_close(v_file);
        info("read back from file");
        file_open(v_status, v_file, "testfile.bin", READ_MODE);
        read(v_file, v_readback);
        wait for 1 ns;
        file_close(v_file);
        check(c_TEST_VEC = v_readback, "Expected read values to match the written ones");
      end if;

      --------------------------------------------------------------------------
      -- TEST 2: Test streaming from a file with incomplete final word
      --------------------------------------------------------------------------
      if run("test_incomplete") then
        info("writing to file");
        file_open(v_status, v_file, "testfile.bin", WRITE_MODE);
        write(v_file, c_TEST_VEC);
        wait for 1 ns;
        file_close(v_file);

        info("stream from file");
        file_open(v_status, v_file, "testfile.bin", READ_MODE);

        -- Stream from file
        for i in 1 to c_READ_WORDS loop

          info("Reading word #" & to_string(i));
          read(v_file, v_read_stream, v_empty);

          -- Check empty bytes
          if (i < c_READ_WORDS) then
            check(v_empty = 0, "Non-zero empty bytes before EoF is reached");
          else
            check(v_empty = g_READ_BYTES - (c_WRITE_BYTES mod g_READ_BYTES),
                  "Incorrect number of empty bytes reported at EoF:" &
                  " Expected: " & to_string(g_READ_BYTES - (c_WRITE_BYTES mod g_READ_BYTES)) &
                  " Received: " & to_string(v_empty));
          end if;

          -- Check read contents
          v_expected
          (v_expected'left downto 8 * v_empty) := c_TEST_VEC(c_TEST_VEC'left - 8 * (i - 1) * g_READ_BYTES downto
                                                             c_TEST_VEC'length -  8 * (i * g_READ_BYTES - v_empty));
          v_expected(8 * v_empty - 1 downto 0) := (others => '0');
          check(v_read_stream = v_expected, "Read values do not match the written ones:" &
                " Expected: "& hex_image(v_expected) &
                " Received: "& hex_image(v_read_stream));
        end loop;

        wait for 1 ns;
        file_close(v_file);
      end if;

    end loop;

    ------------------------------ VUNIT CLEANUP -------------------------------
    test_runner_cleanup(runner);

  end process proc_main;

end architecture bench;

----------------------------------------------------------------------------------------------------
