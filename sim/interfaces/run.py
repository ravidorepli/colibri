# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import os
import random
from vunit import VUnit

GHDL_OPTS = ["-frelaxed","-fsynopsys", "--syn-binding"]
NVC_A_OPTS = ["--relaxed"]
script_dir = os.path.dirname(__file__)
PROJ_ROOT = os.path.join(script_dir,"../../")

vu = VUnit.from_argv()
vu.add_vhdl_builtins()
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

bitvis_vip_avalon_st_lib = vu.add_library('bitvis_vip_avalon_st')
bitvis_vip_avalon_st_lib.add_source_files('UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd')
bitvis_vip_avalon_st_lib.add_source_files('UVVM/bitvis_vip_avalon_st/src/*.vhd')

bitvis_vip_axistream_lib = vu.add_library('bitvis_vip_axistream')
bitvis_vip_axistream_lib.add_source_files('UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd')
bitvis_vip_axistream_lib.add_source_files('UVVM/bitvis_vip_axistream/src/*.vhd')

colibri_lib = vu.add_library('colibri')
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/common/*.vhdl") ,allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/comms/*.vhdl") ,allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/memory/*.vhdl") ,allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/interfaces/stream/*.vhdl") ,allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/interfaces/memory_mapped/*.vhdl"))
colibri_lib.add_source_files(os.path.join(PROJ_ROOT, "src/memory/*/*.vhdl"), allow_empty=True)

tb_lib = vu.add_library("tb_lib")
tb_lib.add_source_files(os.path.join(PROJ_ROOT,"sim/interfaces/stream/*.vhdl") ,allow_empty=True)
tb_lib.add_source_files(os.path.join(PROJ_ROOT,"sim/interfaces/stream/avst_ram_tb/*.vhdl") ,allow_empty=True)
tb_lib.add_source_files(os.path.join(PROJ_ROOT,"sim/interfaces/stream/avst_ram_be_tb/*.vhdl") ,allow_empty=True)
tb_lib.add_source_files(os.path.join(PROJ_ROOT,"sim/interfaces/stream/avst_ram_read_unaligned_tb/*.vhdl") ,allow_empty=True)
tb_lib.add_source_files(os.path.join(PROJ_ROOT,"sim/interfaces/memory_mapped/*.vhdl") ,allow_empty=True)

