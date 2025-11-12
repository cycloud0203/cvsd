# AI Agent Instructions for CVSD HW4: IOTDF Design

## Project Overview
This is a **digital IC design project** for an IoT Data Transformation (IOTDF) module implementing DES-like cryptographic functions. The design flows from RTL to gate-level synthesis to power analysis using industry-standard EDA tools (Synopsys VCS, Design Compiler, PrimeTime).

**Key Architecture**: FSM-based datapath that accepts 128-bit data via 8-bit serial interface, performs one of 4 selectable transformation functions (likely DES-inspired: permutations, S-boxes), and outputs 128-bit results.

## Critical Design Constraints

### Timing & Performance
- **Target clock period**: 6.5ns (153.8 MHz) - defined in `02_SYN/IOTDF_DC.sdc`
- **Technology**: TSMC 0.13µm standard cell library (`slow.db` corner for synthesis)
- The design MUST meet timing at this frequency - any FSM or datapath changes should verify timing closure

### FSM States & Protocol
```verilog
IDLE → LOAD (16 cycles) → COMPUTE (1 cycle) → OUTPUT (1 cycle)
```
- **LOAD state**: Accepts 16 bytes serially (128 bits total) when `in_en=1`
- Module asserts `busy` during LOAD and COMPUTE
- **Critical**: If `in_en` drops during LOAD (counter < 15), FSM resets to IDLE
- Functions selected via `fn_sel[2:0]`: 1=F1, 2=F2, 3=F3, 4=F4

### Incomplete Implementation Alert
⚠️ **The RTL is missing function implementations!** Lines 89-92 in `01_RTL/IOTDF.v` call undefined functions:
```verilog
3'd1: result_reg_next = compute_f1(data_reg);  // NOT DEFINED
3'd2: result_reg_next = compute_f2(data_reg);  // NOT DEFINED
3'd3: result_reg_next = compute_f3(data_reg);  // NOT DEFINED
3'd4: result_reg_next = compute_f4(data_reg);  // NOT DEFINED
```

**Required: FULL DES Implementation** - This is NOT a simplified permutation task:
- **16-round Feistel structure** with round-key schedule (K1→K16 for encrypt, K16→K1 for decrypt)
- **Initial/Final Permutations (IP/FP)**: 64-bit input/output permutations
- **F-function per round**: E-expansion (32→48 bits), XOR with sub-key, 8 S-boxes (6→4 bits each), P-box permutation
- **Key schedule**: PC1, left shifts, PC2 to generate 16 sub-keys from 64-bit key
- **Process 64-bit blocks**: Input 128 bits contains 64-bit data + 64-bit key

**Implementation approach**:
1. Define sub-functions: `initial_permutation`, `final_permutation`, `key_schedule`, `des_round`, `f_function`
2. Use lookup tables from `DES_additional_material/`: S-boxes (S1-S8), P-box, E-expansion, PC1, PC2
3. Implement as combinational `function` blocks within module scope
4. Example: `function [63:0] des_encrypt; input [63:0] data; input [63:0] key; begin /* 16 rounds */ end endfunction`

## Development Workflow

### RTL Simulation (01_RTL/)
```bash
cd 01_RTL
./runall_rtl  # Runs all 4 function tests with pattern1 data
```
- Uses VCS with file list `rtl_01.f`
- Defines: `+define+p1+F1` through `+define+p1+F4` select function & pattern
- Generates `IOTDF_F{1-4}.fsdb` waveforms (use Verdi to view)
- Expected outputs in `00_TESTBED/pattern1_data/f{1-4}.dat`

**Test Coverage**:
- `pattern1`: Provided test vectors with golden outputs (public)
- `pattern2`: You must generate your own test vectors (optional for self-validation)
- **Hidden tests**: Exist and count toward grading! Must pass hidden tests to qualify for P×T×A performance ranking
- Focus on correctness first - hidden test pass is required for synthesis scoring

### Synthesis (02_SYN/)
**You must create `syn.tcl` script** (refer to HW3 for template):
```tcl
# Typical flow:
read_verilog ../01_RTL/IOTDF.v
current_design IOTDF
link
source IOTDF_DC.sdc
compile
write -format verilog -hierarchy -output IOTDF_syn.v
write_sdf -version 2.1 IOTDF_syn.sdf
report_timing > timing.rpt
report_area > area.rpt
```

**Run synthesis**:
```bash
cd 02_SYN
dc_shell -f syn.tcl | tee syn.log
```

**SDC constraints** (`IOTDF_DC.sdc` - PROVIDED, DO NOT MODIFY):
- Clock period: 6.5ns, uncertainty: 0.1ns, latency: 1.0ns
- I/O delays: max 1.0ns, min 0.0ns
- Max fanout: 10
- Operating condition: `slow` corner
- **Modifying these invalidates grading results**

