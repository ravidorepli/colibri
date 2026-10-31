--! @title I2C Master Controller module
--! @file i2c_controller.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 20-03-2024
--! @version 0.1

--! This module implements a simple I2C controller.
--! Release log:
--! - 0.1 first release
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;

entity i2c_controller is
  generic (
    g_CLOCK_PERIOD : time := 10 ns;
    g_I2C_PERIOD   : time := 10 us
  );
  port (
    clk_i   : in    std_logic;
    reset_i : in    std_logic;

    --! @virtualbus I2C controller
    scl_o    : out   std_logic;
    -- breakout of the tristate for better compatibility
    sda_i    : in    std_logic;
    sda_o    : out   std_logic;
    sda_en_o : out   std_logic;
    --! @end

    --! @virtualbus AXIS @dir in command/write
    cmd_data_i    : in    std_logic_vector(7 downto 0);
    cmd_address_i : in    std_logic_vector(6 downto 0);
    cmd_valid_i   : in    std_logic;
    cmd_error_o   : out   std_logic;
    cmd_ready_o   : out   std_logic;
    cmd_read_i    : in    std_logic;
    --! @end
    --! @virtualbus AXIS @dir out read
    rd_data_o     : out   std_logic_vector(7 downto 0);
    rd_valid_o    : out   std_logic;
    rd_ready_i    : in    std_logic
  --! @end
  );
end entity i2c_controller;

architecture rtl of i2c_controller is

  --! number of cycles to derive scl clock
  constant c_SCL_CYCLES : integer := integer(g_I2C_PERIOD / g_CLOCK_PERIOD);

  type fsm_t is (S_RESET, S_IDLE, S_START, S_CMD, S_CMD_ACK, S_TX, S_TX_ACK, S_STOP, S_RX, S_RX_ACK);

  type sig_t is record
    state       : fsm_t;
    next_state  : fsm_t;
    scl_en      : std_logic;
    sda         : std_logic;
    sda_en      : std_logic;
    sda_clk_r   : std_logic;
    rw          : std_logic;
    valid       : std_logic;
    nack        : std_logic;
    bit_cnt     : natural;
    addr_rw     : std_logic_vector(7 downto 0);
    addr_rw_reg : std_logic_vector(7 downto 0);
    byte        : std_logic_vector(7 downto 0);
    data_buff   : std_logic_vector(7 downto 0);
  end record sig_t;

  constant c_FSM_RESET : sig_t :=
  (
    state       => S_RESET,
    next_state  => S_IDLE,
    scl_en      => '0',
    sda         => '1',
    sda_en      => '0',
    sda_clk_r   => '0',
    rw          => '0',
    valid       => '0',
    nack        => '0',
    bit_cnt     => 0,
    addr_rw     => (others => '0'),
    addr_rw_reg => (others => '0'),
    byte        => (others => '0'),
    data_buff   => (others => '0')
  );
  signal   rreg        : sig_t := c_FSM_RESET;
  signal   rcmb        : sig_t;

  signal sda_d   : std_logic;
  signal sda_reg : std_logic;

  signal sda_clk          : std_logic;
  signal sda_rising_edge  : std_logic;
  signal sda_falling_edge : std_logic;
  signal scl_clk          : std_logic;

  -- SDC constraints for Altera
  attribute preserve                          : boolean;
  attribute altera_attribute                  : string;
  attribute altera_attribute of sda_d : signal is
       "-name SYNCHRONIZER_IDENTIFICATION ""FORCED IF ASYNCHRONOUS""";
  attribute preserve of sda_d         : signal is true;
  -- SDC constraints for Xilinx
  attribute async_reg                  : string;
  attribute async_reg of sda_d : signal is "TRUE";

