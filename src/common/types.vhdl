--==================================================================================================
--! @brief Custom type definitions
--!
--! @author Mitja Vodnik <mitja.vodnik@cern.ch> (CERN - EP-LBC)
--! @date 31-01-2024 Created
--! @version 0.1
--! @copyright CERN 2024
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;

----------------------------------------------------------------------------------------------------
package types is

  ------------------------------------------------------------------------------
  --! Common enumerated types
  ------------------------------------------------------------------------------
  --! Symbol ordering options for the data bus
  --!  - BIG    : 1st symbol is on HIGH bits
  --!  - LITTLE : 1st symbol is on LOW bits
  type endian_t is (BIG, LITTLE);

  ------------------------------------------------------------------------------
  --! 1D Array types
  ------------------------------------------------------------------------------
  type slv_array_t is array (natural range <>) of std_logic_vector;

  type uns_array_t is array (natural range <>) of unsigned;

  type sig_array_t is array (natural range <>) of signed;

  type int_array_t is array (natural range <>) of integer;

  type nat_array_t is array (natural range <>) of natural;

  type pos_array_t is array (natural range <>) of positive;

  ------------------------------------------------------------------------------
  --! 2D Array types
  ------------------------------------------------------------------------------
  type slv_array_2d_t is array (natural range <>) of slv_array_t;

  type uns_array_2d_t is array (natural range <>) of uns_array_t;

  type sig_array_2d_t is array (natural range <>) of sig_array_t;

  type int_array_2d_t is array (natural range <>) of int_array_t;

  type nat_array_2d_t is array (natural range <>) of nat_array_t;

  type pos_array_2d_t is array (natural range <>) of pos_array_t;

  ------------------------------------------------------------------------------
  --! AXI4-Lite record types and initialization values
  ------------------------------------------------------------------------------

  --! AXI4-Lite Write Master
  type axil_wr_master_t is record
    awaddr  : std_logic_vector(31 downto 0);
    awprot  : std_logic_vector(2 downto 0);
    awvalid : std_logic;
    wdata   : std_logic_vector(31 downto 0);
    wstrb   : std_logic_vector(3 downto 0);
    wvalid  : std_logic;
    bready  : std_logic;
  end record axil_wr_master_t;

  constant c_AXIL_WR_MASTER_INIT : axil_wr_master_t :=
  (
    awaddr  => (others => '0'),
    awprot  => (others => '0'),
    awvalid => '0',
    wdata   => (others => '0'),
    wstrb   => (others => '1'),
    wvalid  => '0',
    bready  => '0'
  );

  type axil_wr_master_array_t is array (natural range <>) of axil_wr_master_t;

  --! AXI4-Lite Write Slave
  type axil_wr_slave_t is record
    awready : std_logic;
    wready  : std_logic;
    bresp   : std_logic_vector(1 downto 0);
    bvalid  : std_logic;
  end record axil_wr_slave_t;

  constant c_AXIL_WR_SLAVE_INIT : axil_wr_slave_t :=
  (
    awready => '0',
    wready  => '0',
    bresp   => (others => '0'),
    bvalid  => '0'
  );

  type axil_wr_slave_array_t is array (natural range <>) of axil_wr_slave_t;

  --! AXI4-Lite Read Master
  type axil_rd_master_t is record
    araddr  : std_logic_vector(31 downto 0);
    arprot  : std_logic_vector(2 downto 0);
    arvalid : std_logic;
    rready  : std_logic;
  end record axil_rd_master_t;

  constant c_AXIL_RD_MASTER_INIT : axil_rd_master_t :=
  (
    araddr  => (others => '0'),
    arprot  => (others => '0'),
    arvalid => '0',
    rready  => '0'
  );

  type axil_rd_master_array_t is array (natural range <>) of axil_rd_master_t;

  --! AXI4-Lite Read Slave
  type axil_rd_slave_t is record
    arready : std_logic;
    rdata   : std_logic_vector(31 downto 0);
    rresp   : std_logic_vector(1 downto 0);
    rvalid  : std_logic;
  end record axil_rd_slave_t;

  constant c_AXIL_RD_SLAVE_INIT : axil_rd_slave_t :=
  (
    arready => '0',
    rdata   => (others => '0'),
    rresp   => (others => '0'),
    rvalid  => '0'
  );

  type axil_rd_slave_array_t is array (natural range <>) of axil_rd_slave_t;

  ------------------------------------------------------------------------------
  --! AXI4-Stream record types and initialization values
  ------------------------------------------------------------------------------

  --! AXI4-Stream Master
  type axis_master_t is record
    tdata  : std_logic_vector;
    tkeep  : std_logic_vector;
    tlast  : std_logic;
    tvalid : std_logic;
  end record axis_master_t;

  type axis_master_array_t is array (natural range <>) of axis_master_t;

  -- note: use of init functions instead of constants for unconstrained types inheritance
  --! initialize axis_master_t
  function axis_master_init (tdata_width : natural) return axis_master_t;

  --! AXI4-Stream Slave
  type axis_slave_t is record
    tready : std_logic;
  end record axis_slave_t;

  constant c_AXIS_SLAVE_INIT : axis_slave_t :=
  (
    tready => '0'
  );

  type axis_slave_array_t is array (natural range <>) of axis_slave_t;

  ------------------------------------------------------------------------------
  --! Avalon Stream record types and initialization values
  ------------------------------------------------------------------------------

  --! Avalon Stream Master
  type avst_master_t is record
    data  : std_logic_vector;
    empty : unsigned;
    sop   : std_logic;
    eop   : std_logic;
    valid : std_logic;
  end record avst_master_t;

  type avst_master_array_t is array (natural range <>) of avst_master_t;

  -- note: use of init functions instead of constants for unconstrained types inheritance
  --! initialize avst_master_t
  function avst_master_init (data_width : natural; symbol_width: positive := 8) return avst_master_t;

  --! Avalon Stream Slave
  type avst_slave_t is record
    ready : std_logic;
  end record avst_slave_t;

  constant c_AVST_SLAVE_INIT : avst_slave_t :=
  (
    ready => '0'
  );

  type avst_slave_array_t is array (natural range <>) of avst_slave_t;

  ------------------------------------------------------------------------------
  -- Array conversion functions
  ------------------------------------------------------------------------------
  --! convert slv_array_t to std_logic_vector
  function slv_array_to_slv (arg : slv_array_t; constant c_elem_size : natural) return std_logic_vector;

  --! convert std_logic_vector to slv_array_t
  function slv_to_slv_array (arg : std_logic_vector; constant c_elem_size : natural) return slv_array_t;

  --! convert uns_array_t to std_logic_vector
  function uns_array_to_slv (arg : uns_array_t; constant c_elem_size : natural) return std_logic_vector;

  --! convert std_logic_vector to uns_array_t
  function slv_to_uns_array (arg : std_logic_vector; constant c_elem_size : natural) return uns_array_t;

  --! convert uns_array_t to int_array_t
  function uns_array_to_int_array (arg : uns_array_t) return int_array_t;

  --! convert int_array_t to uns_array_t
  function int_array_to_uns_array (arg : int_array_t; c_elem_size : natural) return uns_array_t;

  ------------------------------------------------------------------------------
  -- Array shifting functions
  ------------------------------------------------------------------------------
  --! shift array elements N positions to the left
  function shift_left (arg : slv_array_t; constant c_n : natural) return slv_array_t;

  --! shift array elements N positions to the right
  function shift_right (arg : slv_array_t; constant c_n : natural) return slv_array_t;

  ------------------------------------------------------------------------------
  --! standard types conversions
  ------------------------------------------------------------------------------
  --! convert boolean to std_logic
  function bool_to_sl (arg : boolean) return std_logic;

  --! convert std_logic to integer
  function sl_to_int (arg: std_logic) return integer;

  ------------------------------------------------------------------------------
  -- Array summation functions
  ------------------------------------------------------------------------------
  --! Sum over unsigned array
  function sum (arg : uns_array_t) return unsigned;

  --! Sum over signed array
  function sum (arg : sig_array_t) return signed;

  --! Sum over integer array
  function sum (arg : int_array_t) return integer;

