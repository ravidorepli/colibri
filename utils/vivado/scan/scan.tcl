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
    global design_top
    set str ""
    set idx 0
    set keys [dict keys $dct]
    foreach item $lst {
        set key [lindex $keys $idx]
        set str "-generic $key=$item $str"
        incr idx
    }
    return $str
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
    puts "------------------------------------------------------"
    create_project -in_memory -part $part_num
    import_colibri
    read_xdc $root_dir/clk.xdc
    set filename "${design_top}_[join $config _]"
    ## synthesis
    puts "Running synthesis"
    set gens [set_generics $scan_dict $config]
    set syn [list synth_design]
    lappend syn "-mode out_of_context"
        lappend syn "-top $design_top"
        lappend syn "-part $part_num"
        lappend syn $gens
    puts [join $syn " "]
    eval [join $syn " "] >> $result_dir/${filename}_synth.log
    # place and route
    puts "Running Optimization"
    opt_design >> $result_dir/${filename}_opt.log
    puts "Running Placement"
    place_design >> $result_dir/${filename}_place.log
    puts "Running Phys Opt"
    phys_opt_design >> $result_dir/${filename}_physopt.log
    puts "Running Routing"
    route >> $result_dir/${filename}_route.log
    puts "Running Phys Opt 2"
    phys_opt_design >> $result_dir/${filename}_physopt.log
    # compilation is complete
    puts "Writing results"
    set timing_log [report_timing_summary -setup -nworst 1 -return_string]
    report_utilization >> $result_dir/${filename}_report.log
    regexp {Slack.\D+([0-9]+.[0-9]+)} $timing_log matched slack
    regexp {Requirement.\D+([0-9]+.[0-9]+)} $timing_log matched clk_period
    set fmax [expr {1000./($clk_period - $slack)}]
    regexp {LUTs.[ ]+\|[ ]+([0-9]+)} [report_utilization -return_string] matched luts
    regexp {Registers.[ ]+\|[ ]+([0-9]+)} [report_utilization -return_string] matched ffs
    regexp {Block RAM Tile.[ ]*\|[ ]+([0-9]+\.?[0-9]?)} [report_utilization -return_string] matched brams
    regexp {DSPs.[ ]+\|[ ]+([0-9]+)} [report_utilization -return_string] matched dsps
    set res ""
    foreach c $config {
        set res "$res$c,"
    }
    set res "$res$luts,$ffs,$brams,$dsps,[format "%.2f" $fmax]"
    set result_file [open $result_dir/resources_${design_top}.csv a]
    puts $res
    puts $result_file $res
    close $result_file
    close_project
}
puts "-----------------------------------------------"
puts "run completed, results available in $result_dir"
exit