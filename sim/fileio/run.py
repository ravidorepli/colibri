# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import os
from vunit import VUnit
import itertools

GHDL_OPTS = ["-frelaxed","-fsynopsys", "--syn-binding"]
NVC_A_OPTS = ["--relaxed"]
script_dir = os.path.dirname(__file__)
PROJ_ROOT = os.path.join(script_dir,"../../")
# test settings
a_widths = [16,32]
b_widths = range(1,129)

vu = VUnit.from_argv(compile_builtins=False)
vu.add_vhdl_builtins()
vu.add_osvvm()
vu.add_verification_components()

colibri_lib = vu.add_library('colibri')
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/common/utils.vhdl") ,allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/fileio/*.vhdl") ,allow_empty=True)

tb_lib = vu.add_library("tb_lib")
tb_lib.add_source_files(os.path.join(PROJ_ROOT,"sim/fileio/*.vhdl") ,allow_empty=True)

vu.add_compile_option("ghdl.a_flags",GHDL_OPTS )
vu.add_compile_option("nvc.a_flags",NVC_A_OPTS )
for tb in tb_lib.get_test_benches():

    if tb.name == "binaryio_tb":
        for g_READ_BYTES in range(4, 33):
            tb.test("test_incomplete").add_config(
                name     =f'read_{g_READ_BYTES}',
                generics = {
                    "g_READ_BYTES" : f"{g_READ_BYTES}"
                }
            )

    tb.set_sim_option("modelsim.vsim_flags.gui", ["-voptargs=+acc","-debugdb"])
    tb.set_sim_option("rivierapro.vsim_flags.gui", ["-voptargs=+acc","-debugdb", "+access +r", "-advdataflow"])
    tb.set_sim_option("ghdl.elab_flags", GHDL_OPTS)
    tb.set_sim_option("nvc.sim_flags", ["-wwave.fst"])
    tb.set_sim_option("nvc.heap_size", "256m")
    tb.set_sim_option("disable_ieee_warnings", True)

vu.main()