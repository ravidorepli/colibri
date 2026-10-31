--! @brief Aurora 64b/66b Constants Package
--! @file aurora_const.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 16-01-2024
--! @version 0.3
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;
--==================================================================================================
--! @brief Aurora 64b/66b Constants Package
--! @details
--! Constants, types, and generics for the Aurora 64b/66b protocol.
--! changelog:
--! - 0.3 Update to VHDL Style Guide
--! - 0.2 Adding Channel Bonding Feature
--! - 0.1 first release
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================
package aurora_const is

  constant c_AURORA_DATA_WIDTH : positive := 64;
  constant c_AURORA_ENC_WIDTH  : positive := 66;

  -- SYNC HEADERS
  constant c_DATA_SH : std_logic_vector(1 downto 0) := "01";
  constant c_CTRL_SH : std_logic_vector(1 downto 0) := "10";

  -- CONTROL OCTETS
  constant c_IDLE_CB_BLOCK : std_logic_vector(7 downto 0) := 8x"78";
  constant c_SEP_BLOCK     : std_logic_vector(7 downto 0) := 8x"1e";
  constant c_SEP7_BLOCK    : std_logic_vector(7 downto 0) := 8x"e1";
  --! type ranges for slices

  subtype header_range is natural range c_AURORA_ENC_WIDTH - 1 downto c_AURORA_ENC_WIDTH - 2;

  subtype ctrl_block_range is natural range c_AURORA_ENC_WIDTH - 3 downto c_AURORA_ENC_WIDTH - 10;

  subtype valid_block_range is natural range c_AURORA_ENC_WIDTH - 16 downto c_AURORA_ENC_WIDTH - 18;

  -- constant AURORA words
  constant c_CB_CODE        : std_logic_vector(7 downto 0) := 8x"40";
  constant c_IDLE_WORD      :
  std_logic_vector(c_AURORA_ENC_WIDTH - 1 downto 0)        := c_CTRL_SH &
    c_IDLE_CB_BLOCK &
    (c_AURORA_DATA_WIDTH - 1 downto 8 => '0');
  constant c_CB_WORD        :
  std_logic_vector(c_AURORA_ENC_WIDTH - 1 downto 0)        := c_CTRL_SH &
    c_IDLE_CB_BLOCK & c_CB_CODE &
    (c_AURORA_DATA_WIDTH - 1 downto 16 => '0');
  constant c_EMPTY_SEP_WORD :
  std_logic_vector(c_AURORA_ENC_WIDTH - 1 downto 0)        := c_CTRL_SH &
    c_SEP_BLOCK &
    (c_AURORA_DATA_WIDTH - 1 downto 8 => '0');

  -- Multi-lane support

  -- maximum number of idle packet sent before tx ready
  constant c_MAX_SYNC_CNT : positive := 64;
  -- send channel bond frame every N words
  constant c_CH_BOND_CYCLES : positive range 8 to 255 := 64;

end package aurora_const;
