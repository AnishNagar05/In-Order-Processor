module monitor #(
    parameter CHANNELS = 1,

    parameter SPIKE_DPI = 1,
    parameter RISCV_FORMAL = 1,
    parameter UNKNOWN_SIGNALS = 1,
    parameter COMMIT_LOG = 1,
    parameter ROI = 1
)(
    mon_itf mon_itf
);
    // Check for magic halt instructions
    function bit is_halt(input logic [31:0] inst);
        is_halt = inst inside {32'h00000063, 32'h0000006f, 32'hF0002013};
    endfunction

    always @(posedge mon_itf.clk iff !mon_itf.rst) begin
        for (int unsigned channel = 0; channel < CHANNELS; channel++) begin
            if (mon_itf.valid[channel] && is_halt(mon_itf.inst[channel])) begin
                mon_itf.halt <= 1'b1;
            end
        end
    end

/********************************************************************
 ********************** Spike DPI Checker ***************************
 ********************************************************************/
    if (SPIKE_DPI) begin
        spike_dpi_checker spike_dpi_checker(
            .mon_itf(mon_itf)
        );
    end


/********************************************************************
 ********************** RISCV Formal Checker ************************
 ********************************************************************/
    if (RISCV_FORMAL) begin
        riscv_formal_checker riscv_formal_checker(
            .mon_itf(mon_itf)
        );
    end


/********************************************************************
 ********************** Unknown signals Checker *********************
 ********************************************************************/
    if (UNKNOWN_SIGNALS) begin
        unknown_signals_checker unknown_signals_checker(
            .mon_itf(mon_itf)
        );
    end

    
/********************************************************************
 ********************** Commit Log Printer **************************
 ********************************************************************/
    if (COMMIT_LOG) begin
        commit_log_printer commit_log_printer(
            .mon_itf(mon_itf)
        );
    end

/********************************************************************
 ********************** Region of Interest monitor ******************
 ********************************************************************/
    if (ROI) begin
        roi_monitor roi_monitor(
            .mon_itf(mon_itf)
        );
    end

endmodule

module spike_dpi_checker #(
    parameter CHANNELS = 1
)(
    mon_itf mon_itf
);
    typedef longint unsigned order_t;

    typedef struct packed {
        bit [31:0] mem_wdata;   
        bit [31:0] mem_rdata;   
        bit [31:0] mem_wmask;   
        bit [31:0] mem_rmask;  
        bit [31:0] mem_addr;     

        bit [31:0] pc_wdata;     
        bit [31:0] pc_rdata;     

        bit [31:0] rd_wdata;     
        bit [31:0] rd_addr;      

        bit [31:0] rs2_rdata;    
        bit [31:0] rs1_rdata;    
        bit [31:0] rs2_addr;     
        bit [31:0] rs1_addr;     

        bit [31:0] trapped;      
        bit [31:0] inst;         
    } dut_rvfi_t;

    typedef struct {
        int unsigned channel;
        order_t      order;
        dut_rvfi_t   rvfi;
    } dut_retire_t;

    typedef struct packed {
        bit inst;

        bit rs1_addr;
        bit rs1_rdata;

        bit rs2_addr;
        bit rs2_rdata;

        bit rd_addr;
        bit rd_wdata;

        bit pc_rdata;
        bit pc_wdata;

        bit mem_addr;
        bit mem_rmask;
        bit mem_wmask;
        bit mem_rdata;
        bit mem_wdata;
    } diff_t;


    dut_rvfi_t             spike_rvfi;
    order_t                spike_dpi_order;
    dut_retire_t pending   [order_t];

    import "DPI-C" function void spike_dpi_init(string mem_space, string elf_file);
    import "DPI-C" function int unsigned spike_dpi_fini();
    import "DPI-C" function int unsigned spike_dpi_step(output dut_rvfi_t r);
    import "DPI-C" function string spike_dpi_get_dasm();

    initial begin
        automatic string elf_file;
        if (!$value$plusargs("PROGRAM_ELF=%s", elf_file)) begin
            $fatal(1, "[spike_dpi_checker] +PROGRAM_ELF=<elf> not provided");
        end
        $display("[spike_dpi_checker] Using ELF file %s", elf_file);
        spike_dpi_order = '0;
        mon_itf.error = 1'b0;
        pending.delete(); 
        spike_dpi_init("-m0xaaaaa000:0x55556000", elf_file);
    end

    final begin
        automatic int unsigned retval;
        retval = spike_dpi_fini();
        $display("[spike_dpi_checker] spike_dpi_fini() returned %0d", retval);
    end

    function automatic bit has_masked_mismatch(
        input bit [3:0]  mask,
        input bit [31:0] dut_data,
        input bit [31:0] spike_data
    );
        bit mismatch;
        mismatch = 1'b0;
        for (int i = 0; i < 4; i++) begin
            if (mask[i] && (dut_data[i*8 +: 8] != spike_data[i*8 +: 8])) begin
                mismatch = 1'b1;
            end
        end
        return mismatch;
    endfunction

    function automatic dut_rvfi_t snapshot_dut(input int unsigned ch);
        dut_rvfi_t d;

        d.inst       = mon_itf.inst      [ch];

        d.rs1_addr   = {27'b0, mon_itf.rs1_addr  [ch]};
        d.rs1_rdata  = mon_itf.rs1_rdata [ch];

        d.rs2_addr   = {27'b0, mon_itf.rs2_addr  [ch]};
        d.rs2_rdata  = mon_itf.rs2_rdata [ch];

        d.rd_addr    = {27'b0, mon_itf.rd_addr   [ch]};
        d.rd_wdata   = mon_itf.rd_wdata  [ch];

        d.pc_rdata   = mon_itf.pc_rdata  [ch];
        d.pc_wdata   = mon_itf.pc_wdata  [ch];

        d.mem_addr   = mon_itf.mem_addr  [ch];
        d.mem_rmask  = {28'b0, mon_itf.mem_rmask [ch]};
        d.mem_wmask  = {28'b0, mon_itf.mem_wmask [ch]};
        d.mem_rdata  = mon_itf.mem_rdata [ch];
        d.mem_wdata  = mon_itf.mem_wdata [ch];

        return d;
    endfunction

    function automatic diff_t compute_diff(
        input dut_rvfi_t           d,
        input dut_rvfi_t           s
    );
        diff_t diff;
        diff = '0;

        diff.inst      = (d.inst != s.inst);

        diff.rs1_addr  = |s.rs1_addr[4:0] ?
                        (d.rs1_addr[4:0] != s.rs1_addr[4:0]) : 1'b0;

        diff.rs1_rdata = |s.rs1_addr[4:0] ?
                        (d.rs1_rdata != s.rs1_rdata) : 1'b0;

        diff.rs2_addr  = |s.rs2_addr[4:0] ?
                        (d.rs2_addr[4:0] != s.rs2_addr[4:0]) : 1'b0;

        diff.rs2_rdata = |s.rs2_addr[4:0] ?
                        (d.rs2_rdata != s.rs2_rdata) : 1'b0;

        diff.rd_addr   = (d.rd_addr[4:0] != s.rd_addr[4:0]);

        diff.rd_wdata  = |s.rd_addr[4:0] ?
                        (d.rd_wdata != s.rd_wdata) : 1'b0;

        diff.pc_rdata  = (d.pc_rdata != s.pc_rdata);
        diff.pc_wdata  = (d.pc_wdata != s.pc_wdata);

        diff.mem_rmask = (d.mem_rmask[3:0] != s.mem_rmask[3:0]);
        diff.mem_wmask = (d.mem_wmask[3:0] != s.mem_wmask[3:0]);

        if (s.mem_rmask[3:0] != 4'd0) begin
            diff.mem_addr  = ({d.mem_addr[31:2], 2'b00} != s.mem_addr);
            diff.mem_rdata = has_masked_mismatch(s.mem_rmask[3:0],
                                                d.mem_rdata,
                                                s.mem_rdata);
        end

        if (s.mem_wmask[3:0] != 4'd0) begin
            diff.mem_addr  = ({d.mem_addr[31:2], 2'b00} != s.mem_addr);
            diff.mem_wdata = has_masked_mismatch(s.mem_wmask[3:0],
                                                d.mem_wdata,
                                                s.mem_wdata);
        end

        return diff;
    endfunction

    function automatic bit any_diff(input diff_t d);
        return d.inst      ||
            d.rs1_addr   || d.rs1_rdata ||
            d.rs2_addr   || d.rs2_rdata ||
            d.rd_addr    || d.rd_wdata  ||
            d.pc_rdata   || d.pc_wdata  ||
            d.mem_addr   ||
            d.mem_rmask  || d.mem_wmask ||
            d.mem_rdata  || d.mem_wdata;
    endfunction

    task automatic print_mismatch(
        input dut_retire_t          r,
        input dut_rvfi_t            s,
        input diff_t                diff
    );
        string dasm;
        dasm = spike_dpi_get_dasm();

        $display("");
        $error("Spike Monitor Error at time %0t channel %0d order %0d",
            $time, r.channel, r.order);
        $display("-------begin spike mismatch--------");
        $display("%010s %4s %9s %9s", "signal    ", "diff", "      dut", "    spike");

        $display("%010s %4s h%08x h%08x %s",
                "inst      ", diff.inst      ? "--->" : "    ",
                r.rvfi.inst, s.inst, dasm);

        $display("%010s %4s      %02d      %02d",
                "rs1_addr  ", diff.rs1_addr  ? "--->" : "    ",
                r.rvfi.rs1_addr, s.rs1_addr);

        $display("%010s %4s h%08x h%08x",
                "rs1_rdata ", diff.rs1_rdata ? "--->" : "    ",
                r.rvfi.rs1_rdata, s.rs1_rdata);

        $display("%010s %4s      %02d      %02d",
                "rs2_addr  ", diff.rs2_addr  ? "--->" : "    ",
                r.rvfi.rs2_addr, s.rs2_addr);

        $display("%010s %4s h%08x h%08x",
                "rs2_rdata ", diff.rs2_rdata ? "--->" : "    ",
                r.rvfi.rs2_rdata, s.rs2_rdata);

        $display("%010s %4s      %02d      %02d",
                "rd_addr   ", diff.rd_addr   ? "--->" : "    ",
                r.rvfi.rd_addr, s.rd_addr);

        $display("%010s %4s h%08x h%08x",
                "rd_wdata  ", diff.rd_wdata  ? "--->" : "    ",
                r.rvfi.rd_wdata, s.rd_wdata);

        $display("%010s %4s h%08x h%08x",
                "pc_rdata  ", diff.pc_rdata  ? "--->" : "    ",
                r.rvfi.pc_rdata, s.pc_rdata);

        $display("%010s %4s h%08x h%08x",
                "pc_wdata  ", diff.pc_wdata  ? "--->" : "    ",
                r.rvfi.pc_wdata, s.pc_wdata);

        $display("%010s %4s h%08x h%08x",
                "mem_addr  ", diff.mem_addr  ? "--->" : "    ",
                r.rvfi.mem_addr, s.mem_addr);

        $display("%010s %4s   b%04b   b%04b",
                "mem_rmask ", diff.mem_rmask ? "--->" : "    ",
                r.rvfi.mem_rmask, s.mem_rmask[3:0]);

        $display("%010s %4s   b%04b   b%04b",
                "mem_wmask ", diff.mem_wmask ? "--->" : "    ",
                r.rvfi.mem_wmask, s.mem_wmask[3:0]);

        $display("%010s %4s h%08x h%08x",
                "mem_rdata ", diff.mem_rdata ? "--->" : "    ",
                r.rvfi.mem_rdata, s.mem_rdata);

        $display("%010s %4s h%08x h%08x",
                "mem_wdata ", diff.mem_wdata ? "--->" : "    ",
                r.rvfi.mem_wdata, s.mem_wdata);

        $display("-------end spike mismatch----------");
        $display("");
    endtask

    always @(posedge mon_itf.clk iff !mon_itf.rst) begin
        // Capture phase
        for (int unsigned ch = 0; ch < CHANNELS; ch++) begin
            if (mon_itf.valid[ch]) begin
                dut_retire_t r;
                r.channel = ch;
                r.order   = order_t'(mon_itf.order[ch]);
                r.rvfi    = snapshot_dut(ch);

                if (pending.exists(r.order)) begin
                    $display("");
                    $error("Spike Monitor Error at time %0t channel %0d order %0d",
                            $time, r.channel, r.order);
                    $display("Duplicate order %0d (already pending from channel %0d).",
                                r.order, pending[r.order].channel);
                    $display("");
                    mon_itf.error <= 1'b1;
                end

                pending[r.order] = r;
            end
        end

        // Compare phase
        while (pending.num() > 0) begin
            order_t      min_order;
            diff_t       diff;
            int unsigned rc;
            dut_retire_t r;

            if (!pending.first(min_order)) break;

            if (min_order != spike_dpi_order) begin
                $display("");
                $error("Spike Monitor Error at time %0t order %0d",
                        $time, min_order);
                $display("Order mismatch: expected %0d, got %0d.",
                            spike_dpi_order, min_order);
                $display("");
                mon_itf.error <= 1'b1;
                break;
            end

            r = pending[min_order];

            rc = spike_dpi_step(spike_rvfi);

            if (rc) begin
                $display("");
                $error("Spike Monitor Error at time %0t channel %0d order %0d",
                        $time, r.channel, r.order);
                $display("spike_dpi_step() failed (returned %0d)", rc);
                $display("");
                mon_itf.error <= 1'b1;
            end

            diff = compute_diff(r.rvfi, spike_rvfi);

            if (spike_rvfi.trapped) begin
                string dasm;
                dasm = spike_dpi_get_dasm();
                $display("");
                $error("Spike Monitor Error at time %0t channel %0d order %0d",
                        $time, r.channel, r.order);
                $display("Trapped at pc x%08x inst x%08x dasm %s",
                            spike_rvfi.pc_rdata, spike_rvfi.inst, dasm);
                $display("");
                mon_itf.error <= 1'b1;
            end
            else if (any_diff(diff)) begin
                print_mismatch(r, spike_rvfi, diff);
                mon_itf.error <= 1'b1;
            end

            pending.delete(min_order);
            spike_dpi_order <= spike_dpi_order + 1;
        end

        // Sanity limit
        if (pending.num() > 1024) begin
            $fatal(1, "[spike_dpi_checker] Too many pending instructions, RVFI may be broken");
        end
    end    
endmodule


module riscv_formal_checker #(
    parameter CHANNELS = 1
)(
    mon_itf mon_itf
);
    logic [CHANNELS-1:0]         rvfi_valid;
    logic [CHANNELS-1:0][63:0]   rvfi_order;
    logic [CHANNELS-1:0][31:0]   rvfi_insn;
    logic [CHANNELS-1:0]         rvfi_trap      = '0;
    logic [CHANNELS-1:0]         rvfi_halt;
    logic [CHANNELS-1:0]         rvfi_intr      = '0;
    logic [CHANNELS-1:0][1:0]    rvfi_mode      = '0;
    logic [CHANNELS-1:0][4:0]    rvfi_rs1_addr;
    logic [CHANNELS-1:0][4:0]    rvfi_rs2_addr;
    logic [CHANNELS-1:0][31:0]   rvfi_rs1_rdata;
    logic [CHANNELS-1:0][31:0]   rvfi_rs2_rdata;
    logic [CHANNELS-1:0][4:0]    rvfi_rd_addr;
    logic [CHANNELS-1:0][31:0]   rvfi_rd_wdata;
    logic [CHANNELS-1:0][31:0]   rvfi_pc_rdata;
    logic [CHANNELS-1:0][31:0]   rvfi_pc_wdata;
    logic [CHANNELS-1:0][31:0]   rvfi_mem_addr;
    logic [CHANNELS-1:0][3:0]    rvfi_mem_rmask;
    logic [CHANNELS-1:0][3:0]    rvfi_mem_wmask;
    logic [CHANNELS-1:0][31:0]   rvfi_mem_rdata;
    logic [CHANNELS-1:0][31:0]   rvfi_mem_wdata;
    logic [CHANNELS-1:0]         rvfi_mem_extamo = '0;

    assign rvfi_halt = {CHANNELS{mon_itf.halt}};

    generate
    for (genvar ch = 0; ch < CHANNELS; ch++) begin : gen_rvfi
        assign rvfi_valid   [ch]  = mon_itf.valid    [ch];
        assign rvfi_order   [ch]  = mon_itf.order    [ch];
        assign rvfi_insn    [ch]  = mon_itf.inst     [ch];

        assign rvfi_rs1_addr[ch]  = mon_itf.rs1_addr [ch];
        assign rvfi_rs2_addr[ch]  = mon_itf.rs2_addr [ch];
        assign rvfi_rs1_rdata[ch] = (|mon_itf.rs1_addr[ch]) ? mon_itf.rs1_rdata[ch] : '0;
        assign rvfi_rs2_rdata[ch] = (|mon_itf.rs2_addr[ch]) ? mon_itf.rs2_rdata[ch] : '0;
        assign rvfi_rd_addr [ch]  = mon_itf.rd_addr  [ch];
        assign rvfi_rd_wdata[ch]  = (|mon_itf.rd_addr[ch]) ? mon_itf.rd_wdata[ch] : '0;

        assign rvfi_pc_rdata[ch]  = mon_itf.pc_rdata [ch];
        assign rvfi_pc_wdata[ch]  = mon_itf.pc_wdata [ch];

        assign rvfi_mem_addr [ch] = {mon_itf.mem_addr[ch][31:2], 2'b00};
        assign rvfi_mem_rmask[ch] = mon_itf.mem_rmask[ch];
        assign rvfi_mem_wmask[ch] = mon_itf.mem_wmask[ch];
        assign rvfi_mem_rdata[ch] = mon_itf.mem_rdata[ch];
        assign rvfi_mem_wdata[ch] = mon_itf.mem_wdata[ch];
    end
    endgenerate

    logic [15:0] errcode;

    riscv_formal_monitor_rv32imc monitor(
        .clock          (mon_itf.clk),
        .reset          (mon_itf.rst),

        .rvfi_valid     (rvfi_valid),
        .rvfi_order     (rvfi_order),
        .rvfi_insn      (rvfi_insn),
        .rvfi_trap      (rvfi_trap),
        .rvfi_halt      (rvfi_halt),
        .rvfi_intr      (rvfi_intr),
        .rvfi_mode      (rvfi_mode),
        .rvfi_rs1_addr  (rvfi_rs1_addr),
        .rvfi_rs2_addr  (rvfi_rs2_addr),
        .rvfi_rs1_rdata (rvfi_rs1_rdata),
        .rvfi_rs2_rdata (rvfi_rs2_rdata),
        .rvfi_rd_addr   (rvfi_rd_addr),
        .rvfi_rd_wdata  (rvfi_rd_wdata),
        .rvfi_pc_rdata  (rvfi_pc_rdata),
        .rvfi_pc_wdata  (rvfi_pc_wdata),
        .rvfi_mem_addr  (rvfi_mem_addr),
        .rvfi_mem_rmask (rvfi_mem_rmask),
        .rvfi_mem_wmask (rvfi_mem_wmask),
        .rvfi_mem_rdata (rvfi_mem_rdata),
        .rvfi_mem_wdata (rvfi_mem_wdata),
        .rvfi_mem_extamo(rvfi_mem_extamo),

        .errcode        (errcode)
    );

    always @(posedge mon_itf.clk iff !mon_itf.rst) begin
        if (errcode != '0) begin
            $error("RVFI Monitor Error");
            mon_itf.error <= 1'b1;
        end
    end
endmodule

module unknown_signals_checker #(
    parameter CHANNELS = 1
)(
    mon_itf mon_itf
);
    `define RVFI_CHECK_NO_X(_cond, _sig, _ch, _name)                                \
    if (_cond) begin                                                            \
        if ($isunknown(_sig)) begin                                             \
            $error("RVFI Interface Error (ch %0d): %s contains 'x at time %0t", \
                    _ch, _name, $time);                                         \
            mon_itf.error <= 1'b1;                                              \
        end                                                                     \
    end

    generate
        for (genvar channel = 0; channel < CHANNELS; channel++) begin : x_detection    
            always @(posedge mon_itf.clk iff !mon_itf.rst) begin
                `RVFI_CHECK_NO_X(1'b1, mon_itf.valid[channel], channel, "valid")

                if (mon_itf.valid[channel]) begin
                    `RVFI_CHECK_NO_X(1'b1, mon_itf.order    [channel], channel, "order")
                    `RVFI_CHECK_NO_X(1'b1, mon_itf.inst     [channel], channel, "inst")
                    `RVFI_CHECK_NO_X(1'b1, mon_itf.rs1_addr [channel], channel, "rs1_addr")
                    `RVFI_CHECK_NO_X(1'b1, mon_itf.rs2_addr [channel], channel, "rs2_addr")
                    `RVFI_CHECK_NO_X(1'b1, mon_itf.rd_addr  [channel], channel, "rd_addr")
                    `RVFI_CHECK_NO_X(1'b1, mon_itf.pc_rdata [channel], channel, "pc_rdata")
                    `RVFI_CHECK_NO_X(1'b1, mon_itf.pc_wdata [channel], channel, "pc_wdata")
                    `RVFI_CHECK_NO_X(1'b1, mon_itf.mem_rmask[channel], channel, "mem_rmask")
                    `RVFI_CHECK_NO_X(1'b1, mon_itf.mem_wmask[channel], channel, "mem_wmask")

                    `RVFI_CHECK_NO_X(|mon_itf.rs1_addr[channel],
                                    mon_itf.rs1_rdata[channel],
                                    channel, "rs1_rdata")

                    `RVFI_CHECK_NO_X(|mon_itf.rs2_addr[channel],
                                    mon_itf.rs2_rdata[channel],
                                    channel, "rs2_rdata")

                    `RVFI_CHECK_NO_X(|mon_itf.rd_addr[channel],
                                    mon_itf.rd_wdata[channel],
                                    channel, "rd_wdata")

                    `RVFI_CHECK_NO_X(|mon_itf.mem_rmask[channel] || |mon_itf.mem_wmask[channel],
                                    mon_itf.mem_addr[channel],
                                    channel, "mem_addr")

                    if (|mon_itf.mem_rmask[channel]) begin
                        for (int i = 0; i < 4; i++) begin
                            if (mon_itf.mem_rmask[channel][i]) begin
                                if ($isunknown(mon_itf.mem_rdata[channel][i*8 +: 8])) begin
                                    $error("RVFI Interface Error (ch %0d): mem_rdata[%0d] contains 'x at time %0t",
                                        channel, i, $time);
                                    mon_itf.error <= 1'b1;
                                end
                            end
                        end
                    end

                    if (|mon_itf.mem_wmask[channel]) begin
                        for (int i = 0; i < 4; i++) begin
                            if (mon_itf.mem_wmask[channel][i]) begin
                                if ($isunknown(mon_itf.mem_wdata[channel][i*8 +: 8])) begin
                                    $error("RVFI Interface Error (ch %0d): mem_wdata[%0d] contains 'x at time %0t",
                                        channel, i, $time);
                                    mon_itf.error <= 1'b1;
                                end
                            end
                        end
                    end
                end
            end
        end
    endgenerate
endmodule

module commit_log_printer #(
    parameter CHANNELS = 1
)(
    mon_itf mon_itf
);
    typedef struct {
        int unsigned       channel;
        longint unsigned   order;
    } commit_t;

    int commit_fd;
    int commit_frequency;
    initial begin
        commit_fd = $fopen("commit.log", "w");
        if (commit_fd == 0) begin
            $fatal(1, "[commit_log_printer] Failed to open commit log 'commit.log'");
        end

        if (!$value$plusargs("COMMIT_LOG_FREQUENCY=%d", commit_frequency)) begin
            $fatal(1, "[commit_log_printer] +COMMIT_LOG_FREQUENCY=<frequency> not provided");
        end
    end

    final begin
        if (commit_fd != 0) begin
            $fclose(commit_fd);
        end
    end

    function automatic int first_set_bit_4(input logic [3:0] mask);
        for (int i = 0; i < 4; i++) begin
            if (mask[i]) return i;
        end
        return 0;
    endfunction

    function automatic int count_ones_4(input logic [3:0] mask);
        int cnt = 0;
        for (int i = 0; i < 4; i++) begin
            if (mask[i]) cnt++;
        end
        return cnt;
    endfunction

    always @(posedge mon_itf.clk iff !mon_itf.rst) begin
        if (!mon_itf.halt) begin
            commit_t s[$:CHANNELS];
            commit_t sp;
    
            for (int unsigned channel = 0; channel < CHANNELS; channel++) begin
                if (mon_itf.valid[channel]) begin
                    sp.channel = channel;
                    sp.order   = mon_itf.order[channel];
                    s.push_front(sp);
                end
            end
    
            if (s.size() != 0) begin
                s.rsort with (item.order);
            end
    
            while (s.size() != 0) begin
                automatic int channel;
                automatic int idx_first;
                automatic int ones;
    
                sp      = s.pop_back();
                channel = sp.channel;
    
                if (mon_itf.order[channel] % commit_frequency == 0) begin
                    $display("dut commit No.%0d, rd_s: x%02d, rd: 0x%08h",
                             mon_itf.order[channel],
                             mon_itf.rd_addr[channel],
                             |mon_itf.rd_addr[channel] ? mon_itf.rd_wdata[channel] : 32'd0);
                end
    
                if (mon_itf.inst[channel][1:0] == 2'b11) begin
                    // 32-bit instruction
                    $fwrite(commit_fd,
                            "core   0: 3 0x%08h (0x%08h)",
                            mon_itf.pc_rdata[channel],
                            mon_itf.inst[channel]);
                end
                else begin
                    // 16-bit compressed instruction
                    $fwrite(commit_fd,
                            "core   0: 3 0x%08h (0x%04h)",
                            mon_itf.pc_rdata[channel],
                            mon_itf.inst[channel][15:0]);
                end
    
                // RD
                if (|mon_itf.rd_addr[channel]) begin
                    if (mon_itf.rd_addr[channel] < 10)
                        $fwrite(commit_fd, " x%0d  ", mon_itf.rd_addr[channel]);
                    else
                        $fwrite(commit_fd, " x%0d ", mon_itf.rd_addr[channel]);
    
                    $fwrite(commit_fd, "0x%08h", mon_itf.rd_wdata[channel]);
                end
    
                // MEM_R
                if (|mon_itf.mem_rmask[channel]) begin
                    idx_first = first_set_bit_4(mon_itf.mem_rmask[channel]);
                    $fwrite(commit_fd, " mem 0x%08h",
                            {mon_itf.mem_addr[channel][31:2], 2'b00} + idx_first);
                end
    
                // MEM_W
                if (|mon_itf.mem_wmask[channel]) begin
                    idx_first = first_set_bit_4(mon_itf.mem_wmask[channel]);
                    ones      = count_ones_4(mon_itf.mem_wmask[channel]);
    
                    $fwrite(commit_fd, " mem 0x%08h",
                            {mon_itf.mem_addr[channel][31:2], 2'b00} + idx_first);
    
                    case (ones)
                        1: begin
                            automatic logic [7:0]  wdata_byte;
                            wdata_byte = mon_itf.mem_wdata[channel][8*idx_first +: 8];
                            $fwrite(commit_fd, " 0x%02h", wdata_byte);
                        end
                        2: begin
                            automatic logic [15:0] wdata_half;
                            wdata_half = mon_itf.mem_wdata[channel][8*idx_first +: 16];
                            $fwrite(commit_fd, " 0x%04h", wdata_half);
                        end
                        4: begin
                            $fwrite(commit_fd, " 0x%08h", mon_itf.mem_wdata[channel]);
                        end
                        default: begin
                            $fwrite(commit_fd, " 0x%08h", mon_itf.mem_wdata[channel]);
                        end
                    endcase
                end
    
                $fwrite(commit_fd, "\n");
    
                // Stop logging after halt instruction
                if (is_halt(mon_itf.inst[channel])) begin
                    break;
                end
            end
        end
    end
endmodule

module roi_monitor #(
    parameter CHANNELS = 1
)(
    mon_itf mon_itf
);
    localparam logic [31:0] IPC_START_INST  = 32'h0010_2013; // IPC segment start
    localparam logic [31:0] IPC_STOP_INST   = 32'h0020_2013; // IPC segment stop
    localparam logic [31:0] PWR_START_INST  = 32'h0030_2013; // power window start
    localparam logic [31:0] PWR_STOP_INST   = 32'h0040_2013; // power window stop

    int roi_fd;
    bit dump_fsdb;

    longint unsigned inst_count;
    longint unsigned cycle_count;

    time start_time;
    bit  ipc_printed;

    time power_start_time;
    bit  power_printed;

    initial begin
        roi_fd = $fopen("roi.log", "w");
        if (roi_fd == 0) begin
            $fatal(1, "[roi_monitor] Failed to open roi log 'roi.log'");
        end
    
        inst_count       = '0;
        cycle_count      = '0;
        start_time       = '0;
        ipc_printed      = 1'b0;
    
        power_start_time = '0;
        power_printed    = 1'b0;

        $value$plusargs("DUMP_FSDB=%d", dump_fsdb);
    end

    final begin
        // If we never saw a IPC_STOP_INST, print global IPC summary
        if (!ipc_printed) begin
            if (cycle_count != 0 && !$isunknown({inst_count, cycle_count})) begin
                $display("[roi_monitor] Total IPC   : %f", real'(inst_count) / real'(cycle_count));
            end
            else begin
                $display("[roi_monitor] Total IPC   : N/A (invalid or zero cycle_count)");
            end
            $display("[roi_monitor] Total time  : %0t", $time - start_time);
        end
    
        // If we never saw a PWR_STOP_INST, still dump whatever window we tracked
        if (!power_printed) begin
            $fwrite(roi_fd, "%0t\n", power_start_time);
            $fwrite(roi_fd, "%0t", $time);
        end
    
        if (roi_fd != 0) begin
            $fclose(roi_fd);
        end
    end

    always @(posedge mon_itf.clk iff !mon_itf.rst) begin
        cycle_count <= cycle_count + 1;

        for (int unsigned channel = 0; channel < CHANNELS; channel++) begin
            if (mon_itf.valid[channel]) begin
                inst_count <= inst_count + 1;

                if (mon_itf.inst[channel] == IPC_START_INST) begin
                    $display("[roi_monitor] IPC segment start at time %0t", $time);
                    inst_count  <= '0;
                    cycle_count <= '0;
                    start_time  <= $time;
                    ipc_printed <= 1'b0;
                end

                if (mon_itf.inst[channel] == IPC_STOP_INST) begin
                    ipc_printed <= 1'b1;
                    $display("[roi_monitor] IPC segment stop at time %0t", $time);

                    if (cycle_count != 0 && !$isunknown({inst_count, cycle_count})) begin
                        $display("[roi_monitor] Segment IPC  : %f", real'(inst_count) / real'(cycle_count));
                    end
                    else begin
                        $display("[roi_monitor] Segment IPC  : N/A (invalid or zero cycle_count)");
                    end                    

                    $display("[roi_monitor] Segment time : %0t", $time - start_time);
                end

                if (mon_itf.inst[channel] == PWR_START_INST) begin
                    $display("[roi_monitor] Power window start at time %0t", $time);
                    power_start_time <= $time;
                    power_printed    <= 1'b0;
                end

                if (mon_itf.inst[channel] == PWR_STOP_INST) begin
                    power_printed <= 1'b1;
                    $display("[roi_monitor] Power window stop at time %0t", $time);

                    $fwrite(roi_fd, "%0t\n", power_start_time);
                    $fwrite(roi_fd, "%0t", $time);
                end
            end
        end
    end
endmodule