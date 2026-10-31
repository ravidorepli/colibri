--==================================================================================================
--! @brief JTAG stream serializer/deserializer
--! @file jtag_serdes.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 15-12-2025 Created
--! @version 0.1
--! @copyright CERN 2025
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;

--==================================================================================================
--! @brief JTAG stream serializer/deserializer
--! @details
--!
--! This component converts a simple jtag interface with additional FSM signals (shift, update)
--! into a streaming duplex interface with configurable data width.
--! The entity has been designed to work with JTAG primitives available from vendors
--! to create a vendor-independent direct interface with user logic.
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity jtag_serdes is
  generic (
    g_DATA_WIDTH  : natural := 8;
    g_REG_FALLING : boolean := false
  );
  port (
    -- clocks
    clk_ser_i   : in    std_logic;
    clk_par_i   : in    std_logic;
    -- jtag FSM states (on clk_ser_i)
    shift_i     : in    std_logic;
    update_i    : in    std_logic;
    --! parallel input stream
    par_data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    par_valid_i : in    std_logic;
    par_ready_o : out   std_logic;
    --! parallel output stream
    par_data_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0);
    par_valid_o : out   std_logic;
    --! serial input
    ser_data_i  : in    std_logic;
    --! serial output
    ser_data_o  : out   std_logic
  );
end entity jtag_serdes;

architecture rtl of jtag_serdes is

  signal sp_data      : std_logic_vector(g_DATA_WIDTH - 1 downto 0);
  signal sp_level     : std_logic;
  signal sp_level_reg : std_logic;

  signal ps_data : std_logic_vector(g_DATA_WIDTH - 1 downto 0);

  signal shreg : std_logic_vector(g_DATA_WIDTH - 1 downto 0) := (others => '0');

  signal upd_level : std_logic := '0';

begin

  -- sticky input to reduce metastability issues
  -- sampled at UPDATE (many clock cycles to stabilize)
  proc_sync_ps : process (clk_par_i) is
  begin

    if rising_edge(clk_par_i) then
      if (par_valid_i and par_ready_o) then
        ps_data <= par_data_i;
      end if;
    end if;

  end process proc_sync_ps;

  -- jtag shifting register
  proc_shreg : process (clk_ser_i) is
  begin

    if rising_edge(clk_ser_i) then
      if (shift_i) then
        shreg <= ser_data_i & shreg(g_DATA_WIDTH - 1 downto 1);
      elsif (not update_i) then -- capture
        shreg <= ps_data;
      end if;
    end if;

  end process proc_shreg;

  -- generate TDO sampling
  gen_falling : if g_REG_FALLING generate
    ser_data_o <= shreg(0) when falling_edge(clk_ser_i);
  else generate
    ser_data_o <= shreg(0);
  end generate gen_falling;

  -- update output logic
  upd_level <= not upd_level when rising_edge(update_i);
  sp_data   <= shreg;

  -- synchronize with fast clock
  sync_level_inst : entity colibri.synchro
    generic map (
      g_DATA_LENGTH => 1
    )
    port map (
      clk_i     => clk_par_i,
      reset_i   => '0',
      data_i(0) => upd_level,
      data_o(0) => sp_level
    );

  -- register on fast clock
  proc_out_data : process (clk_par_i) is
  begin

    if rising_edge(clk_par_i) then
      par_valid_o  <= '0';
      sp_level_reg <= sp_level;
      if (sp_level_reg xor sp_level) then
        par_valid_o <= '1';
        par_data_o  <= sp_data;
      end if;
    end if;

  end process proc_out_data;

  -- drive ready back (sample data when shift is completed)
  -- needed to plug a fifo in input
  par_ready_o <= par_valid_o;

end architecture rtl;
