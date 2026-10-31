--==================================================================================================
--! @title Stream to Wishbone Master Memory Mapped Interface
--! @file stream_to_wbm.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 17-05-2024
--! @version 0.2
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;

--==================================================================================================
--! @brief Stream to Wishbone Master Memory Mapped Interface
--! @details
--!
--! This entity converts a full duplex stream into a Wishbone.B4 master.
--! The entity takes a 1 byte command and n bits where n is the maximum between g_WB_ADDR_WIDTH
--! and g_WB_DATA_WIDTH.
--!
--! 0x01 command sets the address
--! 0x02 command send a read request
--! 0x03 command send a write request
--! 0x00 is NOP
--!
--! Stream Data Format
--! 39                       0
--!  | CMD[7:0] | DATA[31:0] |
--!
--! The controller sends the data back by setting the CMD to the last CMD + 0x10.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity stream_to_wbm is
  generic (
    --! wishbone address line width
    g_WB_ADDR_WIDTH : natural := 32;
    --! wishbone data lines width
    g_WB_DATA_WIDTH : natural := 32
  );
  port (
    clk_i       : in    std_logic;
    reset_i     : in    std_logic;
    --! @virtualbus stream @dir in interface
    snk_data_i  : in    std_logic_vector(8 + maximum(g_WB_ADDR_WIDTH, g_WB_DATA_WIDTH)  - 1 downto 0);
    snk_valid_i : in    std_logic;
    snk_ready_o : out   std_logic;
    --! @end
    --! @virtualbus stream @dir out interface
    src_data_o  : out   std_logic_vector(8 + maximum(g_WB_ADDR_WIDTH, g_WB_DATA_WIDTH) - 1 downto 0);
    src_valid_o : out   std_logic;
    --! @end
    --! @virtualbus wishbone @dir inout wishbone B4 memory mapped master
    wb_adr_o    : out   unsigned(g_WB_ADDR_WIDTH - 1 downto 0);
    wb_dat_i    : in    std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0);
    wb_dat_o    : out   std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0);
    wb_we_o     : out   std_logic;
    wb_sel_o    : out   std_logic_vector(g_WB_DATA_WIDTH / 8 - 1 downto 0);
    wb_stb_o    : out   std_logic;
    wb_cyc_o    : out   std_logic;
    wb_ack_i    : in    std_logic;
    wb_err_i    : in    std_logic
  --! @end
  );
end entity stream_to_wbm;

architecture rtl of stream_to_wbm is

  constant c_HDR_WIDTH : natural := 8;

  -- stream constants
  constant c_CMD_ADDR  : std_logic_vector(3 downto 0) := x"1"; --!  ADDRESS command
  constant c_CMD_RDATA : std_logic_vector(3 downto 0) := x"2"; --! READ DATA command
  constant c_CMD_WDATA : std_logic_vector(3 downto 0) := x"3"; --! WRITE DATA command
  constant c_CMD_ACK   : std_logic_vector(3 downto 0) := x"1"; --! CMD ACKNOWLEDGED command

  type wb_slim_t is record
    adr  :  unsigned(g_WB_ADDR_WIDTH - 1 downto 0);
    wdat :  std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0);
    we   :  std_logic;
    stb  :  std_logic;
    cyc  :  std_logic;
  end record wb_slim_t;

  constant c_WB_RST : wb_slim_t :=
  (
    adr  => (others => '0'),
    wdat => (others => '0'),
    we   => '0',
    stb  => '0',
    cyc  => '0'
  );

  type cmd_fsm_t is (S_IDLE, S_REQ, S_ACK);

  constant c_DATA_WIDTH : natural := maximum(g_WB_ADDR_WIDTH, g_WB_DATA_WIDTH);

  type cmd_sig_t is record
    state  : cmd_fsm_t;
    wb     : wb_slim_t;
    rdat   : std_logic_vector(c_DATA_WIDTH + c_HDR_WIDTH - 1 downto 0);
    rvalid : std_logic;
  end record cmd_sig_t;

  constant c_CMD_FSM_INIT : cmd_sig_t :=
  (
    state  => S_IDLE,
    wb     => c_WB_RST,
    rvalid => '0',
    rdat   => (others => '0')
  );

  signal rreg : cmd_sig_t := c_CMD_FSM_INIT;
  signal rcmb : cmd_sig_t;

  signal skid_ready : std_logic;
  signal skid_valid : std_logic;
  signal skid_data  : std_logic_vector(c_DATA_WIDTH + c_HDR_WIDTH - 1 downto 0);

  subtype cmd_range_t is natural range c_DATA_WIDTH + c_HDR_WIDTH - 1 downto c_DATA_WIDTH;

  subtype dat_range_t is natural range c_DATA_WIDTH - 1 downto 0;

