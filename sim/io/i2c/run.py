# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import os
from vunit import VUnit

GHDL_OPTS = ["-frelaxed","-fsynopsys", "--syn-binding"]
NVC_A_OPTS = ["--relaxed"]
script_dir = os.path.dirname(__file__)
PROJ_ROOT = os.path.join(script_dir,"../../../")

vu = VUnit.from_argv()
vu.add_vhdl_builtins()
vu.add_osvvm()
vu.add_verification_components()

uvvm_util_lib = vu.add_library('uvvm_util')
uvvm_util_lib.add_source_files('UVVM/uvvm_util/src/*.vhd')

uvvm_vvc_framework_lib = vu.add_library('uvvm_vvc_framework')
uvvm_vvc_framework_lib.add_source_files('UVVM/uvvm_vvc_framework/src/*.vhd')

bitvis_vip_scoreboard_lib = vu.add_library('bitvis_vip_scoreboard')
bitvis_vip_scoreboard_lib.add_source_files('UVVM/bitvis_vip_scoreboard/src/*.vhd')

bitvis_vip_clock_generator_lib = vu.add_library('bitvis_vip_clock_generator')
bitvis_vip_clock_generator_lib.add_source_files('UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd')
bitvis_vip_clock_generator_lib.add_source_files('UVVM/bitvis_vip_clock_generator/src/*.vhd')

bitvis_vip_i2c_lib = vu.add_library('bitvis_vip_i2c')
bitvis_vip_i2c_lib.add_source_files('UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd')
bitvis_vip_i2c_lib.add_source_files('UVVM/bitvis_vip_i2c/src/*.vhd')


colibri_lib = vu.add_library('colibri')
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/common/*.vhdl") ,allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/io/i2c/*.vhdl") ,allow_empty=True)

tb_lib = vu.add_library("tb_lib")
tb_lib.add_source_files(os.path.join(PROJ_ROOT,"sim/io/i2c/tb_pkg.vhdl"))
tb_lib.add_source_files(os.path.join(PROJ_ROOT,"sim/io/i2c/*.vhdl") ,allow_empty=True)

vu.add_compile_option("ghdl.a_flags",GHDL_OPTS )
vu.add_compile_option("nvc.a_flags",NVC_A_OPTS )
for tb in tb_lib.get_test_benches():
    tb.set_sim_option("modelsim.vsim_flags.gui", ["-voptargs=+acc","-debugdb"])
    tb.set_sim_option("rivierapro.vsim_flags.gui", ["-voptargs=+acc","-debugdb", "+access +r", "-advdataflow"])
    tb.set_sim_option("ghdl.elab_flags", GHDL_OPTS)
    # tb.set_sim_option("ghdl.sim_flags", ["--fst=wave.fst"])
    tb.set_sim_option("nvc.heap_size", "256m")
    tb.set_sim_option("disable_ieee_warnings", True)
    # tb.set_sim_option("ghdl.sim_flags", ["--assert-level=warning"])
vu.main()