<!--
SPDX-FileCopyrightText: 2026 CERN

SPDX-License-Identifier: CERN-OHL-W-2.0
-->

# Formal Verification

## Tools setup
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) by YosysHQ includes all the necessary tools. To install do

```bash
# Download the latest release from the YosysHQ GitHub repository
wget wget https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2025-07-18/oss-cad-suite-linux-x64-20250718.tgz
# Extract the archive
tar -xvf oss-cad-suite-linux-x64-20250718.tgz
# Set the environment
source oss-cad-suite/environment
```
Alternatively, [hdlc/formal](https://hub.docker.com/r/hdlc/formal) Docker container is similar.
To run it with `podman` execute
```
podman run -it --rm -v .:/wrk:z -w /wrk docker.io/hdlc/formal bash
```

## Running the verification
To verify a module (e.g. `common`, `comms`, ...) change to the corresponding `fv` subdirectory and run SBY. For example
```bash
cd fv/common
sby --yosys "yosys -m ghdl" -f run.sby
```
This will run tests for all the components in that module.

To list all the tasks contained in the `.sby` file, run
```bash
sby --yosys "yosys -m ghdl" -f run.sby --dumptasks
```

To run a specific task, add its name to the command, like so
```bash
sby --yosys "yosys -m ghdl" -f run.sby counter_prove
```

## SBY script usage
Each `fv` subdirectory contains a `run.sby` script which specifies the parameters used for verification. See [`sby` documentation](https://yosyshq.readthedocs.io/projects/sby/en/latest/reference.html) for reference on the file format.

The `run.sby` script uses Python scripting to generate FV tasks for multiple components.
To add a new component to the script, simply add it to any of the arrays in the `[tasks]` section.
There is a separate array for each of the 3 tasks: `prove`, `bmc` and `cover`; this way we can specify precisely which task will be generated for the component. For example
```python
[tasks]
--pycode-begin--
for name in [ # Use `prove` to verify the `counter` component
    'counter'
    ]:
    output(f"{name}_prove prove name_tag_{name}")

for name in [ # Use `bmc` to verify the `debouncer` component
    'debouncer'
    ]:
    output(f"{name}_bmc bmc name_tag_{name}")

for name in [ # Cover both components
    'counter',
    'debouncer'
    ]:
    output(f"{name}_cover cover name_tag_{name}")
--pycode-end--
```
The VHDL source file for the component is included automatically by the Python loop in the `[files]` section. Any additional files should be added explicitly
```python
[files]
../../src/common/utils.vhdl
utils_fv.vhdl

--pycode-begin--
for tag in tags:
    # Includes source files for all unique component names
    if tag.startswith('name_tag_'):
        name = tag.split('name_tag_')[-1]
        output(f"../../src/common/{name}.vhdl")
        output(f"{name}.psl")
--pycode-end--
```
Additional files should also be specified in the `[scripts]` section along with any component-specific properties such as generics and top-level entity names
```python
[script]
--pycode-begin--
for tag in tags:
    # Generates build scripts for all unique component names
    if tag.startswith('name_tag_'):
        name = tag.split('name_tag_')[-1]

        # Set any specific generics, additional files, top entity name ... -----
        generics = ''
        add_files = 'utils.vhdl'
        entity_name = name
        if name == 'counter':
            generics = '-gg_MODULO=10'
        if name == 'utils':
            add_files = 'utils_fv.vhdl'
            entity_name += '_fv'
        # ----------------------------------------------------------------------
```

Task options, such as algorithm `depth`, can be configured in the `[options]` section, while the `engine` and `solver` for each task is specified in the `[engines]` sections. All of these parameters may be chosen globally using the `prove`, `bmc` and `cover` tags
```python
[options]
depth 20
prove: mode prove
bmc: mode bmc
cover: mode cover

[engines]
cover: smtbmc
bmc: abc bmc3
prove: abc pdr
```

or they may be specified separately using Python code

```python
[options]
prove: mode prove
bmc: mode bmc
cover: mode cover

--pycode-begin--
depths = { # ------------------------------------ Set BMC depth ----------------
    'utils' : 10,
}
default = 20

for tag in tags:
    if tag.endswith('_bmc'):
        name = tag.split('_bmc')[0]

        if name in depths:
            output(f"{tag}: depth {depths[name]}")
        else:
            output(f"{tag}: depth {default}")
# ------------------------------------------------------------------------------
--pycode-end--
```

## Tips
1. If certain task is taking a long time to finish, SBY's `--autotune` feature can help find an optimal engine to run it
    ```bash
    sby --yosys "yosys -m ghdl" -f run.sby utils_prove --autotune
    ```
    This also helps identify engine-specific issues, since it outputs the results for all possible engines.

## TODO
- describe `psl` (language, files)

## Known issues
1. Many `psl` files include an initial reset assumption (`assume reset_i;`) to ensure the component being verified always starts in an initialized state. When using the `smtbmc` engine in `prove` mode, this assumption is ignored, resulting in assertion failures due to a random initial state.