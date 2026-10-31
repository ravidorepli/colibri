--! @title Pipeline Buffer
--! @file Pipeline_buffer.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 06-03-2024
--! @version 0.1

--! Pipeline buffer (two-stage fifo) to propagate back-pressure and register combinational paths
--! Use this for better performance and full decoupling, use skid buffer if low latency is needed.
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

entity pipeline_buffer is
  generic (
    g_DATA_WIDTH : positive := 32
  );
  port (
    clk_i       : in    std_logic;
    reset_i     : in    std_logic;
    --
    snk_data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    snk_empty_i : in    unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);
    snk_keep_i  : in    std_logic_vector(g_DATA_WIDTH / 8 - 1 downto 0);
    snk_sop_i   : in    std_logic;
    snk_eop_i   : in    std_logic;
    snk_valid_i : in    std_logic;
    snk_ready_o : out   std_logic;
    --
    src_data_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    src_empty_o : out   unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);
    src_keep_o  : out   std_logic_vector(g_DATA_WIDTH / 8 - 1 downto 0);
    src_sop_o   : out   std_logic;
    src_eop_o   : out   std_logic;
    src_valid_o : out   std_logic;
    src_ready_i : in    std_logic
  );
end entity pipeline_buffer;

architecture rtl of pipeline_buffer is

  type interface_t is record
    data  :  std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    empty :  unsigned(log2ceil(g_DATA_WIDTH / 8) - 1 downto 0);
    keep  :  std_logic_vector(g_DATA_WIDTH / 8 - 1 downto 0);
    sop   :  std_logic;
    eop   :  std_logic;
  end record interface_t;

  signal snk_if     : interface_t;
  signal src_if     : interface_t;
  signal reg_if     : interface_t;
  signal skid_if    : interface_t;
  signal reg_valid  : std_logic := '0';
  signal skid_valid : std_logic := '0';
  signal stall      : std_logic := '1';

begin

  proc_skid : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        stall      <= '0';
        reg_valid  <= '0';
        skid_valid <= '0';
      else
        -- normal operation
        if (stall = '0') then
          -- back pressure
          if (src_ready_i = '0' and reg_valid = '1') then
            -- register input
            skid_if    <= snk_if;
            skid_valid <= snk_valid_i;
            stall      <= '1';
          else
            reg_if    <= snk_if;
            reg_valid <= snk_valid_i;
          end if;
        else
          -- move to main reg
          if (src_ready_i = '1' or reg_valid = '0') then
            reg_if    <= skid_if;
            reg_valid <= skid_valid;
            stall     <= '0';
          end if;
        end if;
      end if;
    end if;

  end process proc_skid;

  snk_ready_o <= not stall;

  src_if <= reg_if;

  snk_if.data  <= snk_data_i;
  snk_if.empty <= snk_empty_i;
  snk_if.keep  <= snk_keep_i;
  snk_if.sop   <= snk_sop_i;
  snk_if.eop   <= snk_eop_i;

  src_data_o  <= src_if.data;
  src_empty_o <= src_if.empty;
  src_keep_o  <= src_if.keep;
  src_sop_o   <= src_if.sop;
  src_eop_o   <= src_if.eop;
  src_valid_o <= reg_valid;

end architecture rtl;
