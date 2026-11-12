#==========================================================================================
# File        : regression/regression.do
# Project     : PCIE_Gen6
# Description : Batch regression for the PCIe Gen6 UVM bench (Questa / ModelSim).
#
#   Run from the PROJECT ROOT (the folder that has run.do, PCIe_top/, PCIe_tests/ ...):
#
#     vsim -c -do "do regression/regression.do; quit -f"                     (3DW + 4DW)
#     vsim -c -do "set BUILD 3dw; do regression/regression.do; quit -f"      (3DW only)
#     vsim -c -do "set BUILD 4dw; do regression/regression.do; quit -f"      (4DW only)
#     vsim -c -do "set BUILD 3dw; set TESTS {PCIe_gen6_3DW_Flit_MemWr_Random_test}; set RUNS 5; do regression/regression.do; quit -f"
#
#   Optional knobs (set them before 'do regression/regression.do'):
#     BUILD     3dw | 4dw | all             (default all)
#     TESTS     {test1 test2 ...}           run only these (instead of the test list)
#     RUNS      N                           seeds per test, overrides the list column
#     SEED      random | <number>           seed when the list gives none (default random)
#     RUN_TIME  -all | e.g. 20ms            sim time limit per test (default -all)
#     VERB      UVM_LOW | UVM_MEDIUM ...    +UVM_VERBOSITY (default UVM_LOW)
#     COV       1 | 0                       save functional coverage (covergroups) per test,
#                                           merge + report at the end (default 1)
#     CODECOV   0 | 1                       also collect code coverage (+cover=bcesf / -coverage)
#     KEEP_PASS_LOGS 1 | 0                  0 = delete the (very large) log of every PASS run
#
#   Output : regression/results/<date_time>/
#              compile_<lib>.log , logs/<test>__s<seed>.log , summary.txt , summary.csv
#              ucdb/<test>__s<seed>.ucdb , merged.ucdb , coverage_summary.txt ,
#              coverage_details.txt , coverage_html/index.html
#   Status : PASS        UVM_ERROR==0 and UVM_FATAL==0 and no simulator ** Error/Fatal
#            FAIL        any of the above non-zero
#            INCOMPLETE  no UVM Report Summary in the log (hang / time limit / crash)
#            LOAD_ERR    vsim could not load the design
#            NO_SUCH_TEST  +UVM_TESTNAME is not a registered test (check the spelling / test list)
#==========================================================================================

onbreak {resume}
onerror {resume}

if {![info exists BUILD]}    {set BUILD all}
if {![info exists SEED]}     {set SEED random}
if {![info exists RUN_TIME]} {set RUN_TIME -all}
if {![info exists VERB]}     {set VERB UVM_LOW}
if {![info exists COV]}      {set COV 1}
if {![info exists CODECOV]}  {set CODECOV 0}
if {![info exists KEEP_PASS_LOGS]} {set KEEP_PASS_LOGS 1}

set stamp  [clock format [clock seconds] -format %Y%m%d_%H%M%S]
set regdir "regression/results/$stamp"
file mkdir "$regdir/logs"
if {$COV} { file mkdir "$regdir/ucdb" }

set SRC [list PCIe_top/PCIe_PHY_interface.sv PCIe_top/PCIe_PIPE_interface.sv \
              PCIe_config/enum_defs.sv PCIe_top/PCIe_pkg.sv PCIe_top/PCIe_top.sv]

# build name -> {library  defines  test-list}
set BUILDS(3dw) {work_3dw PCIE_GEN6_FEC_CRC                       regression/testlist_3dw.txt}
set BUILDS(4dw) {work_4dw PCIE_GEN6_FEC_CRC+FORCE_4DW+CONFIG_4DW  regression/testlist_4dw.txt}

set RESULTS {}

#------------------------------------------------------------------------------
proc compile_build {lib defs} {
  global SRC regdir CODECOV
  if {[file exists $lib]} { catch {vdel -lib $lib -all} }
  vlib $lib
  set covopt [expr {$CODECOV ? "+cover=bcesf" : ""}]
  if {[catch {vlog -work $lib -sv {*}$covopt +define+$defs -l $regdir/compile_$lib.log {*}$SRC} err]} {
    echo "REGRESSION : COMPILE FAILED for $lib ($err) - see $regdir/compile_$lib.log"
    return 0
  }
  return 1
}

#------------------------------------------------------------------------------
# test list line : <test> [num_seeds] [seed]
proc read_list {fname} {
  set out {}
  if {![file exists $fname]} { echo "REGRESSION : test list $fname not found"; return $out }
  set fh [open $fname r]
  while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} continue
    lappend out $line
  }
  close $fh
  return $out
}

