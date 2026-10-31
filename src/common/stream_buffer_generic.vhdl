--! @file stream_buffer_generic.vhdl
--! @brief Simple stream buffer with generic type
--! @author Alberto Perro
--! @date 30-04-2026 Created
--! @version 0.1
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

--==================================================================================================
--! @brief Simple stream buffer with generic type
--! @details
--! This entity implements stream buffer with generic typing, allowing <<skid>> and <<pipeline>> behaviours.
--! Zero latency (skid) is selected by g_REGISTER_DATAPATH = false, 1 clock latency is selected by
--! g_REGISTER_DATAPATH = true

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity stream_buffer_generic is
  generic (
    type data_t;
    g_REGISTER_DATAPATH : boolean := false
  );
  port (
    reset_i     : in    std_logic;
    clk_i       : in    std_logic;
    --! source
    snk_data_i  : in    data_t;
    snk_valid_i : in    std_logic;
    snk_ready_o : out   std_logic;
    --! destination
    src_data_o  : out   data_t;
    src_ready_i : in    std_logic;
    src_valid_o : out   std_logic
  );
end entity stream_buffer_generic;

architecture rtl of stream_buffer_generic is

  signal snk_ready : std_logic;
  signal skid_data : snk_data_i'subtype;

begin

  gen_buffer_style : if not g_REGISTER_DATAPATH generate
  begin

    proc_skid : process (clk_i) is
    begin

      if rising_edge(clk_i) then
        if (reset_i = '1') then
          -- clear register state
          snk_ready <= '1';
        else
          if (snk_ready = '1') then
            if (src_ready_i = '0' and snk_valid_i = '1') then
              skid_data <= snk_data_i;
              snk_ready <= '0';
            end if;
          else
            if (src_ready_i = '1') then
              snk_ready <= '1';
            end if;
          end if;
        end if;
      end if;

    end process proc_skid;

    src_data_o  <= snk_data_i when snk_ready = '1' else
                   skid_data;
    src_valid_o <= '1' when snk_ready = '0' and reset_i = '0' else
                   (snk_valid_i and not reset_i);

  else generate
    signal reg_valid  : std_logic;
    signal skid_valid : std_logic;
    signal reg_data   : snk_data_i'subtype;

  begin

    proc_pipeline : process (clk_i) is
    begin

      if rising_edge(clk_i) then
        if (reset_i = '1') then
          snk_ready <= '1';
        else
          if (snk_ready = '1') then
            if (reg_valid and not src_ready_i) then
              skid_data  <= snk_data_i;
              skid_valid <= snk_valid_i;
              snk_ready  <= '0';
            else
              reg_data  <= snk_data_i;
              reg_valid <= snk_valid_i;
            end if;
          else
            if (not reg_valid or src_ready_i) then
              reg_data  <= skid_data;
              reg_valid <= skid_valid;
              snk_ready <= '1';
            end if;
          end if;
        end if;
      end if;

    end process proc_pipeline;

    src_data_o  <= reg_data;
    src_valid_o <= reg_valid;

  end generate gen_buffer_style;

  snk_ready_o <= snk_ready;

end architecture rtl;
