# Setting environment
sh mkdir -p Netlist
sh mkdir -p Report

set company {NTUGIEE}
set designer {Student}

# Library and search-path setup
set search_path ". /home/raid7_2/course/cvsd/CBDK_IC_Contest/CIC/SynopsysDC/db ../01_RTL $search_path ../ ./"
set target_library "slow.db"
set link_library   "* $target_library dw_foundation.sldb"
set symbol_library "tsmc13.sdb generic.sdb"
set synthetic_library "dw_foundation.sldb"
set default_schematic_options {-size infinite}

# Design setup
set DESIGN "IOTDF"

set hdlin_translate_off_skip_text "TRUE"
set edifout_netlist_only "TRUE"
set verilogout_no_tri true

set hdlin_enable_presto_for_vhdl "TRUE"
set sh_enable_line_editing true
set sh_line_editing_mode emacs
history keep 100
alias h history

# Read RTL
analyze -format sverilog "flist.sv"
elaborate $DESIGN
current_design [get_designs $DESIGN]
link

# Apply constraints
source -echo -verbose ./IOTDF_DC.sdc

# Pre-compile checks
check_design  > Report/check_design.txt
check_timing  > Report/check_timing.txt

# Clock gating setup - DC will auto-detect explicit enables in RTL
set_clock_gating_style -sequential_cell latch -positive_edge_logic {integrated:icgcp} -control_point before -control_signal scan_enable
set compile_clock_gating_through_hierarchy true

# Synthesis
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
set_fix_hold [all_clocks]
compile_ultra

# Reports
current_design [get_designs $DESIGN]
report_timing -max_paths 5 > "./Report/${DESIGN}.timing"
report_area   -hierarchy > "./Report/${DESIGN}.area"
report_clock_gating -gated -ungated > "./Report/${DESIGN}.clock_gating"

# Netlist output
set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true
change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed {a-z A-Z 0-9 _}   -max_length 255 -type cell
define_name_rules name_rule -allowed {a-z A-Z 0-9 _[]} -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive
change_names -hierarchy -rules name_rule
remove_unconnected_ports -blast_buses [get_cells -hierarchical *]
set verilogout_higher_designs_first true
write -format verilog -hierarchy -output "../03_GATE/${DESIGN}_syn.v"
write_sdf -version 2.1 -context verilog -load_delay cell "../03_GATE/${DESIGN}_syn.sdf"

# Final checks
report_timing
report_area -hierarchy
check_design
exit

