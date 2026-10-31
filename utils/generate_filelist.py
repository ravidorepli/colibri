# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import os
import yaml

colibri_root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../")


def list_files_recursive(directory):
    file_paths = []
    for dirpath, _, filenames in os.walk(directory):
        for filename in filenames:
            if filename.endswith(".vhdl") and not ("binaryio" in filename):
                file_paths.append(
                    os.path.relpath(
                        os.path.join(dirpath, filename),
                        colibri_root,
                    )
                )

    return sorted(file_paths)


# Example usage:
directory_path = os.path.join(colibri_root, "./src")
print("Writing file lists:")
all_files = list_files_recursive(directory_path)

with open(os.path.join(colibri_root, "utils/hog/colibri.src"), "w") as hoglist:
    hoglist.write("\n".join([os.path.join("colibri", x) for x in all_files]))
print("Hog file list written.")

fusesoc = {
    "name": "cern:colibri:colibri:0.0.1",
    "description": "colibri: Common Cores Library",
    "filesets": {
        "rtl": {
            "files": all_files,
            "file_type": "vhdlSource-2008",
            "logical_name": "colibri",
        }
    },
    "targets": {"default": {"filesets": ["rtl"]}},
}
with open(os.path.join(colibri_root, "colibri.core"), "w") as fusesoc_core:
    fusesoc_core.write("CAPI=2:\n")
    fusesoc_core.write(yaml.dump(fusesoc, sort_keys=False))
print("FuseSoC file list written.")

with open(os.path.join(colibri_root, "utils/vivado/colibri.tcl"), "w") as vivado_tcl:
    vivado_tcl.write("set script_dir [file dirname [file normalize [info script]]]\n")
    vivado_tcl.write("set colibri_src $script_dir/../../\n")
    vivado_tcl.write(
        "\n".join(
            [
                "read_vhdl -library colibri -vhdl2008 "
                + os.path.join("$colibri_src", x)
                for x in all_files
            ]
        )
    )
print("vivado tcl written.")

with open(os.path.join(colibri_root, "utils/vivado/colibri_legacy.tcl"), "w") as vivado_tcl:
    vivado_tcl.write("set script_dir [file dirname [file normalize [info script]]]\n")
    vivado_tcl.write("set colibri_src $script_dir/../../\n")
    vivado_tcl.write(
        "\n".join(
            [
                "read_vhdl -library colibri -vhdl2008 "
                + os.path.join("$colibri_src", x)
                for x in all_files if not ("common.vhdl" in x) or not ("synchro_generic.vhdl" in x)
            ]
        )
    )
print("vivado legacy tcl written.")

with open(os.path.join(colibri_root, "utils/quartus/colibri.tcl"), "w") as quartus_tcl:
    quartus_tcl.write("set script_dir [file dirname [file normalize [info script]]]\n")
    quartus_tcl.write("set colibri_src $script_dir/../../\n")
    quartus_tcl.write("set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008\n")
    quartus_tcl.write(
        "\n".join(
            [
                "set_global_assignment -name VHDL_FILE "
                + os.path.join("$colibri_src", x)
                + " -library colibri"
                for x in all_files
            ]
        )
    )
print("quartus tcl written.")


with open(os.path.join(colibri_root, "utils/quartus/colibri_legacy.tcl"), "w") as quartus_tcl:
    quartus_tcl.write("set script_dir [file dirname [file normalize [info script]]]\n")
    quartus_tcl.write("set colibri_src $script_dir/../../\n")
    quartus_tcl.write("set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008\n")
    quartus_tcl.write(
        "\n".join(
            [
                "set_global_assignment -name VHDL_FILE "
                + os.path.join("$colibri_src", x)
                + " -library colibri"
                for x in all_files if not ("common.vhdl" in x) or not ("synchro_generic.vhdl" in x)
            ]
        )
    )
print("quartus legacy tcl written.")

with open(os.path.join(colibri_root, "utils/quartus/colibri.qip"), "w") as quartus_qip:
    quartus_qip.write(
        "\n".join(
            [
                "set_global_assignment -name VHDL_FILE "
                + os.path.join("$quartus(qip_path)/../../", x)
                + " -library colibri"
                for x in all_files if not ("common.vhdl" in x)
            ]
        )
    )
print("quartus QIP written.")
