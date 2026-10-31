-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;

library vunit_lib;
  context vunit_lib.vunit_context;

library uvvm_util;
  context uvvm_util.uvvm_util_context;

library bitvis_vip_scoreboard;

----------------------------------------------------------------------------------------------------

entity simple_dpram_be_tb is
  generic (
    RUNNER_CFG : string;

    --! Byte width in bits (AMD supports 8, 9, 16 or 18)
    g_BYTE_WIDTH : positive := 8;
    --! Bytes per data word - RAM width
    g_WORD_BYTES : positive := 8;
    --! Words to store - RAM depth
    g_N_WORDS    : positive := 64
  );
end entity simple_dpram_be_tb;

----------------------------------------------------------------------------------------------------

architecture behavioural of simple_dpram_be_tb is

  --! Clock periods
  constant c_WR_CLK_PERIOD : time := 7 ns;
  constant c_RD_CLK_PERIOD : time := 11 ns;

  --! Data word and address widths in bits
  constant c_DATA_WIDTH : positive := g_WORD_BYTES * g_BYTE_WIDTH;
  constant c_ADDR_WIDTH : positive := log2ceil(g_N_WORDS);

  --! Write port with byte-enable
  signal wrclk  : std_logic;
  signal wren   : std_logic_vector(g_WORD_BYTES - 1 downto 0) := (others => '0');
  signal wraddr : unsigned(c_ADDR_WIDTH - 1 downto 0)         := (others => '0');
  signal wrdata : std_logic_vector(c_DATA_WIDTH - 1 downto 0) := (others => '0');

  --! Read port
  signal rdclk  : std_logic;
  signal rden   : std_logic                           := '0';
  signal rdaddr : unsigned(c_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal rddata : std_logic_vector(c_DATA_WIDTH - 1 downto 0);

  --! Indicator for the input process to start
  signal start_input  : std_logic := '0';
  --! Indicator for the verification process, that input is finished
  signal input_stoped : std_logic := '0';

  ------------------------------------------------------------------------------
  -- Create custom scoreboards - one for address and one for data
  ------------------------------------------------------------------------------

  --! Address scoreboard package
  package addr_sb_pkg is new bitvis_vip_scoreboard.generic_sb_pkg
    generic map (
      T_ELEMENT         => wraddr'subtype,
      ELEMENT_MATCH     => std_match,
      TO_STRING_ELEMENT => to_hstring
    );

  --! Data scoreboard package
  package data_sb_pkg is new bitvis_vip_scoreboard.generic_sb_pkg
    generic map (
      T_ELEMENT         => wrdata'subtype,
      ELEMENT_MATCH     => std_match,
      TO_STRING_ELEMENT => to_hstring
    );

  --! The scoreboard variables
  shared variable v_addr_sb : addr_sb_pkg.t_generic_sb;
  shared variable v_data_sb : data_sb_pkg.t_generic_sb;

--------------------------------------------------------------------------------

begin ----------------------------------------------------------------------------------------------

  -- Generate clocks
  clock_generator(wrclk, c_WR_CLK_PERIOD);
  clock_generator(rdclk, c_RD_CLK_PERIOD);

  ------------------------------------------------------------------------------
  --! Unit under test
  ------------------------------------------------------------------------------
  uut_simple_dpram_be : entity colibri.simple_dpram_be
    generic map (
      g_BYTE_WIDTH => g_BYTE_WIDTH,
      g_WORD_BYTES => g_WORD_BYTES,
      g_N_WORDS    => g_N_WORDS
    )
    port map (
      wrclk_i  => wrclk,
      wren_i   => wren,
      wraddr_i => wraddr,
      wrdata_i => wrdata,
      rdclk_i  => rdclk,
      rden_i   => rden,
      rdaddr_i => rdaddr,
      rddata_o => rddata
    );

  ------------------------------------------------------------------------------
  --! Input generation
  ------------------------------------------------------------------------------
  proc_input : process is

    -- Random address and data bytes for writing
    variable v_rand_addr : wraddr'subtype;
    variable v_rand_byte : std_logic_vector(g_BYTE_WIDTH - 1 downto 0);
    -- Expected data word in RAM after a masked write
    variable v_exp_data : wrdata'subtype;
    -- Iteration index for the writing loop
    variable v_i : natural := 0;
    -- Skip a write when randomly picked address is already in the queue
    variable v_skip : boolean := false;

  begin

    wait until start_input;

    -- Test random RAM writes for many iterations
    while v_i < 2 * g_N_WORDS loop
      -- Pick a random address for the next write
      v_rand_addr := to_unsigned(random(0, g_N_WORDS), c_ADDR_WIDTH);

      v_skip := false;
      -- Skip the writing if previous write to that address is yet to be verified
      if (not v_addr_sb.is_empty(VOID)) then
        if v_addr_sb.exists(v_rand_addr) then
          v_skip := true;
        end if;
      end if;

      if (v_skip) then
        wren <= (others => '0');
        wait_num_rising_edge(wrclk, 1);
      else
        -- Overwrite current value with zeroes
        wren   <= (others => '1');
        wraddr <= v_rand_addr;
        wrdata <= (others => '0');
        wait_num_rising_edge(wrclk, 1);

        -- Generate random bytes and a random byte-enable mask
        for b in wren'range loop
          v_rand_byte                                                := random(g_BYTE_WIDTH);
          wrdata((b + 1) * g_BYTE_WIDTH - 1 downto b * g_BYTE_WIDTH) <= v_rand_byte;
          if random(VOID) then
            wren(b)                                                        <= '1';
            v_exp_data((b + 1) * g_BYTE_WIDTH - 1 downto b * g_BYTE_WIDTH) := v_rand_byte;
          else
            wren(b)                                                        <= '0';
            v_exp_data((b + 1) * g_BYTE_WIDTH - 1 downto b * g_BYTE_WIDTH) := (others => '0');
          end if;
        end loop;

        -- Write initiated - add the address and axpected data to the scoreboards
        wait_num_rising_edge(wrclk, 1);
        v_addr_sb.add_expected(wraddr);
        v_data_sb.add_expected(v_exp_data);
        log(ID_SEQUENCER, "Writing: addr x" & to_hstring(wraddr) &
            ", mask " & to_string(wren) & ", data x" & to_hstring(wrdata));

        v_i := v_i + 1;
      end if;

    end loop; -- Write iteration

    input_stoped <= '1';
    wait;

  end process proc_input;

  ------------------------------------------------------------------------------
  --! VUnit verification process
  ------------------------------------------------------------------------------
  proc_verify : process is
  begin

    -------------------------- VUNIT SETUP --------------------------
    test_runner_setup(runner, RUNNER_CFG);

    -- Initialize the scoreboards, then unblock the writing process
    v_addr_sb.enable(VOID);
    v_data_sb.enable(VOID);
    wait_num_rising_edge(wrclk, 10);
    start_input <= '1';
    wait_num_rising_edge(rdclk, 1);

    -- Verification loop - keep reading while new data is available
    while input_stoped = '0' or (not v_addr_sb.is_empty(VOID)) loop

      if (not v_addr_sb.is_empty(VOID)) then
        rdaddr <= v_addr_sb.peek_expected(VOID);
        gen_pulse(rden, rdclk, 1, "Reading: addr x" & to_hex_string(v_addr_sb.peek_expected(VOID)));
        wait for c_RD_CLK_PERIOD / 10;
        v_addr_sb.delete_expected(rdaddr);
        v_data_sb.check_received(rddata, "Checking data read from RAM");
      else
        wait_num_rising_edge(rdclk, 1);
      end if;

    end loop;

    ------------------------- VUNIT CLEANUP --------------------------
    test_runner_cleanup(runner);

  end process proc_verify;

  test_runner_watchdog(runner, 1 ms);

end architecture behavioural;

----------------------------------------------------------------------------------------------------
