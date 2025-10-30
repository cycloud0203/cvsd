/********************************************************************
* Filename: testbed.v
* Description:
*     Testbench for RISC-V CPU (HW2 CVSD 2025 Fall)
*********************************************************************/

`timescale 1ns/100ps
`define CYCLE       10.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   120000
`define RST_DELAY   2.0

`ifdef p0
    `define INST_DAT   "../00_TB/PATTERN/p0/inst.dat"
    `define GOLDEN_DAT "../00_TB/PATTERN/p0/data.dat"
    `define STATUS_DAT "../00_TB/PATTERN/p0/status.dat"
`elsif p1
    `define INST_DAT   "../00_TB/PATTERN/p1/inst.dat"
    `define GOLDEN_DAT "../00_TB/PATTERN/p1/data.dat"
    `define STATUS_DAT "../00_TB/PATTERN/p1/status.dat"
`elsif p2
    `define INST_DAT   "../00_TB/PATTERN/p2/inst.dat"
    `define GOLDEN_DAT "../00_TB/PATTERN/p2/data.dat"
    `define STATUS_DAT "../00_TB/PATTERN/p2/status.dat"
`elsif p3
    `define INST_DAT   "../00_TB/PATTERN/p3/inst.dat"
    `define GOLDEN_DAT "../00_TB/PATTERN/p3/data.dat"
    `define STATUS_DAT "../00_TB/PATTERN/p3/status.dat"
`else
    `define INST_DAT   "../00_TB/PATTERN/p0/inst.dat"
    `define GOLDEN_DAT "../00_TB/PATTERN/p0/data.dat"
    `define STATUS_DAT "../00_TB/PATTERN/p0/status.dat"
`endif

// ANSI Color Codes
`define RED     "\033[1;31m"
`define GREEN   "\033[1;32m"
`define YELLOW  "\033[1;33m"
`define RESET   "\033[0m"