#------------------------------------------------------------------------------
proc parse_log {log seed_in} {
  set err -1 ; set fat -1 ; set seed $seed_in
  if {![file exists $log]} { return [list INCOMPLETE - - $seed] }
  # logs can be several 100 MB : scan in 8 MB chunks instead of one read
  set tool_err 0 ; set carry "" ; set last "" ; set badname 0
  set fh [open $log r]
  while {![eof $fh]} {
    set chunk "$carry[read $fh 8000000]"
    incr tool_err [regexp -all {\*\* (Error|Fatal)} $chunk]
    if {[string first "\[INVTST\]" $chunk] >= 0} { set badname 1 }
    if {$seed eq $seed_in} { regexp {Sv_Seed\s*=\s*(\d+)} $chunk -> seed }
    set i [string last "Report counts by severity" $chunk]
    if {$i >= 0} { set last [string range $chunk $i [expr {$i + 400}]] }
    set carry [string range $chunk end-200 end]
  }
  close $fh
  if {$last ne ""} {
    regexp {UVM_ERROR\s*:\s*(\d+)} $last -> err
    regexp {UVM_FATAL\s*:\s*(\d+)} $last -> fat
  }

  if {$badname} {
    set st NO_SUCH_TEST
  } elseif {$err < 0} {
    set st INCOMPLETE
  } elseif {$err > 0 || $fat > 0 || $tool_err > 0} {
    set st FAIL
  } else {
    set st PASS
  }
  if {$err < 0} { set err - ; set fat - }
  return [list $st $err $fat $seed]
}

#------------------------------------------------------------------------------
proc run_one {lib test seed} {
  global regdir RUN_TIME VERB RESULTS COV CODECOV KEEP_PASS_LOGS
  set tag  [expr {$seed eq "random" ? "r[clock clicks]" : $seed}]
  set log  "$regdir/logs/${test}__s${tag}.log"
  set ucdb "$regdir/ucdb/${test}__s${tag}.ucdb"
  set vcov [expr {$CODECOV ? "-coverage" : ""}]
  set t0   [clock seconds]
  echo "REGRESSION : RUNNING $test  (lib=$lib seed=$seed)"

  if {[catch {vsim -onfinish stop {*}$vcov -sv_seed $seed -l $log $lib.PCIe_top \
                   +UVM_TESTNAME=$test +UVM_VERBOSITY=$VERB +UVM_NO_RELNOTES} err]} {
    catch {quit -sim}
    lappend RESULTS [list $test $lib LOAD_ERR - - $seed 0 $log]
    echo "REGRESSION : LOAD_ERR $test : $err"
    return
  }
  if {$RUN_TIME eq "-all"} { run -all } else { run $RUN_TIME }
  if {$COV} {
    if {[catch {coverage save $ucdb} cerr]} { echo "REGRESSION : coverage save failed for $test : $cerr" }
  }
  catch {quit -sim}

  set dt [expr {[clock seconds] - $t0}]
  foreach {st e f s} [parse_log $log $seed] break
  lappend RESULTS [list $test $lib $st $e $f $s $dt $log]
  echo [format "REGRESSION : %-10s %s  (UVM_ERROR=%s UVM_FATAL=%s seed=%s %ss)" $st $test $e $f $s $dt]
  if {$st eq "PASS" && !$KEEP_PASS_LOGS} { catch {file delete $log} }
}

#------------------------------------------------------------------------------
if {$BUILD eq "all"} { set blist {3dw 4dw} } else { set blist [list $BUILD] }

