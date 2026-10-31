# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import os
import itertools
from vunit import VUnit

GHDL_OPTS = ["-frelaxed","-fsynopsys", "--syn-binding"]
NVC_A_OPTS = ["--relaxed"]
script_dir = os.path.dirname(__file__)
PROJ_ROOT = os.path.join(script_dir,"../../")

vu = VUnit.from_argv()
vu.add_vhdl_builtins()
vu.add_osvvm()
vu.add_verification_components()

colibri_lib = vu.add_library('colibri')
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/common/*.vhdl") ,allow_empty=True)

tb_lib = vu.add_library("tb_lib")
tb_lib.add_source_files(os.path.join(PROJ_ROOT,"sim/common/*.vhdl") ,allow_empty=True)

vu.add_compile_option("ghdl.a_flags",GHDL_OPTS )
vu.add_compile_option("nvc.a_flags",NVC_A_OPTS )
for tb in tb_lib.get_test_benches():
    tb.set_sim_option("modelsim.vsim_flags.gui", ["-voptargs=+acc","-debugdb"])
    tb.set_sim_option("rivierapro.vsim_flags.gui", ["-voptargs=+acc","-debugdb", "+access +r", "-advdataflow"])
    tb.set_sim_option("ghdl.elab_flags", GHDL_OPTS)
    tb.set_sim_option("nvc.heap_size", "256m")
    tb.set_sim_option("nvc.sim_flags", ["--wave=wave.fst"])
    tb.set_sim_option("disable_ieee_warnings", True)
    # tb.set_sim_option("ghdl.sim_flags", ["--assert-level=warning"])

    if tb.name == 'synchro_pulse_tb':
        for stages in [2, 3, 20]:
            for src_clk, dst_clk in itertools.product([6, 50], repeat=2):
                tb.add_config(
                    name=f'src={src_clk},dst={dst_clk},stages={stages}',
                    generics={
                        'g_DST_CLK_PERIOD' : f'{dst_clk} ns',
                        'g_SRC_CLK_PERIOD' : f'{src_clk} ns',
                        'g_NUM_STAGES' : stages
                    }
                )
    if tb.name == 'stream_buffer_tb':
        for register in [True, False]:
            tb.add_config(
                name=f'reg_datapath={register}',
                generics={
                    'g_REGISTER_DATAPATH' : register
                }
            )
vu.main()