vu.add_compile_option("ghdl.a_flags",GHDL_OPTS )
vu.add_compile_option("nvc.a_flags",NVC_A_OPTS )
for tb in tb_lib.get_test_benches():

    # Avalon-ST <-> AXI-Stream ---------------------------------------------------------------------
    if tb.name == "avst_to_axis_tb" or tb.name == "axis_to_avst_tb":
        for g_AVST_ENDIANNESS in ["BIG", "LITTLE"]:
            tb.add_config(
                name     = g_AVST_ENDIANNESS,
                generics = {"g_AVST_ENDIANNESS"  : g_AVST_ENDIANNESS}
                    )
    # ----------------------------------------------------------------------------------------------

    # Avalon-ST width converter --------------------------------------------------------------------
    if tb.name == "avst_width_converter_tb":

        # some selected test scenarios
        for g_SYM_WIDTH, g_INPUT_SYM, g_OUTPUT_SYM in [
             (8, 4, 4), (8, 2, 4), (8, 4, 2),
             (1, 1, 1), (1, 32, 1), (1, 1, 32),
             (13, 5, 7), (13, 7, 5),
             (8, 16, 9), (8, 16, 18), (8, 16, 27),
        ]:
            tb.add_config(
                name = f'sel_{g_SYM_WIDTH}b_{g_INPUT_SYM}_to_{g_OUTPUT_SYM}',
                generics = {
                    "g_SEED"       : 42,
                    "g_SYM_WIDTH"  : g_SYM_WIDTH,
                    "g_INPUT_SYM"  : g_INPUT_SYM,
                    "g_OUTPUT_SYM" : g_OUTPUT_SYM
                    }
                    )
            
        # some fully random tests
        for i in range(5):
            g_SEED       = random.randint(1, 1024)
            g_SYM_WIDTH  = random.randint(1, 511)
            g_INPUT_SYM  = random.randint(1, 31)
            g_OUTPUT_SYM = random.randint(1, 31)
            tb.add_config(
                name = f'rand_{g_SYM_WIDTH}b_{g_INPUT_SYM}_to_{g_OUTPUT_SYM}_seed{g_SEED}',
                generics = {
                    "g_SEED"       : g_SEED,
                    "g_SYM_WIDTH"  : g_SYM_WIDTH,
                    "g_INPUT_SYM"  : g_INPUT_SYM,
                    "g_OUTPUT_SYM" : g_OUTPUT_SYM
                    }
                    )
    # ----------------------------------------------------------------------------------------------

    # Avalon-ST FIFO -------------------------------------------------------------------------------
    if tb.name == "avst_fifo_tb":

        # test both sync. and async. versions
        for g_ASYNC_CLOCKS in (True, False):
            async_str = 'async_' if g_ASYNC_CLOCKS else ''

            # some selected test scenarios
            for g_SYM_WIDTH, g_DATA_SYM in [
                (8, 16), (1, 8)
            ]:
                tb.add_config(
                    name = f'{async_str}sel_{g_SYM_WIDTH}b_{g_DATA_SYM}',
                    generics = {
                        "g_SEED"         : 42,
                        "g_SYM_WIDTH"    : g_SYM_WIDTH,
                        "g_DATA_SYM"     : g_DATA_SYM,
                        "g_ASYNC_CLOCKS" : g_ASYNC_CLOCKS
                        }
                    )
                
            # some fully random tests
            for i in range(5):
                g_SEED      = random.randint(1, 1024)
                g_SYM_WIDTH = random.randint(1, 511)
                g_DATA_SYM  = random.randint(1, 31)
                tb.add_config(
                    name = f'{async_str}rand_{g_SYM_WIDTH}b_{g_DATA_SYM}_seed{g_SEED}',
                    generics = {
                        "g_SEED"         : g_SEED,
                        "g_SYM_WIDTH"    : g_SYM_WIDTH,
                        "g_DATA_SYM"     : g_DATA_SYM,
                        "g_ASYNC_CLOCKS" : g_ASYNC_CLOCKS
                        }
                    )
    # ----------------------------------------------------------------------------------------------
    # Avalon-ST RAM interfaces ---------------------------------------------------------------------
    if tb.name == "avst_ram_tb":

        # some selected test scenarios
        for g_ADDR_WIDTH in range(3, 9, 2):
            for g_DATA_WIDTH in [8, 64]:
                tb.add_config(
                    name = f'dwidth={g_DATA_WIDTH},awidth={g_ADDR_WIDTH}',
                    generics = {
                        "g_DATA_WIDTH" : g_DATA_WIDTH,
                        "g_ADDR_WIDTH" : g_ADDR_WIDTH
                        }
                    )
                
    if tb.name == "avst_ram_be_tb":

        # some selected test scenarios
        for g_BYTE_WIDTH in [8, 9]:
            for g_WORD_BYTES in [1, 2, 5, 8]:
                tb.add_config(
                    name = f'bwidth={g_BYTE_WIDTH},wbytes={g_WORD_BYTES}',
                    generics = {
                        "g_BYTE_WIDTH" : g_BYTE_WIDTH,
                        "g_WORD_BYTES" : g_WORD_BYTES
                        }
                    )

    if tb.name == "avst_ram_write_unaligned_tb":

        # some selected test scenarios
        for g_BYTE_WIDTH in [8, 9]:
            for g_WORD_BYTES in [2, 5, 8]:
                tb.add_config(
                    name = f'bwidth={g_BYTE_WIDTH},wbytes={g_WORD_BYTES}',
                    generics = {
                        "g_BYTE_WIDTH" : g_BYTE_WIDTH,
                        "g_WORD_BYTES" : g_WORD_BYTES
                        }
                    )

    if tb.name == "avst_ram_read_unaligned_tb":

        # some selected test scenarios
        for g_BYTE_WIDTH in [8, 9]:
            for g_WORD_BYTES in [2, 5, 8]:
                for g_RAM_DEPTH in [17, 128]:
                    tb.add_config(
                        name = f'bwidth={g_BYTE_WIDTH},wbytes={g_WORD_BYTES},depth={g_RAM_DEPTH}',
                        generics = {
                            "g_BYTE_WIDTH" : g_BYTE_WIDTH,
                            "g_WORD_BYTES" : g_WORD_BYTES,
                            "g_RAM_DEPTH"  : g_RAM_DEPTH
                            }
                            )
    # ----------------------------------------------------------------------------------------------

    tb.set_sim_option("modelsim.vsim_flags.gui", ["-voptargs=+acc","-debugdb"])
    tb.set_sim_option("rivierapro.vsim_flags.gui", ["-voptargs=+acc","-debugdb", "+access +r", "-advdataflow"])
    tb.set_sim_option("ghdl.elab_flags", GHDL_OPTS)
    tb.set_sim_option("nvc.sim_flags", ["--wave=wave.fst"])
    tb.set_sim_option("nvc.heap_size", "256m")
    tb.set_sim_option("disable_ieee_warnings", True)
    # tb.set_sim_option("ghdl.sim_flags", ["--assert-level=warning"])
vu.main()