### Gate-Level Simulation (03_GATE/)
```bash
cd 03_GATE
./runall_syn  # Post-synthesis timing simulation
```
- Uses synthesized netlist `IOTDF_syn.v` + SDF delays
- Includes TSMC cell models (`tsmc13_neg.v`)
- Define `+define+SDF` enables SDF annotation

### Power Analysis (06_POWER/)
```tcl
cd 06_POWER
pt_shell -f pt_script.tcl
```
- Reads gate-level netlist, SDF, and FSDB switching activity
- Generates `F1_4.power` report with power breakdown per function

## Common Patterns & Conventions

### Verilog Style
- **Two-process FSM**: Separate combinational (`always @(*)`) and sequential (`always @(posedge clk)`) blocks
- **Default assignments**: Always initialize `_next` signals to avoid latches (line 46-51)
- **No functions defined yet**: You must add `function [127:0] compute_f1` etc. within module scope

### Testbench Patterns
- Pattern selection via compiler defines: `p1`/`p2` (pattern set), `F1`-`F4` (function)
- Pattern paths constructed dynamically: `pattern_file_path` → `func_ans_path`
- **Cycle accurate**: Test expects `valid` pulse exactly when result ready

### File Organization
- `*.f` files: Verilog file lists for compilation
- `runall_*`: Shell scripts executing multiple test scenarios
- DES reference: Excel files with lookup tables (convert to Verilog case/LUT as needed)

## When Modifying RTL

1. **Start with DES algorithm correctness**: Verify 16-round structure, key schedule, S-box lookups before worrying about timing
2. **Always check datapath width**: 128-bit input = 64-bit data + 64-bit key; process correctly
3. **Preserve FSM timing**: Don't add pipeline stages without updating testbench expectations (COMPUTE must be 1 cycle!)
4. **Test all 4+ functions**: Each function has different expected outputs (F1-F4 provided, potentially F5 exists)
5. **Verify synthesis timing**: DES logic is combinationally heavy - watch for long paths through S-boxes and permutations
6. **Hidden test compliance**: Your design will be tested with unseen patterns - ensure general correctness, not just pattern1 fitting

## DES Implementation Tips

### Critical Path Concerns
- **16-round DES in 1 cycle is tight at 6.5ns** - each round ~400ps budget
- Consider optimizing: parallel S-box lookups, minimize mux delays in Feistel structure
- P-box and E-expansion are just wire reordering (zero delay)
- Key schedule can be precomputed or on-the-fly (trade area vs. delay)

### Common Pitfalls
- **Bit ordering**: DES uses big-endian bit numbering (bit 1 = MSB) - verify against test vectors
- **Key parity bits**: 64-bit key has 8 parity bits (every 8th bit) - ignore or handle per spec
- **S-box indexing**: Row (2 bits) + Column (4 bits) from 6-bit input - double-check lookup logic
- **Sub-key order**: Encryption K1→K16, decryption K16→K1 - verify F1 vs F2 behavior

## Quick Reference Commands

```bash
# Compile RTL for F1
vcs -f rtl_01.f -full64 -R +v2k -sverilog +define+p1+F1

# View waveforms (if Verdi available)
verdi -ssf IOTDF_F1.fsdb &

# Check for undefined functions
grep -n "compute_f[1-4]" 01_RTL/IOTDF.v

# Run post-syn sim with timing
vcs -f rtl_03.f -full64 -R +define+SDF+p1+F1 +maxdelays
```

## EDA Tool Environment
**Development on NTUGIEE server required** - all tools pre-configured:
- **VCS**: Verilog simulation with FSDB dump
- **Design Compiler (DC)**: Logic synthesis with TSMC 0.13µm library
- **PrimeTime (PT)**: Power analysis
- **Verdi**: Waveform viewer for debugging

**Server paths** (already in `.synopsys_dc.setup`):
- Library: `/home/raid7_2/course/cvsd/CBDK_IC_Contest/CIC/SynopsysDC/db/slow.db`
- Cell models: `/home/raid7_2/course/cvsd/CBDK_IC_Contest/CIC/Verilog/tsmc13_neg.v`

## Key Files to Understand
- `01_RTL/IOTDF.v` (lines 1-130): Main module - START HERE
- `00_TESTBED/testfixture.v` (lines 1-200): Understand test protocol
- `02_SYN/IOTDF_DC.sdc`: Timing constraints (DO NOT MODIFY)
- `DES_additional_material/`: Reference for implementing compute_f* functions

---
*For questions about DES algorithm specifics, consult course notes `1141_hw4_note-2.pdf` and `1141_hw4.pdf`*