begin

  skid_buffer_inst : entity work.skid_buffer
    generic map (
      g_DATA_WIDTH => c_DATA_WIDTH + c_HDR_WIDTH
    )
    port map (
      clk_i       => clk_i,
      reset_i     => reset_i,
      snk_data_i  => snk_data_i,
      snk_empty_i => (others => '0'),
      snk_keep_i  => (others => '0'),
      snk_sop_i   => '0',
      snk_eop_i   => '0',
      snk_valid_i => snk_valid_i,
      snk_ready_o => snk_ready_o,
      src_data_o  => skid_data,
      src_empty_o => open,
      src_keep_o  => open,
      src_sop_o   => open,
      src_eop_o   => open,
      src_valid_o => skid_valid,
      src_ready_i => skid_ready
    );

  --! main FSM process
  proc_cmd_fsm : process (all) is

    variable v_int : cmd_sig_t;

  begin

    v_int        := rreg;
    v_int.rvalid := '0';

    case rreg.state is

      when S_IDLE =>
        v_int.wb.stb := '0';
        v_int.wb.cyc := '0';

        if (skid_valid) then
          v_int.rdat := skid_data;

          case skid_data(cmd_range_t) is

            when 4x"0" & c_CMD_ADDR =>
              v_int.wb.adr            := resize(unsigned(skid_data(dat_range_t)), g_WB_ADDR_WIDTH);
              v_int.rdat(cmd_range_t) := c_CMD_ACK & c_CMD_ADDR;
              v_int.rvalid            := '1';
              v_int.state             := S_IDLE;

            when 4x"0" & c_CMD_RDATA =>
              v_int.wb.we := '0';
              v_int.state := S_REQ;

            when 4x"0" & c_CMD_WDATA =>
              v_int.wb.we   := '1';
              v_int.state   := S_REQ;
              v_int.wb.wdat := skid_data(dat_range_t);

            when others =>
              v_int.state := S_IDLE;

          end case;

        end if;

      when S_REQ =>
        v_int.wb.cyc := '1';
        v_int.wb.stb := '1';
        v_int.state  := S_ACK;

      when S_ACK =>
        v_int.wb.stb := '0';

        if (wb_ack_i) then
          v_int.rvalid := '1';
          if (rreg.wb.we = '0') then
            v_int.rdat(cmd_range_t) := c_CMD_ACK & c_CMD_RDATA;
            v_int.rdat(dat_range_t) := wb_dat_i;
          else
            v_int.rdat(cmd_range_t) := c_CMD_ACK & c_CMD_WDATA;
          end if;
          v_int.wb    := c_WB_RST;
          v_int.state := S_IDLE;
        end if;

    end case;

    if (reset_i) then
      v_int := c_CMD_FSM_INIT;
    end if;

    rcmb <= v_int;

  end process proc_cmd_fsm;

  rreg <= rcmb when rising_edge(clk_i);

  wb_adr_o <= rreg.wb.adr;
  wb_dat_o <= rreg.wb.wdat;
  wb_we_o  <= rreg.wb.we;
  wb_sel_o <= (others => '1'); -- not used
  wb_stb_o <= rreg.wb.stb;
  wb_cyc_o <= rreg.wb.cyc;

  src_data_o  <= rreg.rdat;
  src_valid_o <= rreg.rvalid;

  skid_ready <= '1' when rreg.state = S_IDLE else
                '0';

end architecture rtl;