foreach b $blist {
  if {![info exists BUILDS($b)]} { echo "REGRESSION : unknown BUILD '$b' (use 3dw / 4dw / all)"; continue }
  foreach {lib defs listfile} $BUILDS($b) break

  echo "REGRESSION : ===== COMPILING $b ($lib) ====="
  if {![compile_build $lib $defs]} {
    lappend RESULTS [list "<compile $b>" $lib COMPILE_ERR - - - 0 $regdir/compile_$lib.log]
    continue
  }

  if {[info exists TESTS]} { set entries $TESTS } else { set entries [read_list $listfile] }

  foreach e $entries {
    set test [lindex $e 0]
    set n    [expr {[llength $e] > 1 ? [lindex $e 1] : 1}]
    set sd   [expr {[llength $e] > 2 ? [lindex $e 2] : $SEED}]
    if {[info exists RUNS]} { set n $RUNS }
    for {set k 0} {$k < $n} {incr k} { run_one $lib $test $sd }
  }
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
set npass 0 ; set nfail 0
set fh  [open "$regdir/summary.txt" w]
set csv [open "$regdir/summary.csv" w]
puts $csv "test,lib,status,uvm_error,uvm_fatal,seed,time_s,log"

set hdr [format "%-62s %-9s %-11s %-6s %-6s %-12s %s" TEST LIB STATUS ERR FATAL SEED TIME(s)]
puts $fh "PCIe Gen6 regression : $stamp   BUILD=$BUILD"
puts $fh $hdr
puts $fh [string repeat - [string length $hdr]]
foreach r $RESULTS {
  foreach {t l st e f s dt log} $r break
  if {$st eq "PASS"} {incr npass} else {incr nfail}
  puts $fh  [format "%-62s %-9s %-11s %-6s %-6s %-12s %s" $t $l $st $e $f $s $dt]
  puts $csv "$t,$l,$st,$e,$f,$s,$dt,$log"
}
puts $fh [string repeat - [string length $hdr]]
puts $fh "RUNS  : TOTAL=[expr {$npass+$nfail}]  PASS=$npass  NOT_PASS=$nfail"

#------------------------------------------------------------------------------
# Test-level summary : one line per test (all its seeds), PASS only if every run passed
#------------------------------------------------------------------------------
set order {}
foreach r $RESULTS {
  foreach {t l st e f s dt log} $r break
  set k "$t|$l"
  if {![info exists TRUNS($k)]} { lappend order $k ; set TRUNS($k) 0 ; set TPASS($k) 0 }
  incr TRUNS($k)
  if {$st eq "PASS"} { incr TPASS($k) }
}
set tp 0 ; set tf 0
set ts [open "$regdir/test_summary.txt" w]
set th [format "%-62s %-9s %-5s %-5s %-5s %s" TEST LIB RUNS PASS FAIL RESULT]
puts $ts "PCIe Gen6 regression : $stamp   BUILD=$BUILD   (TEST-LEVEL SUMMARY)"
puts $ts $th
puts $ts [string repeat - [string length $th]]
foreach k $order {
  foreach {t l} [split $k |] break
  set nf [expr {$TRUNS($k) - $TPASS($k)}]
  set res [expr {$nf == 0 ? "PASS" : "FAIL"}]
  if {$nf == 0} {incr tp} else {incr tf}
  puts $ts [format "%-62s %-9s %-5d %-5d %-5d %s" $t $l $TRUNS($k) $TPASS($k) $nf $res]
}
puts $ts [string repeat - [string length $th]]
puts $ts "TESTS : TOTAL=[expr {$tp+$tf}]  PASS=$tp  FAIL=$tf"
puts $ts "RUNS  : TOTAL=[expr {$npass+$nfail}]  PASS=$npass  FAIL=$nfail   (random tests run with several seeds)"
puts $ts "A test is PASS only if every one of its runs (seeds) passed."
close $ts
puts $fh "TESTS : TOTAL=[expr {$tp+$tf}]  PASS=$tp  FAIL=$tf   (see test_summary.txt)"

#------------------------------------------------------------------------------
# Coverage : merge every test's UCDB, write text + HTML reports
#------------------------------------------------------------------------------
if {$COV} {
  set ucdbs  [glob -nocomplain $regdir/ucdb/*.ucdb]
  set merged "$regdir/merged.ucdb"
  if {[llength $ucdbs] == 0} {
    puts $fh "COVERAGE : no UCDB saved"
  } elseif {[catch {
      vcover merge $merged {*}$ucdbs
      vcover report -file $regdir/coverage_summary.txt $merged
      vcover report -details -file $regdir/coverage_details.txt $merged
      catch {vcover report -html -htmldir $regdir/coverage_html -details $merged}
    } cerr]} {
    puts $fh "COVERAGE : merge/report failed : $cerr"
  } else {
    puts $fh "COVERAGE : merged [llength $ucdbs] UCDBs -> $merged"
    set cf [open $regdir/coverage_summary.txt r]
    while {[gets $cf ln] >= 0} {
      if {[regexp -nocase {(total|covergroup).*coverage.*[0-9.]+%} $ln]} { puts $fh "COVERAGE : [string trim $ln]" }
    }
    close $cf
  }
}
close $fh ; close $csv

echo ""
set fh [open "$regdir/summary.txt" r] ; echo [read $fh] ; close $fh
echo "REGRESSION : results in $regdir"