end package types;

package body types is ------------------------------------------------------------------------------

  -- record type initialization functions --

  --! initialize axis_master_t
  function axis_master_init (tdata_width: natural) return axis_master_t is
  begin

    -- an aggregate, not a record-constrained subtype (Quartus Lite / Standard reject those)
    return (
      tdata  => (tdata_width - 1 downto 0 => '0'),
      tkeep  => (div_ceil(tdata_width, 8) - 1 downto 0 => '0'),
      tlast  => '0',
      tvalid => '0'
    );

  end function axis_master_init;

  --! initialize avst_master_t
  function avst_master_init (data_width: natural; symbol_width: positive := 8) return avst_master_t is
  begin

    -- an aggregate, not a record-constrained subtype (Quartus Lite / Standard reject those)
    return (
      data  => (data_width - 1 downto 0 => '0'),
      empty => (max_int(log2ceil(data_width / symbol_width), 1) - 1 downto 0 => '0'),
      sop   => '0',
      eop   => '0',
      valid => '0'
    );

  end function avst_master_init;

  --! convert slv_array_t to std_logic_vector
  function slv_array_to_slv (arg : slv_array_t; constant c_elem_size : natural) return std_logic_vector is

    variable v_slv : std_logic_vector((arg'length * c_elem_size) - 1 downto 0);

  begin

    for i in 0 to arg'length - 1 loop
      v_slv(v_slv'left - (i * c_ELEM_SIZE) downto v_slv'length - ((i + 1) * c_ELEM_SIZE)) := arg(i);
    end loop;

    return v_slv;

  end function slv_array_to_slv;

  --! convert std_logic_vector to slv_array_t
  function slv_to_slv_array (arg : std_logic_vector; constant c_elem_size : natural) return slv_array_t is

    constant c_NUM_ELEMS : natural := arg'length / c_elem_size;

    variable v_arr : slv_array_t(0 to c_NUM_ELEMS - 1)(c_elem_size - 1 downto 0);

  begin

    for i in 0 to c_NUM_ELEMS - 1 loop
      v_arr(i) :=arg(arg'left - (i * c_elem_size) downto arg'length - ((i + 1) * c_elem_size));
    end loop;

    return v_arr;

  end function slv_to_slv_array;

  --! convert uns_array_t to std_logic_vector
  function uns_array_to_slv (arg : uns_array_t; constant c_elem_size : natural) return std_logic_vector is

    variable v_slv : std_logic_vector((arg'length * c_elem_size) - 1 downto 0);

  begin

    -- arg(arg'low)'length, not arg'element'length: Quartus Lite / Standard have no 'element
    assert arg'length = 0 or c_elem_size /= arg(arg'low)'length
      report "Warning: Mismatch between element size and array element size (it will be resized to c_ELEM_SIZE)"
      severity WARNING;

    for i in 0 to arg'length - 1 loop
      v_slv(v_slv'left - (i * c_ELEM_SIZE) downto v_slv'length - ((i + 1) * c_ELEM_SIZE)) :=
        std_logic_vector(resize(arg(i), c_elem_size));
    end loop;

    return v_slv;

  end function uns_array_to_slv;

  --! convert std_logic_vector to uns_array_t
  function slv_to_uns_array (arg : std_logic_vector; constant c_elem_size : natural) return uns_array_t is

    constant c_NUM_ELEMS : natural := arg'length / c_elem_size;

    variable v_arr : uns_array_t(0 to c_NUM_ELEMS - 1)(c_elem_size - 1 downto 0);

  begin

    for i in 0 to c_NUM_ELEMS - 1 loop
      v_arr(i) := unsigned(arg(arg'left - (i * c_elem_size) downto arg'length - ((i + 1) * c_elem_size)));
    end loop;

    return v_arr;

  end function slv_to_uns_array;

  --! convert uns_array_t to int_array_t
  function uns_array_to_int_array (arg : uns_array_t) return int_array_t is

    variable v_arr : int_array_t(arg'range);

  begin

    for i in arg'range loop
      v_arr(i) := to_integer(arg(i));
    end loop;

    return v_arr;

  end function uns_array_to_int_array;

  --! convert int_array_t to uns_array_t
  function int_array_to_uns_array (arg : int_array_t; c_elem_size : natural) return uns_array_t is

    variable v_arr : uns_array_t(arg'range)(c_elem_size - 1 downto 0);

  begin

    for i in arg'range loop
      v_arr(i) := to_unsigned(arg(i), c_elem_size);
    end loop;

    return v_arr;

  end function int_array_to_uns_array;

  function shift_left (arg : slv_array_t; constant c_n : natural) return slv_array_t is

    constant c_ELEM_SIZE : natural := arg(0)'length;
    variable v_slv       : std_logic_vector((arg'length * c_ELEM_SIZE) - 1 downto 0);

  begin

    v_slv := slv_array_to_slv(arg, c_ELEM_SIZE) sll c_n * c_ELEM_SIZE;
    return slv_to_slv_array(v_slv, c_ELEM_SIZE);

  end function shift_left;

  function shift_right (arg : slv_array_t; constant c_n : natural) return slv_array_t is

    constant c_ELEM_SIZE : natural := arg(0)'length;
    variable v_slv       : std_logic_vector((arg'length * c_ELEM_SIZE) - 1 downto 0);

  begin

    v_slv := slv_array_to_slv(arg, c_ELEM_SIZE) srl c_n * c_ELEM_SIZE;
    return slv_to_slv_array(v_slv, c_ELEM_SIZE);

  end function shift_right;

  --! convert boolean to std_logic
  function bool_to_sl (arg : boolean) return std_logic is

    variable v_ret : std_logic;

  begin

    if (arg) then
      return '1';
    end if;

    return '0';

  end function bool_to_sl;

  --! convert std_logic to integer
  function sl_to_int (arg: std_logic) return integer is
  begin

    if (arg = '1') then
      return 1;
    else
      return 0;
    end if;

  end function sl_to_int;

  function sum (arg : uns_array_t) return unsigned is

    variable v_out : unsigned(arg(0)'range) := (others => '0');

  begin

    for i in arg'range loop
      v_out := v_out + arg(i);
    end loop;

    return v_out;

  end function sum;

  function sum (arg : sig_array_t) return signed is

    variable v_out : signed(arg(0)'range) := (others => '0');

  begin

    for i in arg'range loop
      v_out := v_out + arg(i);
    end loop;

    return v_out;

  end function sum;

  function sum (arg : int_array_t) return integer is

    variable v_out : integer := 0;

  begin

    for i in arg'range loop
      v_out := v_out + arg(i);
    end loop;

    return v_out;

  end function sum;

end package body types;

----------------------------------------------------------------------------------------------------
