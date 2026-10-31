load_package flow
load_package report
package require cmdline

package require json
set ::tcl_interactive 0
set root_dir [file dirname [file normalize [info script]]]

set jsonfile [open ${root_dir}/config.json r]
set json_data [read $jsonfile]
close $jsonfile
set jdict [json::json2dict $json_data]
set design_top [dict get $jdict top]
set part_num [dict get $jdict device]
dict unset jdict device
dict unset jdict top
set scan_dict $jdict


set result_dir ${root_dir}/results_$design_top

if {[catch {file mkdir $result_dir} err_msg]} {
  if {[string match "*file exists*" $err_msg] || [string match "*directory exists*" $err_msg]} {
    puts "Directory '$result_dir' already exists (caught error)."
  } else {
    error "Error creating directory '$result_dir': $err_msg"
  }
} else {
  puts "Directory '$result_dir' created."
}

set result_file [open ${result_dir}/resources_${design_top}.csv w]

set header ""
foreach key [dict keys $scan_dict] {
    set header "${header}${key},"
}
set header "${header}LUTs,FFs,BRAMs,DSPs,FMAX"
puts $result_file $header
close $result_file

## calculate cartesian product of configurations
proc cart_prod {arg} {
    set arg_list {}
    foreach key [dict keys $arg] {
        lappend arg_list [dict get $arg $key]
    }
    set result {{}}
    foreach current_list $arg_list {
        set elem {}
        foreach ex $result {
            foreach item $current_list {
                lappend elem [concat $ex [list $item]]
            }
        }
        set result $elem
    }
    return $result
}

## set generics from dictionary
proc set_generics {dct lst} {
    set idx 0
    set keys [dict keys $dct]
    foreach item $lst {
        set key [lindex $keys $idx]
        set_parameter -name $key $item
        incr idx
    }
}

proc make_all_pins_virtual {} {

    execute_module -tool map

    set name_ids [get_names -filter * -node_type pin]

    foreach_in_collection name_id $name_ids {
        set pin_name [get_name_info -info full_path $name_id]
        post_message "Making VIRTUAL_PIN assignment to $pin_name"
        set_instance_assignment -to $pin_name -name VIRTUAL_PIN ON
    }
    export_assignments
}

#import library
proc import_colibri {} {
    global root_dir
    puts "Importing colibri library"
    source ${root_dir}/../colibri.tcl
}

set comp_list [cart_prod $scan_dict]
puts "------------------------------------------------------"
puts "******************************************************"
puts "------------------------------------------------------"
puts "Resource/Fmax Scan of entity ${design_top}"
puts "Running [llength $comp_list] compilations. This will take some time..."

foreach config $comp_list {
    puts "-----------------------------------------------"
    set filename "${result_dir}/${design_top}_[join $config _]"
    project_new -overwrite $filename
    set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008
    set_global_assignment -name DEVICE $part_num
    import_colibri
    set_global_assignment -name TOP_LEVEL_ENTITY $design_top
    set_generics $scan_dict $config
    make_all_pins_virtual
    #----------------------------------
    puts "Running synthesis"
    execute_module -tool map
    puts "Running Fitter"
    execute_module -tool fit
    puts "Writing results"
    load_report
    # set panel {Synthesis||Partition "root_partition"||Partition "root_partition" Resource Utilization by Entity}
    # set id [get_report_panel_id $panel]
    # regexp {([0-9]+)} [get_report_panel_data -id $id -row 1 -col 1] matched luts
    # regexp {([0-9]+)} [get_report_panel_data -id $id -row 1 -col 2] matched ffs
    # regexp {([0-9]+)} [get_report_panel_data -id $id -row 1 -col 3] matched brams
    # regexp {([0-9]+)} [get_report_panel_data -id $id -row 1 -col 4] matched dsps
    set luts [get_fitter_resource_usage -alut]
    set ffs [get_fitter_resource_usage -reg]
    set brams [get_fitter_resource_usage -mem_bit -used]
    regexp {([0-9]+)[ ]+/} [get_fitter_resource_usage -resource "DSP Blocks Needed*"] matched dsps
    
    set fmax "-1.0"        
    set res ""
    
    foreach c $config {
        set res "$res$c,"
    }
    
    set res "$res$luts,$ffs,$brams,$dsps,[format "%.2f" $fmax]"
    set result_file [open $result_dir/resources_${design_top}.csv a]
    puts $res
    puts $result_file $res
    close $result_file
    unload_report
    project_close
}

puts "-----------------------------------------------"
puts "run completed, results available in $result_dir"
exit


