module id_stage
import rv32i_types::*;
(
    input logic clk, 
    input logic rst,

    input logic stall_id,

    input if_id_t if_id_r,  
    
    input logic wb_we,  //signals from WB for REG FILE
    input logic [4:0] wb_rd,
    input logic [31:0] wb_wdata,
    
    input logic kill_id_ex,

    output id_ex_stage_reg_t id_ex_r  
);

  instr_t instr;
  assign instr.word = if_id_r.inst; //set the current instruction to instr passed in

  logic [31:0] rs1_v, rs2_v;
  logic [4:0]  rs1, rs2, rd;

  assign rs1 = instr.i_type.rs1;    //assign source and dest regs with the value passed in from instr
  assign rs2 = instr.r_type.rs2;
  assign rd  = instr.i_type.rd;

  regfile u_regfile (   //pass signals to reg file to access registers
    .clk    (clk),
    .rst    (rst),
    .regf_we(wb_we),
    .rd_v   (wb_wdata),
    .rs1_s  (rs1),
    .rs2_s  (rs2),
    .rd_s   (wb_rd),
    .rs1_v  (rs1_v),    //we get the values inside the source regs here
    .rs2_v  (rs2_v)
  );

  logic [31:0] i_imm, s_imm, b_imm, u_imm, j_imm;   //make up the immediate for each possible case
  always_comb begin
    i_imm = {{21{if_id_r.inst[31]}}, if_id_r.inst[30:20]};
    s_imm = {{21{if_id_r.inst[31]}}, if_id_r.inst[30:25], if_id_r.inst[11:7]};
    b_imm = {{20{if_id_r.inst[31]}}, if_id_r.inst[7], if_id_r.inst[30:25], if_id_r.inst[11:8], 1'b0};
    u_imm = {if_id_r.inst[31:12], 12'h000};
    j_imm = {{12{if_id_r.inst[31]}}, if_id_r.inst[19:12], if_id_r.inst[20], if_id_r.inst[30:21], 1'b0};
  end

  id_ex_stage_reg_t id_ex_n;   

  always_comb begin
    id_ex_n = '0;

    //basically a wire passing the same values down from IF/ID
    id_ex_n.valid_bit = if_id_r.valid_bit;
    id_ex_n.pc    = if_id_r.pc;
    id_ex_n.inst  = if_id_r.inst;
    id_ex_n.order = if_id_r.order;

    id_ex_n.rs1   = rs1;    //Values from the REG file, set them up for id_ex reg
    id_ex_n.rs2   = rs2;
    id_ex_n.rd    = rd;
    id_ex_n.rs1_v = rs1_v;
    id_ex_n.rs2_v = rs2_v;
    id_ex_n.valid = if_id_r.valid;

    id_ex_n.alu_m1_sel = rs1_out;    
    id_ex_n.alu_m2_sel = alu_m2_rs2;    //default value for alu selects
    id_ex_n.alu_op     = alu_op_add;
    id_ex_n.imm        = 32'd0;

    unique case (instr.i_type.opcode)   //depending on opcode, setup necessary values

      op_b_jal: begin
        id_ex_n.reg_write  = 1'b1;
        id_ex_n.rd         = rd;
        id_ex_n.is_jal     = 1'b1;
        id_ex_n.imm        = j_imm;

        id_ex_n.alu_m1_sel = pc_out;  //pc + j_imm for target
        id_ex_n.alu_m2_sel = alu_m2_imm;
        id_ex_n.alu_op     = alu_op_add;
        id_ex_n.rs1        = 5'd0;      // change register addr and values to 0
        id_ex_n.rs2        = 5'd0;      
        id_ex_n.rs1_v      = 32'd0;     
        id_ex_n.rs2_v      = 32'd0;
      end

      op_b_jalr: begin
        id_ex_n.reg_write  = 1'b1;
        id_ex_n.rd         = rd;
        id_ex_n.is_jalr    = 1'b1;
        id_ex_n.imm        = i_imm;
        
        id_ex_n.alu_m1_sel = rs1_out; //rs1 + i_imm for target
        id_ex_n.alu_m2_sel = alu_m2_imm;
        id_ex_n.alu_op     = alu_op_add;

        id_ex_n.rs2        = 5'd0;  //
        id_ex_n.rs2_v      = 32'd0;
      end

      op_b_br: begin
        id_ex_n.reg_write    = 1'b0;
        id_ex_n.rd           = 5'd0;
        id_ex_n.is_branch    = 1'b1;
        id_ex_n.branch_funct3 = instr.b_type.funct3; 
        id_ex_n.imm          = b_imm;
        
        id_ex_n.alu_m1_sel   = pc_out;  //pc + b_imm for branch target
        id_ex_n.alu_m2_sel   = alu_m2_imm;
        id_ex_n.alu_op       = alu_op_add;
      end

        op_b_load: begin
          id_ex_n.reg_write  = 1'b1;
          id_ex_n.is_load    = 1'b1;
          id_ex_n.is_store   = 1'b0;
          id_ex_n.mem_funct3 = instr.i_type.funct3;

          id_ex_n.alu_m1_sel = rs1_out;
          id_ex_n.alu_m2_sel = alu_m2_imm;
          id_ex_n.alu_op     = alu_op_add;
          id_ex_n.imm        = i_imm;
          id_ex_n.rs2        = 5'd0;
          id_ex_n.rs2_v      = 32'd0;

        end

        op_b_store: begin
          id_ex_n.reg_write  = 1'b0;
          id_ex_n.is_load    = 1'b0;
          id_ex_n.is_store   = 1'b1;
          id_ex_n.mem_funct3 = instr.s_type.funct3;
          id_ex_n.rd = 5'd0;

          id_ex_n.alu_m1_sel = rs1_out;
          id_ex_n.alu_m2_sel = alu_m2_imm;
          id_ex_n.alu_op     = alu_op_add;
          id_ex_n.imm        = s_imm;

        end 

        op_b_lui: begin
          id_ex_n.reg_write = 1'b1;
          id_ex_n.imm       = u_imm;

          id_ex_n.alu_m1_sel = rs1_out;
          id_ex_n.alu_m2_sel = alu_m2_imm;
          id_ex_n.alu_op     = alu_op_add;
          id_ex_n.rs1        = 5'd0;
          id_ex_n.rs2        = 5'd0;
          id_ex_n.rs1_v      = 32'd0;
          id_ex_n.rs2_v      = 32'd0;
        end

        op_b_auipc: begin
          id_ex_n.reg_write  = 1'b1;
          id_ex_n.imm        = u_imm;

          id_ex_n.alu_m1_sel = pc_out;
          id_ex_n.alu_m2_sel = alu_m2_imm;
          id_ex_n.alu_op     = alu_op_add;
          id_ex_n.rs1        = 5'd0;
          id_ex_n.rs2        = 5'd0;
          id_ex_n.rs1_v      = 32'd0;
          id_ex_n.rs2_v      = 32'd0;
        end

      op_b_imm: begin   //setup immediate and alu selects for this instr
        id_ex_n.reg_write = 1'b1;
        id_ex_n.alu_m1_sel= rs1_out;
        id_ex_n.alu_m2_sel= alu_m2_imm;
        id_ex_n.imm       = i_imm;
        id_ex_n.rs2       = 5'd0;
        id_ex_n.rs2_v     = 32'd0;

        unique case (instr.i_type.funct3)   //determine which operation to do, alu val to pass on
          arith_f3_add: id_ex_n.alu_op = alu_op_add; 
          arith_f3_and: id_ex_n.alu_op = alu_op_and;
          arith_f3_or : id_ex_n.alu_op = alu_op_or;
          arith_f3_xor: id_ex_n.alu_op = alu_op_xor;
          arith_f3_sll: id_ex_n.alu_op = alu_op_sll;
          arith_f3_sr : id_ex_n.alu_op = instr.word[30] ? alu_op_sra : alu_op_srl;
          arith_f3_slt: begin 
            id_ex_n.slt_now            = 1'b1;
            id_ex_n.slt_sign_signal    = 1'b0; //signed value
          end   
          arith_f3_sltu: begin 
            id_ex_n.slt_now            = 1'b1;
            id_ex_n.slt_sign_signal    = 1'b1;
          end
          default: id_ex_n.valid_bit = 1'b0;
        endcase
      end

      op_b_reg: begin
        id_ex_n.reg_write = 1'b1;
        id_ex_n.alu_m1_sel= rs1_out;
        id_ex_n.alu_m2_sel= alu_m2_rs2;

        unique case (instr.r_type.funct3)
          arith_f3_add: id_ex_n.alu_op = instr.word[30] ? alu_op_sub : alu_op_add;
          arith_f3_and: id_ex_n.alu_op = alu_op_and;
          arith_f3_or : id_ex_n.alu_op = alu_op_or;
          arith_f3_xor: id_ex_n.alu_op = alu_op_xor;
          arith_f3_sll: id_ex_n.alu_op = alu_op_sll;
          arith_f3_sr : id_ex_n.alu_op = instr.word[30] ? alu_op_sra : alu_op_srl;
          arith_f3_slt: begin 
            id_ex_n.slt_now            = 1'b1;
            id_ex_n.slt_sign_signal    = 1'b0; //signed value
          end   
          arith_f3_sltu: begin 
            id_ex_n.slt_now            = 1'b1;
            id_ex_n.slt_sign_signal    = 1'b1;
          end
          default: id_ex_n.valid_bit = 1'b0;
        endcase
      end

      default: begin
        id_ex_n.valid_bit = 1'b0; // if instr not coded yet, make invalid_bit as default case
      end
    endcase
  end


  always_ff @(posedge clk) begin    
    if (rst) begin
      id_ex_r <= '0;
      id_ex_r.valid_bit <= 1'b0;   
    end else if (kill_id_ex) begin 
      // bubble or flush depending on load use or branch
      id_ex_r <= '0;
      id_ex_r.valid_bit <= 1'b0;
    end else if (!stall_id) begin
      id_ex_r <= id_ex_n;       
    end else begin 
      id_ex_r <= id_ex_r;
    end
  end

endmodule