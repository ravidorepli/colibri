--! @title Collection of commonly used polynomials
--! @file poly_pkg.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 08-12-2023
--! @version 0.1
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

package poly is

  -- common CRC polynomials
  constant c_CRC_1        : std_logic_vector(0 downto 0)  := "1";
  constant c_CRC_3_GSM    : std_logic_vector(2 downto 0)  := 3x"3";
  constant c_CRC_5_USB    : std_logic_vector(4 downto 0)  := 5x"05";
  constant c_CRC_8        : std_logic_vector(7 downto 0)  := 8x"7";
  constant c_CRC_16_CCITT : std_logic_vector(15 downto 0) := 16x"1021";
  constant c_CRC_32       : std_logic_vector(31 downto 0) := 32x"04c11db7";
  -- common scrambling polynomials
  constant c_SCR_10GBASE : std_logic_vector(57 downto 0) := 58x"80001";
  -- common PRBS polynomials
  constant c_PRBS_5  : std_logic_vector(5 downto 0)  := 6x"29";
  constant c_PRBS_7  : std_logic_vector(7 downto 0)  := 8x"c1";
  constant c_PRBS_15 : std_logic_vector(15 downto 0) := 16x"c001";
  constant c_PRBS_23 : std_logic_vector(23 downto 0) := 24x"840001";
  constant c_PRBS_31 : std_logic_vector(31 downto 0) := 32x"90000001";

end package poly;