module testbed;

    // Clock and Reset
    wire clk;
    wire rst_n;
    
    // Core <-> Memory Interface
    wire            mem_we;
    wire [31:0]     mem_addr;
    wire [31:0]     mem_wdata;
    wire [31:0]     mem_rdata;
    
    // Status Signals
    wire [2:0]      status;
    wire            status_valid;
    
    // Test Control
    integer         cycle_count;
    integer         inst_count;
    reg             test_finish;
    
    // Golden Data
    reg [31:0]      golden_data [0:2047];  // Golden memory content
    reg [2:0]       golden_status [0:1023]; // Golden status sequence
    integer         status_idx;
    
    // =========================================================================
    // Load Golden Data (At time 0)
    // =========================================================================
    initial begin
        // Load golden references for verification
        $readmemb(`GOLDEN_DAT, golden_data);
        $readmemb(`STATUS_DAT, golden_status);
    end
    
    // =========================================================================
    // Load Instruction Memory (Following TA's template timing)
    // =========================================================================
    initial begin
        // Wait for reset to be released (matching TA's template)
        wait (rst_n === 1'b0);
        wait (rst_n === 1'b1);
        
        // Load memory immediately after rst_n goes back to 1
        // (same delta cycle, before next clock edge)
        $readmemb(`INST_DAT, u_data_mem.mem_r);
        
        $display("========================================");
        $display("  Pattern Loaded");
        $display("========================================");
        $display("  Instruction: %s", `INST_DAT);
        $display("  Golden Data: %s", `GOLDEN_DAT);
        $display("  Golden Stat: %s", `STATUS_DAT);
        $display("  First Instruction: %h", u_data_mem.mem_r[0]);
        $display("  Second Instruction: %h", u_data_mem.mem_r[1]);
        $display("========================================");
    end
    
    // =========================================================================
    // Clock Generator Module
    // =========================================================================
    clk_gen u_clk_gen (
        .clk   (clk),
        .rst_n (rst_n)
    );
    
    // =========================================================================
    // Module Instantiation
    // =========================================================================
    core u_core (
        .i_clk          (clk),
        .i_rst_n        (rst_n),
        .o_status       (status),
        .o_status_valid (status_valid),
        .o_we           (mem_we),
        .o_addr         (mem_addr),
        .o_wdata        (mem_wdata),
        .i_rdata        (mem_rdata)
    );

    data_mem u_data_mem (
        .i_clk          (clk),
        .i_rst_n        (rst_n),
        .i_we           (mem_we),
        .i_addr         (mem_addr),
        .i_wdata        (mem_wdata),
        .o_rdata        (mem_rdata)
    );

    // =========================================================================
    // Waveform Dumping
    // =========================================================================
    initial begin
        $fsdbDumpfile("core.fsdb");
        $fsdbDumpvars(0, testbed, "+mda");
        $fsdbDumpMDA();
    end

    // =========================================================================
    // Initialization and Early Debug
    // =========================================================================
    initial begin
        test_finish = 1'b0;
        cycle_count = 0;
        inst_count = 0;
        status_idx = 0;
        
        // Wait for reset to be released
        wait (rst_n === 1'b0);
        $display("\n[%0t] Reset asserted", $time);
        wait (rst_n === 1'b1);
        $display("[%0t] Reset released, starting execution", $time);
        $display("Core initial state:");
        $display("  o_addr  = %04d", mem_addr);
        $display("  i_rdata = %b", mem_rdata);
        $display("  mem[0]  = %d", u_data_mem.mem_r[0]);
        $display("  mem[1]  = %d", u_data_mem.mem_r[1]);
        $display("");
    end

    // =========================================================================
    // Cycle Counter
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
        end
    end

    // =========================================================================
    // Status Monitor and Checker
    // =========================================================================
    always @(negedge clk) begin
        if (rst_n && status_valid) begin
            // Check status against golden
            if (status !== golden_status[status_idx]) begin
                $display("%s[ERROR]%s Status mismatch at instruction %d:", `RED, `RESET, status_idx+1);
                $display("        Expected: %d, Got: %d", golden_status[status_idx], status);
            end else begin
                `ifdef VERBOSE
                    $display("%s[PASS]%s Inst %4d: Status = %d", `GREEN, `RESET, status_idx+1, status);
                `endif
            end
            status_idx = status_idx + 1;
            inst_count = inst_count + 1;
            
            case (status)
                `R_TYPE: begin
                    `ifndef VERBOSE
                        $display("[Cycle %4d] Inst %4d: R-Type expected: %d got: %d", cycle_count, inst_count, golden_status[status_idx-1], status);
                    `endif
                end
                `I_TYPE: begin
                    `ifndef VERBOSE
                        $display("[Cycle %4d] Inst %4d: I-Type expected: %d got: %d", cycle_count, inst_count, golden_status[status_idx-1], status);
                    `endif
                end
                `S_TYPE: begin	
                    `ifndef VERBOSE
                        $display("[Cycle %4d] Inst %4d: S-Type expected: %d got: %d", cycle_count, inst_count, golden_status[status_idx-1], status);
                    `endif
                end
                `B_TYPE: begin
                    `ifndef VERBOSE
                        $display("[Cycle %4d] Inst %4d: B-Type expected: %d got: %d", cycle_count, inst_count, golden_status[status_idx-1], status);
                    `endif
                end
                `U_TYPE: begin
                    `ifndef VERBOSE
                        $display("[Cycle %4d] Inst %4d: U-Type expected: %d got: %d", cycle_count, inst_count, golden_status[status_idx-1], status);
                    `endif
                end
                `INVALID_TYPE: begin
                    // Check if INVALID was expected
                    if (golden_status[status_idx-1] == `INVALID_TYPE) begin
                        $display("%s[Cycle %4d] Inst %4d: INVALID (Expected)%s", `GREEN, cycle_count, inst_count, `RESET);
                        $display("========================================");
                        $display("%s  Invalid operation detected as expected%s", `GREEN, `RESET);
                    end else begin
                        $display("%s[Cycle %4d] Inst %4d: INVALID (Unexpected)%s", `RED, cycle_count, inst_count, `RESET);
                        $display("========================================");
                        $display("%s  Unexpected invalid operation!%s", `RED, `RESET);
                    end
                    $display("========================================");
                    #(`CYCLE * 2);
                    test_finish = 1'b1;
                    check_results();
                    $finish;
                end
                `EOF_TYPE: begin
                    $display("%s[Cycle %4d] Inst %4d: EOF - Program Complete%s", `GREEN, cycle_count, inst_count, `RESET);
                    $display("========================================");
                    $display("%s  Execution Completed%s", `GREEN, `RESET);
                    $display("  Total Instructions: %d", inst_count);
                    $display("  Total Cycles:       %d", cycle_count);
                    $display("  CPI:                %.2f", cycle_count * 1.0 / inst_count);
                    $display("========================================");
                    #(`CYCLE * 2);
                    test_finish = 1'b1;
                    check_results();
                    $finish;
                end
                default: begin
                    $display("%s[Cycle %4d] Inst %4d: Unknown Status: %d%s", `YELLOW, cycle_count, inst_count, status, `RESET);
                end
            endcase
        end
    end

    // =========================================================================
    // Memory Transaction Monitor (for debugging)
    // =========================================================================
    `ifdef DEBUG
    always @(posedge clk) begin
        if (rst_n) begin
            if (mem_we) begin
                $display("[Cycle %4d] MEM WRITE: Addr=%04d (word %04d), Data=%d, PC=%04d", 
                         cycle_count, mem_addr, mem_addr[12:2], mem_wdata, u_core.pc_r);
            end
            `ifdef VERBOSE
            else begin
                $display("[Cycle %4d] MEM READ:  Addr=%04d (word %04d), Data=%d", 
                         cycle_count, mem_addr, mem_addr[12:2], mem_rdata);
            end
            `endif
        end
    end
    `endif
    
    // =========================================================================
    // Register Dump at End (for debugging)
    // =========================================================================
    `ifdef DEBUG
    always @(posedge clk) begin
        if (rst_n && status_valid && (status == `INVALID_TYPE || status == `EOF_TYPE)) begin
            #1; // Small delay
            $display("\n========================================");
            $display("  Integer Register Dump");
            $display("========================================");
            $display("  x0  = 0x%08h    x1  = 0x%08h", u_core.int_registers[0], u_core.int_registers[1]);
            $display("  x2  = 0x%08h    x3  = 0x%08h", u_core.int_registers[2], u_core.int_registers[3]);
            $display("  x4  = 0x%08h    x5  = 0x%08h", u_core.int_registers[4], u_core.int_registers[5]);
            $display("  x6  = 0x%08h    x7  = 0x%08h", u_core.int_registers[6], u_core.int_registers[7]);
            $display("  x8  = 0x%08h    x10 = 0x%08h", u_core.int_registers[8], u_core.int_registers[10]);
            $display("  x11 = 0x%08h    x12 = 0x%08h", u_core.int_registers[11], u_core.int_registers[12]);
            $display("  x13 = 0x%08h    x14 = 0x%08h", u_core.int_registers[13], u_core.int_registers[14]);
            $display("  x15 = 0x%08h    x16 = 0x%08h", u_core.int_registers[15], u_core.int_registers[16]);
            $display("  x17 = 0x%08h", u_core.int_registers[17]);
            $display("\n  FP Register Dump");
            $display("========================================");
            $display("  f0  = 0x%08h    f1  = 0x%08h", u_core.float_registers[0], u_core.float_registers[1]);
            $display("  f2  = 0x%08h    f3  = 0x%08h", u_core.float_registers[2], u_core.float_registers[3]);
        end
    end
    `endif

    // =========================================================================
    // Result Verification Task
    // =========================================================================
    task check_results;
        integer i;
        integer errors;
        integer data_errors;
        begin
            errors = 0;
            data_errors = 0;
            
            $display("\n========================================");
            $display("  Verifying Results");
            $display("========================================");
            
            // Check data memory (addresses 4096-8191 = indices 1024-2047)
            $display("\nChecking Data Memory...");
            for (i = 1024; i < 2048; i = i + 1) begin
                if (u_data_mem.mem_r[i] !== golden_data[i]) begin
                    $display("%s[ERROR]%s Mem[%04d] (Addr %04d): Expected = %d, Got = %d", 
                             `RED, `RESET, i, i * 4, golden_data[i], u_data_mem.mem_r[i]);
                    data_errors = data_errors + 1;
                    errors = errors + 1;
                    
                    // Limit error messages
                    if (data_errors >= 20) begin
                        $display("%s... (too many errors, stopping data error messages)%s", `YELLOW, `RESET);
                        i = 2048; // break loop
                    end
                end
            end
            
            if (data_errors == 0) begin
                $display("%sData Memory Check: PASS (All %d words correct)%s", `GREEN, 1024, `RESET);
            end else begin
                $display("%sData Memory Check: FAIL (%d errors out of %d words)%s", `RED, data_errors, 1024, `RESET);
            end
            
            // Summary
            $display("\n========================================");
            $display("  Test Summary");
            $display("========================================");
            $display("  Total Instructions:  %d", inst_count);
            $display("  Total Cycles:        %d", cycle_count);
            $display("  Data Errors:         %d", data_errors);
            
            if (errors == 0) begin
                $display("\n%s>>> TEST PASSED! <<<%s", `GREEN, `RESET);
            end else begin
                $display("\n%s>>> TEST FAILED! (Total %d errors) <<<%s", `RED, errors, `RESET);
            end
            $display("========================================\n");
        end
    endtask

endmodule

// =============================================================================
// Clock Generator Module (Separate module like reference testbench)
// =============================================================================
module clk_gen (
    output reg clk,
    output reg rst_n
);

    // Clock generation
    initial clk = 1'b0;
    always #(`HCYCLE) clk = ~clk;

    // Reset generation with proper timing
    initial begin
        rst_n = 1'b1;                           // Start high
        #(0.25 * `CYCLE);                       // 0.25 cycle delay
        rst_n = 1'b0;                           // Assert reset
        #((`RST_DELAY - 0.25) * `CYCLE);        // Hold for RST_DELAY
        rst_n = 1'b1;                           // Release reset
        #(`MAX_CYCLE * `CYCLE);                 // Timeout check
        $display("\n========================================");
        $display("%s  ERROR: Timeout!%s", `RED, `RESET);
        $display("  Exceeded maximum cycles: %d", `MAX_CYCLE);
        $display("========================================");
        $finish;
    end

endmodule
