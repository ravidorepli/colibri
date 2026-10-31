-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  context colibri.common;
  use colibri.aurora_const.all;

--
library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

entity aurora_st_decoder_tb is
  generic (
    RUNNER_CFG : string
  );
end entity aurora_st_decoder_tb;

architecture bench of aurora_st_decoder_tb is

  -- Clock period
  constant SRC_CLK_PERIOD : time := 5 ns;
  -- Generics
  constant G_N_LANES      : positive := 4;
  constant G_FIFO_WORDS   : positive := 8;
  -- Ports
  signal reset            : std_logic                                                := '1';
  signal src_clk          : std_logic                                                := '1';
  signal src_sop          : std_logic;
  signal src_eop          : std_logic;
  signal src_valid        : std_logic;
  signal src_ready        : std_logic;
  signal src_data         : std_logic_vector((c_AURORA_DATA_WIDTH) - 1 downto 0);
  signal src_empty        : unsigned(log2ceil(c_AURORA_DATA_WIDTH / 8) - 1 downto 0) := (others => '0');
  signal snk_data         : slv_array_t(0 to G_N_LANES - 1)(c_AURORA_ENC_WIDTH - 1 downto 0);
  signal snk_ready        : std_logic;
  signal snk_valid        : std_logic;

begin

  aurora_st_decoder_inst : entity colibri.aurora_st_decoder
    generic map (
      g_N_LANES    => g_N_LANES,
      g_FIFO_WORDS => g_FIFO_WORDS
    )
    port map (
      clk_i         => src_clk,
      reset_i       => reset,
      snk_link_up_i => '1',
      snk_data_i    => snk_data,
      snk_valid_i   => snk_valid,
      snk_ready_o   => snk_ready,
      src_sop_o     => src_sop,
      src_eop_o     => src_eop,
      src_valid_o   => src_valid,
      src_error_o   => open,
      src_data_o    => src_data,
      src_empty_o   => src_empty
    );

  --   proc_src : process is
  --   begin

  --   end process proc_src;

  --   proc_snk : process is
  --   begin

  --   end process proc_snk;

  main : process is
  begin

    test_runner_setup(runner, runner_cfg);
    wait for 10 * SRC_CLK_PERIOD;
    reset <= '0';

    if run("simple") then
      info("simple decoding test");
      info("WARNING!!! - THIS IS NOT A SELF CHECKING TESTBENCH");
      wait for  10 us;
    end if;

    test_runner_cleanup(runner);

  end process main;

  proc_input : process is

    variable v_b : boolean;

  begin

    v_b := false;
    wait until not reset;

    loop

      if (snk_ready) then
        v_b := not v_b;
        if (v_b) then
          snk_data(0) <= 66x"1aaaaaaaabbbbbbbb";
          snk_data(1) <= 66x"27800000000000000";
          snk_data(2) <= 66x"1eeeeeeeeffffffff";
          snk_data(3) <= 66x"21e03ccdd11223300";
        else
          snk_data(0) <= 66x"27800000000000000";
          snk_data(1) <= 66x"27800000000000000";
          snk_data(2) <= 66x"27800000000000000";
          snk_data(3) <= 66x"27800000000000000";
        end if;
      end if;

      wait for SRC_CLK_PERIOD;
    end loop;

  end process proc_input;

  src_clk   <= not src_clk after SRC_CLK_PERIOD / 2;
  snk_valid <= '1';
  test_runner_watchdog(runner, 300 us);

end architecture bench;
