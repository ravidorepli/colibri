--==================================================================================================
--! @brief JTAG stream serializer/deserializer TB
--! @file jtag_serdes_tb.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 15-12-2025 Created
--! @version 0.1
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.osvvmcontext;

library colibri;
--
library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;

-- SPDX-FileCopyrightText: 2026 CERN
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

entity jtag_serdes_tb is
  generic (
    RUNNER_CFG : string
  );
end entity jtag_serdes_tb;

architecture bench of jtag_serdes_tb is

  shared variable v_rv : randomptype;

  constant c_TEST_SIZE      : positive := 10;
  -- Clock period
  constant c_CLK_SER_PERIOD : time := 100 ns;
  constant c_CLK_PAR_PERIOD : time := 1 ns;
  -- Generics
  constant c_DATA_WIDTH     : natural := 8;
  -- Ports
  signal clk_ser            : std_logic := '1';
  signal clk_par            : std_logic := '1';
  signal reset              : std_logic := '1';

  signal a_data_i  : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal a_valid_i : std_logic;
  signal a_ready_o : std_logic;
  signal a_data_o  : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal a_valid_o : std_logic;

  signal b_data_i  : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal b_valid_i : std_logic;
  signal b_ready_o : std_logic;
  signal b_data_o  : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal b_valid_o : std_logic;

  signal b_data  : std_logic_vector(c_DATA_WIDTH - 1 downto 0);
  signal b_valid : std_logic;

  signal capture : std_logic := '0';
  signal shift   : std_logic := '0';
  signal update  : std_logic := '0';
  signal ab      : std_logic;
  signal ba      : std_logic;

  -- vvcs
  constant A_M_STREAM : axi_stream_master_t := new_axi_stream_master(data_length => c_DATA_WIDTH);
  constant B_M_STREAM : axi_stream_master_t := new_axi_stream_master(data_length => c_DATA_WIDTH);
  constant A_M        : stream_master_t     := as_stream(A_M_STREAM);
  constant B_M        : stream_master_t     := as_stream(B_M_STREAM);
  constant A_S_STREAM : axi_stream_slave_t  := new_axi_stream_slave(data_length => c_DATA_WIDTH);
  constant B_S_STREAM : axi_stream_slave_t  := new_axi_stream_slave(data_length => c_DATA_WIDTH);
  constant A_S        : stream_slave_t      := as_stream(A_S_STREAM);
  constant B_S        : stream_slave_t      := as_stream(B_S_STREAM);
  signal   loopback   : boolean             := false;

begin

  osvvm.TbUtilPkg.CreateClock(clk_ser, c_CLK_SER_PERIOD);
  osvvm.TbUtilPkg.CreateClock(clk_par, c_CLK_PAR_PERIOD);

  jtag_serdes_a_inst : entity colibri.jtag_serdes
    generic map (
      g_DATA_WIDTH => c_DATA_WIDTH
    )
    port map (
      clk_ser_i   => clk_ser and (capture or shift),
      clk_par_i   => clk_par,
      shift_i     => shift,
      update_i    => update,
      par_data_i  => a_data_i,
      par_valid_i => a_valid_i,
      par_ready_o => a_ready_o,
      par_data_o  => a_data_o,
      par_valid_o => a_valid_o,
      ser_data_i  => ba,
      ser_data_o  => ab
    );

  jtag_serdes_b_inst : entity colibri.jtag_serdes
    generic map (
      g_DATA_WIDTH => c_DATA_WIDTH
    )
    port map (
      clk_ser_i   => clk_ser and (capture or shift),
      clk_par_i   => clk_par,
      shift_i     => shift,
      update_i    => update,
      par_data_i  => b_data_i,
      par_valid_i => b_valid_i,
      par_ready_o => b_ready_o,
      par_data_o  => b_data_o,
      par_valid_o => b_valid_o,
      ser_data_i  => ab,
      ser_data_o  => ba
    );

  proc_jtag_fsm : process is
  begin

    update  <= '0';
    shift   <= '0';
    capture <= '0';
    osvvm.TbUtilPkg.WaitForLevel(reset, '0');
    osvvm.TbUtilPkg.WaitForClock(clk_ser, 3);
    capture <= '1';
    osvvm.TbUtilPkg.WaitForClock(clk_par, 1);
    osvvm.TbUtilPkg.WaitForClock(clk_ser, 1);
    capture <= '0';
    shift   <= '1';
    osvvm.TbUtilPkg.WaitForClock(clk_ser, 8);
    shift   <= '0';
    update  <= '1';
    osvvm.TbUtilPkg.WaitForClock(clk_ser, 1);

  end process proc_jtag_fsm;

  main : process is

    variable v_data      : a_data_i'subtype;
    variable v_data_prev : a_data_i'subtype;
    variable v_recv      : a_data_i'subtype;

  begin

    test_runner_setup(runner, RUNNER_CFG);

    if (run("test")) then
      osvvm.TbUtilPkg.WaitForClock(clk_par, 1);
      reset <= '0';

      for i in 0 to c_TEST_SIZE loop
        v_data := v_rv.RandSlv(16, 127, c_DATA_WIDTH);
        wait for 1 ns;
        push_stream(net, A_M, v_data);
        pop_stream(net, B_S, v_recv);
        if (i /= 0) then
          check(v_recv = v_data_prev, "A to B data mismatch R:"&to_hstring(v_recv) & " E:" & to_hstring(v_data));
        else
          info("shift out first word");
        end if;
        v_data_prev := v_data;

      end loop;

      for i in 0 to c_TEST_SIZE loop
        v_data := v_rv.RandSlv(16, 127, c_DATA_WIDTH);
        wait for 1 ns;
        push_stream(net, B_M, v_data);
        pop_stream(net, A_S, v_recv);
        if (i /= 0) then
          check(v_recv = v_data_prev, "B to A data mismatch R:"&to_hstring(v_recv) & " E:" & to_hstring(v_data));
        end if;
        v_data_prev := v_data;
      end loop;

    end if;

    test_runner_cleanup(runner);

  end process main;

  test_runner_watchdog(runner, 10 ms);

  a_s_inst : entity vunit_lib.axi_stream_slave
    generic map (
      SLAVE => A_S_STREAM
    )
    port map (
      aclk     => clk_par,
      areset_n => not reset,
      tready   => open,
      tvalid   => a_valid_o,
      tdata    => a_data_o
    );

  a_m_inst : entity vunit_lib.axi_stream_master
    generic map (
      MASTER => A_M_STREAM
    )
    port map (
      aclk     => clk_par,
      areset_n => not reset,
      tvalid   => a_valid_i,
      tready   => a_ready_o,
      tdata    => a_data_i
    );

  b_s_inst : entity vunit_lib.axi_stream_slave
    generic map (
      SLAVE => B_S_STREAM
    )
    port map (
      aclk     => clk_par,
      areset_n => not reset,
      tready   => open,
      tvalid   => b_valid_o,
      tdata    => b_data_o
    );

  b_m_inst : entity vunit_lib.axi_stream_master
    generic map (
      MASTER => B_M_STREAM
    )
    port map (
      aclk     => clk_par,
      areset_n => not reset,
      tvalid   => b_valid_i,
      tready   => b_ready_o,
      tdata    => b_data_i
    );

end architecture bench;
