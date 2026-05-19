module ex_stage
import rv32i_types::*;
(
    input  logic   clk,
    input  logic   rst,

    input  logic   stall_ex,     
    input  id_ex_stage_reg_t id_ex_r,

    //output signals for data memory
    output logic [31:0] dmem_addr,
    output logic [3:0]  dmem_rmask,
    output logic [3:0]  dmem_wmask,
    output logic [31:0] dmem_wdata,

    output ex_mem_t ex_mem_r,

    //forwarding logic 
    input  ex_mem_t ex_mem_fwd,
    input  mem_wb_t mem_wb_fwd,

    //output signals for branching flush logic
    output logic    branch_taken_o,
    output logic [31:0] branch_target_o
);

    ex_mem_t ex_mem_n;

    logic [31:0] op_a, op_b;
    logic [31:0] alu_res;

    logic        branch_taken_ex;
    logic [31:0] branch_target_ex;
    logic [31:0] pc_plus4;

    logic [31:0] rs1_fwd, rs2_fwd;
    logic ex_haz_rs1, ex_haz_rs2, mem_haz_rs1, mem_haz_rs2;

    //setup forwarding if data hazard
    assign ex_haz_rs1 =
        ex_mem_fwd.valid_bit && ex_mem_fwd.reg_write && (ex_mem_fwd.rd_addr != 5'd0) &&
        !ex_mem_fwd.is_load && (ex_mem_fwd.rd_addr == id_ex_r.rs1);

    assign ex_haz_rs2 =
        ex_mem_fwd.valid_bit && ex_mem_fwd.reg_write && (ex_mem_fwd.rd_addr != 5'd0) &&
        !ex_mem_fwd.is_load && (ex_mem_fwd.rd_addr == id_ex_r.rs2);

    assign mem_haz_rs1 =
        mem_wb_fwd.valid_bit && mem_wb_fwd.reg_write && (mem_wb_fwd.rd_addr != 5'd0) &&
        !(ex_haz_rs1) && (mem_wb_fwd.rd_addr == id_ex_r.rs1);

    assign mem_haz_rs2 =
        mem_wb_fwd.valid_bit && mem_wb_fwd.reg_write && (mem_wb_fwd.rd_addr != 5'd0) &&
        !(ex_haz_rs2) && (mem_wb_fwd.rd_addr == id_ex_r.rs2);

    always_comb begin
        rs1_fwd = id_ex_r.rs1_v;
        rs2_fwd = id_ex_r.rs2_v;
        //setup forwarding
        if (ex_haz_rs1) rs1_fwd = ex_mem_fwd.result;
        else if (mem_haz_rs1) rs1_fwd = mem_wb_fwd.rd_wdata;

        if (ex_haz_rs2) rs2_fwd = ex_mem_fwd.result;
        else if (mem_haz_rs2) rs2_fwd = mem_wb_fwd.rd_wdata;
    end

    assign pc_plus4 = id_ex_r.pc + 32'd4;

    rv32i_opcode opcode;    //FOR LUI INSTR
    assign opcode = rv32i_opcode'(id_ex_r.inst[6:0]);

    always_comb begin
        unique case (id_ex_r.alu_m1_sel)
            rs1_out: op_a = rs1_fwd;
            pc_out : op_a = id_ex_r.pc;
        default: op_a = 32'hx;
        endcase

        unique case (id_ex_r.alu_m2_sel)
            alu_m2_rs2: op_b = rs2_fwd;
            alu_m2_imm: op_b = id_ex_r.imm;
            default:   op_b = 32'hx;
        endcase
    end
    
    always_comb begin
        alu_res = 32'hx;    //should I set to don't care or 0???
        unique case (id_ex_r.alu_op)
            alu_op_add: alu_res = op_a + op_b;
            alu_op_sub: alu_res = op_a - op_b;
            alu_op_and: alu_res = op_a & op_b;
            alu_op_or : alu_res = op_a | op_b;
            alu_op_xor: alu_res = op_a ^ op_b;
            alu_op_sll: alu_res = op_a << op_b[4:0];
            alu_op_srl: alu_res = op_a >> op_b[4:0];
            alu_op_sra: alu_res = $unsigned($signed(op_a) >>> op_b[4:0]);
        default:    alu_res = 32'hx;
        endcase

        if (id_ex_r.slt_now) begin  //dealing with the slt case
        if (id_ex_r.slt_sign_signal == 1'b0) begin
            alu_res = {31'd0, (($signed(op_a) < $signed(op_b)))}; //signed
        end else begin
            alu_res = {31'd0, (op_a < op_b)};   //unsigned
        end
        end
        if (opcode == op_b_lui) begin
            alu_res = id_ex_r.imm;
        end
        if (id_ex_r.is_jal || id_ex_r.is_jalr) begin
            alu_res = pc_plus4;
        end
    end

    logic [1:0] byte_offset;
    logic [31:0] dmem_addr_calc;
    logic [3:0]  dmem_rmask_calc;
    logic [3:0]  dmem_wmask_calc;
    logic [31:0] dmem_wdata_calc;

    assign byte_offset = alu_res[1:0];  // Address from ALU
    assign dmem_addr_calc = alu_res & 32'hFFFF_FFFC;    // Generate dmem_addr and align
    
    // Generate rmask
    always_comb begin
        dmem_rmask_calc = 4'b0000;
        
        if (id_ex_r.is_load && id_ex_r.valid_bit) begin
            unique case (id_ex_r.mem_funct3)
                load_f3_lb, load_f3_lbu: begin
                    unique case (byte_offset)
                        2'b00: dmem_rmask_calc = 4'b0001;
                        2'b01: dmem_rmask_calc = 4'b0010;
                        2'b10: dmem_rmask_calc = 4'b0100;
                        2'b11: dmem_rmask_calc = 4'b1000;
                    endcase
                end
                load_f3_lh, load_f3_lhu: begin
                    unique case (byte_offset[1])
                        1'b0: dmem_rmask_calc = 4'b0011;
                        1'b1: dmem_rmask_calc = 4'b1100;
                    endcase
                end
                load_f3_lw: dmem_rmask_calc = 4'b1111;
                default: dmem_rmask_calc = 4'b0000;
            endcase
        end
    end
    
    // Generate wmask
    always_comb begin
        dmem_wmask_calc = 4'b0000;
        
        if (id_ex_r.is_store && id_ex_r.valid_bit) begin
            unique case (id_ex_r.mem_funct3)
                store_f3_sb: begin
                    unique case (byte_offset)
                        2'b00: dmem_wmask_calc = 4'b0001;
                        2'b01: dmem_wmask_calc = 4'b0010;
                        2'b10: dmem_wmask_calc = 4'b0100;
                        2'b11: dmem_wmask_calc = 4'b1000;
                    endcase
                end
                store_f3_sh: begin
                    unique case (byte_offset[1])
                        1'b0: dmem_wmask_calc = 4'b0011;
                        1'b1: dmem_wmask_calc = 4'b1100;
                    endcase
                end
                store_f3_sw: dmem_wmask_calc = 4'b1111;
                default: dmem_wmask_calc = 4'b0000;
            endcase
        end
    end
    
    // Generate wdata, shift
    always_comb begin
        dmem_wdata_calc = 32'b0;
        
        if (id_ex_r.is_store) begin
            unique case (id_ex_r.mem_funct3)
                store_f3_sb: begin
                    unique case (byte_offset)
                        2'b00: dmem_wdata_calc = {24'b0, rs2_fwd[7:0]};
                        2'b01: dmem_wdata_calc = {16'b0, rs2_fwd[7:0], 8'b0};
                        2'b10: dmem_wdata_calc = {8'b0, rs2_fwd[7:0], 16'b0};
                        2'b11: dmem_wdata_calc = {rs2_fwd[7:0], 24'b0};
                    endcase
                end
                store_f3_sh: begin
                    unique case (byte_offset[1])
                        1'b0: dmem_wdata_calc = {16'b0, rs2_fwd[15:0]};
                        1'b1: dmem_wdata_calc = {rs2_fwd[15:0], 16'b0};
                    endcase
                end
                store_f3_sw: dmem_wdata_calc = rs2_fwd;
                default: dmem_wdata_calc = 32'b0;
            endcase
        end
    end

    // Branch condition evaluation
    always_comb begin
        branch_taken_ex = 1'b0;    //always setting branch taken to 0 here
        branch_target_ex = 32'd0;

        if (id_ex_r.is_jal) begin
        branch_taken_ex  = id_ex_r.valid_bit;
        branch_target_ex = id_ex_r.pc + id_ex_r.imm;
    end else if (id_ex_r.is_jalr) begin
        branch_taken_ex  = id_ex_r.valid_bit;
        branch_target_ex = (rs1_fwd + id_ex_r.imm) & 32'hffff_fffe;
    end else if (id_ex_r.is_branch) begin
            unique case (id_ex_r.branch_funct3)
                branch_f3_beq : branch_taken_ex = (rs1_fwd == rs2_fwd);
                branch_f3_bne : branch_taken_ex = (rs1_fwd != rs2_fwd);
                branch_f3_blt : branch_taken_ex = ($signed(rs1_fwd) <  $signed(rs2_fwd));
                branch_f3_bge : branch_taken_ex = ($signed(rs1_fwd) >= $signed(rs2_fwd));
                branch_f3_bltu: branch_taken_ex = (rs1_fwd <  rs2_fwd);
                branch_f3_bgeu: branch_taken_ex = (rs1_fwd >= rs2_fwd);
                default       : branch_taken_ex = 1'b0;
            endcase
            branch_target_ex = id_ex_r.pc + id_ex_r.imm;
        end
    end

    assign branch_taken_o  = branch_taken_ex;
    assign branch_target_o = branch_target_ex;

    assign dmem_addr  = dmem_addr_calc;
    assign dmem_rmask = stall_ex ? 4'b0 : dmem_rmask_calc; //adding stall_ex HERE
    assign dmem_wmask = stall_ex ? 4'b0 : dmem_wmask_calc;
    assign dmem_wdata = dmem_wdata_calc;


    always_comb begin
        ex_mem_n = '0;

        ex_mem_n.valid    = id_ex_r.valid;
        ex_mem_n.valid_bit = id_ex_r.valid_bit;
        ex_mem_n.pc        = id_ex_r.pc;
        ex_mem_n.inst      = id_ex_r.inst;
        ex_mem_n.order     = id_ex_r.order;

        ex_mem_n.rs1_addr  = id_ex_r.rs1;
        ex_mem_n.rs2_addr  = id_ex_r.rs2;
        
        ex_mem_n.rs1_rdata = rs1_fwd;   //use forwarded values
        ex_mem_n.rs2_rdata = rs2_fwd;

        ex_mem_n.is_load    = id_ex_r.is_load;
        ex_mem_n.is_store   = id_ex_r.is_store;
        ex_mem_n.mem_funct3 = id_ex_r.mem_funct3;

        ex_mem_n.store_data = rs2_fwd;

        ex_mem_n.dmem_rmask = dmem_rmask_calc; 
        ex_mem_n.dmem_wmask = dmem_wmask_calc; 
        ex_mem_n.dmem_wdata = dmem_wdata_calc;

        ex_mem_n.reg_write = id_ex_r.reg_write;
        ex_mem_n.rd_addr   = id_ex_r.rd;

        if (!id_ex_r.valid_bit) begin       //DEBUG
            ex_mem_n.reg_write = 1'b0;
            ex_mem_n.rd_addr        = 5'd0;
            ex_mem_n.is_load  = 1'b0;
            ex_mem_n.is_store = 1'b0;
        end

        ex_mem_n.branch_taken  = branch_taken_ex;
        ex_mem_n.branch_target = branch_target_ex;

        if (id_ex_r.is_jal || id_ex_r.is_jalr)
            ex_mem_n.result = pc_plus4;              
        else
            ex_mem_n.result = alu_res;
        end

    always_ff @(posedge clk) begin
        if (rst) begin
            ex_mem_r <= '0;
            ex_mem_r.valid_bit <= 1'b0;
        end else if (!stall_ex) begin
            ex_mem_r <= ex_mem_n;
        end else begin
            ex_mem_r <= ex_mem_r;
        end
    end

endmodule