begin

  proc_sync_sda : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        sda_d   <= '0';
        sda_reg <= '0';
      else
        sda_d   <= sda_i;
        sda_reg <= sda_d;
      end if;
    end if;

  end process proc_sync_sda;

  -- infer tri-state logic (external pull-up required)

  scl_o <= '0' when rreg.scl_en = '1' and scl_clk = '0' else
           'Z';

  sda_o    <= rreg.sda;
  sda_en_o <= rreg.sda_en;

  -- generate scl and data clocks
  proc_clk_generator : process (clk_i) is

    variable v_count     : integer range 0 to c_SCL_CYCLES - 1;
    variable v_scl_delay : std_logic_vector(c_SCL_CYCLES - 1 downto 0);

  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        v_scl_delay      := (others => '0');
        scl_clk          <= '0';
        sda_clk          <= '0';
        sda_rising_edge  <= '0';
        sda_falling_edge <= '0';
        v_count          := 0;
      else
        scl_clk <= v_scl_delay(0);
        sda_clk <= v_scl_delay(v_scl_delay'length / 4);
        --! drive rising edge pulse
        if (sda_clk = '0' and v_scl_delay(v_scl_delay'length / 4) = '1') then
          sda_rising_edge <= '1';
        else
          sda_rising_edge <= '0';
        end if;
        if (sda_clk = '1' and v_scl_delay(v_scl_delay'length / 4) = '0') then
          sda_falling_edge <= '1';
        else
          sda_falling_edge <= '0';
        end if;
        --! drive scl clock
        if (v_count < c_SCL_CYCLES / 2) then
          v_scl_delay := '1' & v_scl_delay(v_scl_delay'left downto 1);
        else
          v_scl_delay := '0' & v_scl_delay(v_scl_delay'left downto 1);
        end if;
        --! internal counter for clock division
        if (v_count = c_SCL_CYCLES - 1) then
          v_count := 0;
        else
          v_count := v_count + 1;
        end if;
      end if;
    end if;

  end process proc_clk_generator;

  -- main FSM process
  proc_fsm_cmb : process (all) is

    variable v_int : sig_t;

  begin

    v_int       := rreg;
    cmd_ready_o <= '0';

    case rreg.state is

      when S_RESET =>
        v_int.valid  := '0';
        v_int.sda    := '1';
        v_int.sda_en := '0';

        v_int.scl_en := '0';
        v_int.nack   := '0';

        if (sda_falling_edge) then
          v_int.state := S_IDLE;
        end if;

      when S_IDLE =>
        v_int.sda    := '1';
        v_int.sda_en := '0';
        v_int.scl_en := '0';

        if (v_int.valid = '0') then
          if (sda_rising_edge = '1') then
            cmd_ready_o <= '1';

            if (cmd_valid_i = '1') then
              v_int.addr_rw     := cmd_address_i & cmd_read_i;
              v_int.addr_rw_reg := cmd_address_i & cmd_read_i;
              v_int.rw          := cmd_read_i;
              v_int.byte        := cmd_data_i;
              v_int.state       := S_START;
            end if;
          end if;
        end if;

      when S_START =>
        v_int.sda_en := '1';
        v_int.sda    := sda_clk;

        if (sda_rising_edge = '1') then
          v_int.sda     := rreg.addr_rw(v_int.addr_rw'left);
          v_int.addr_rw := rreg.addr_rw(v_int.addr_rw'left - 1 downto 0) & '0';
          v_int.bit_cnt := rreg.bit_cnt + 1;
          v_int.state   := S_CMD;
        end if;

        if (sda_falling_edge = '1') then
          if (rreg.scl_en = '0') then
            v_int.scl_en := '1';
            v_int.nack   := '0';
          end if;
        end if;

      when S_CMD =>

        if (sda_rising_edge = '1') then
          v_int.sda     := rreg.addr_rw(v_int.addr_rw'left);
          v_int.addr_rw := rreg.addr_rw(v_int.addr_rw'left - 1 downto 0) & '0';
          v_int.bit_cnt := rreg.bit_cnt + 1;
          if (v_int.bit_cnt = 9) then
            v_int.bit_cnt := 0;
            v_int.sda     := '1';
            v_int.sda_en  := '0';
            v_int.state   := S_CMD_ACK;
          end if;
        end if;

      when S_CMD_ACK =>

        if (sda_rising_edge = '1') then
          if (rreg.rw = '0') then
            v_int.sda_en  := '1';
            v_int.sda     := rreg.byte(v_int.byte'left);
            v_int.byte    := rreg.byte(v_int.byte'left - 1 downto 0) & '0';
            v_int.bit_cnt := rreg.bit_cnt + 1;
            v_int.state   := S_TX;
          else
            v_int.sda     := '1';
            v_int.sda_en  := '0';
            v_int.bit_cnt := 0;
            v_int.state   := S_RX;
            v_int.byte    := (others => '0');
          end if;
        end if;

        if (sda_falling_edge = '1') then
          if (sda_reg /= '0') then
            v_int.nack := '1';
          end if;
        end if;

      when S_TX =>

        if (sda_rising_edge = '1') then
          v_int.sda     := rreg.byte(v_int.byte'left);
          v_int.byte    := rreg.byte(v_int.byte'left - 1 downto 0) & '0';
          v_int.bit_cnt := rreg.bit_cnt + 1;
          if (v_int.bit_cnt = 9) then
            v_int.bit_cnt := 0;
            v_int.sda     := '1';
            v_int.sda_en  := '0';
            v_int.state   := S_TX_ACK;
          end if;
        end if;

      when S_TX_ACK =>

        if (sda_rising_edge = '1') then
          cmd_ready_o <= '1';
          if (cmd_valid_i = '1') then
            v_int.addr_rw     := cmd_address_i & cmd_read_i;
            v_int.addr_rw_reg := cmd_address_i & cmd_read_i;
            v_int.rw          := cmd_read_i;
            v_int.byte        := cmd_data_i;
            if (v_int.addr_rw_reg = rreg.addr_rw_reg) then
              v_int.sda     := v_int.byte(v_int.byte'left);
              v_int.byte    := v_int.byte(v_int.byte'left - 1 downto 0) & '0';
              v_int.bit_cnt := v_int.bit_cnt + 1;
              v_int.sda_en  := '1';
              v_int.state   := S_TX;
            else
              v_int.state := S_START;
            end if;
          else
            v_int.state := S_STOP;
          end if;
        end if;

        if (sda_falling_edge = '1') then
          if (sda_reg /= '0') then
            v_int.nack := '1';
          end if;
        end if;

      when S_RX =>

        if (sda_rising_edge = '1') then
          v_int.bit_cnt := v_int.bit_cnt + 1;
          if (v_int.bit_cnt = 8) then
            v_int.valid   := '1';
            v_int.bit_cnt := 0;
            v_int.state   := S_RX_ACK;
          else
            v_int.byte := rreg.byte(v_int.byte'left - 1 downto 0) & '0';
          end if;
        end if;

        if (sda_falling_edge = '1') then
          v_int.byte(0) := sda_reg;
          if (rreg.bit_cnt = 7) then
            cmd_ready_o  <= '1';
            v_int.sda    := '1';
            v_int.sda_en := '1';
            if (cmd_valid_i = '1') then
              v_int.addr_rw     := cmd_address_i & cmd_read_i;
              v_int.addr_rw_reg := cmd_address_i & cmd_read_i;
              v_int.rw          := cmd_read_i;
              v_int.data_buff   := cmd_data_i;
              if (v_int.addr_rw_reg = rreg.addr_rw_reg) then
                v_int.sda        := '0';
                v_int.next_state := S_RX;
              else
                v_int.next_state := S_START;
              end if;
            else
              v_int.next_state := S_STOP;
            end if;
          end if;
        end if;

      when S_RX_ACK =>

        if (sda_rising_edge = '1') then
          v_int.sda    := '1';
          v_int.sda_en := '0';
          if (v_int.valid = '0') then
            v_int.state := rreg.next_state;
            v_int.byte  := rreg.data_buff;
          else
            v_int.state := S_STOP;
          end if;
        end if;

      when S_STOP =>
        v_int.sda := not(sda_clk and v_int.sda_clk_r);

        if (sda_rising_edge = '1') then
          v_int.state := S_IDLE;
        end if;

        if (sda_falling_edge = '1') then
          v_int.scl_en := '0';
        end if;

    end case;

    -- consume read
    if (rreg.valid = '1' and rd_ready_i = '1') then
      v_int.valid := '0';
    end if;

    if (reset_i = '1') then
      v_int := c_FSM_RESET;
    end if;

    v_int.sda_clk_r := sda_clk;
    rcmb            <= v_int;

  end process proc_fsm_cmb;

  rd_data_o   <= rreg.byte;
  rd_valid_o  <= rreg.valid;
  cmd_error_o <= rreg.nack;
  rreg        <= rcmb when rising_edge(clk_i);

end architecture rtl;
