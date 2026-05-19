/////////////////////////////////////////////////////////////
// Maybe merge what is in mp_verif/rtl/cpu/types.sv over here? //
/////////////////////////////////////////////////////////////

package rv32i_types;
    //ALL OPCODES AND OPERATIONS
    typedef enum logic [6:0] {
        op_b_lui       = 7'b0110111, // load upper immediate (U type)
        op_b_auipc     = 7'b0010111, // add upper immediate PC (U type)
        op_b_jal       = 7'b1101111, // jump and link (J type)
        op_b_jalr      = 7'b1100111, // jump and link register (I type)
        op_b_br        = 7'b1100011, // branch (B type)
        op_b_load      = 7'b0000011, // load (I type)
        op_b_store     = 7'b0100011, // store (S type)
        op_b_imm       = 7'b0010011, // arith ops with register/immediate operands (I type)
        op_b_reg       = 7'b0110011  // arith ops with register operands (R type)
    } rv32i_opcode;

    typedef enum logic [2:0] {
        arith_f3_add   = 3'b000, // check logic 30 for sub if op_reg op
        arith_f3_sll   = 3'b001,
        arith_f3_slt   = 3'b010,
        arith_f3_sltu  = 3'b011,
        arith_f3_xor   = 3'b100,
        arith_f3_sr    = 3'b101, // check logic 30 for logical/arithmetic
        arith_f3_or    = 3'b110,
        arith_f3_and   = 3'b111
    } arith_f3_t;

    typedef enum logic [2:0] {
        load_f3_lb     = 3'b000,
        load_f3_lh     = 3'b001,
        load_f3_lw     = 3'b010,
        load_f3_lbu    = 3'b100,
        load_f3_lhu    = 3'b101
    } load_f3_t;

    typedef enum logic [2:0] {
        store_f3_sb    = 3'b000,
        store_f3_sh    = 3'b001,
        store_f3_sw    = 3'b010
    } store_f3_t;

    typedef enum logic [2:0] {
        branch_f3_beq  = 3'b000,
        branch_f3_bne  = 3'b001,
        branch_f3_blt  = 3'b100,
        branch_f3_bge  = 3'b101,
        branch_f3_bltu = 3'b110,
        branch_f3_bgeu = 3'b111
    } branch_f3_t;

    typedef enum logic [2:0] {
        alu_op_add     = 3'b000,
        alu_op_sll     = 3'b001,
        alu_op_sra     = 3'b010,
        alu_op_sub     = 3'b011,
        alu_op_xor     = 3'b100,
        alu_op_srl     = 3'b101,
        alu_op_or      = 3'b110,
        alu_op_and     = 3'b111
    } alu_ops;

    typedef enum logic {
        rs1_out = 1'b0,
        pc_out  = 1'b1
    } alu_m1_sel_t;

    typedef enum logic {
      alu_m2_rs2 = 1'b0,
      alu_m2_imm = 1'b1
    } alu_m2_sel_t;

// more mux def here

    //TYPE OF INSTRUCTION
    typedef union packed {
        logic [31:0] word;

        struct packed {
            logic [11:0] i_imm;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  rd;
            rv32i_opcode opcode;
        } i_type;

        struct packed {
            logic [6:0]  funct7;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  rd;
            rv32i_opcode opcode;
        } r_type;

        struct packed {
            logic [11:5] imm_s_top;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  imm_s_bot;
            rv32i_opcode opcode;
        } s_type;


        struct packed { 
            logic        imm_12;
            logic [10:5] imm_10_5;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:1]  imm_4_1; 
            logic        imm_11;
            rv32i_opcode opcode;
        } b_type;

        struct packed {
            logic [31:12] imm;
            logic [4:0]   rd;
            rv32i_opcode  opcode;
        } j_type;

    } instr_t;

//IF-ID pipeline reg
typedef struct packed{   //think as giant bus
    logic       valid;
    logic        valid_bit; //is using this stage valid_bit right now?
    logic [31:0] inst;
    logic [31:0] pc;    
    logic [63:0] order; //used for monitor

} if_id_t;


typedef struct packed {
    logic               valid;
    logic               valid_bit;
    logic   [31:0]      inst;
    logic   [31:0]      pc;
    logic   [63:0]      order;

    alu_m1_sel_t        alu_m1_sel;
    alu_m2_sel_t        alu_m2_sel;
    alu_ops             alu_op;

    logic   [4:0]       rs1, rs2, rd;   //register number and values
    logic   [31:0]      rs1_v, rs2_v;

    logic   [31:0]      imm;        //immediate value to pass onto execute

    logic               reg_write;

    logic               slt_now;
    logic               slt_sign_signal;

    logic               is_load;
    logic               is_store;
    logic   [2:0]   mem_funct3; //keep track of which type of load or store

    logic        is_jal;    //signals to keep track of branch
    logic        is_jalr;
    logic        is_branch;
    logic [2:0]  branch_funct3;

} id_ex_stage_reg_t;

typedef struct packed {
    logic       valid;
    logic        valid_bit;
    logic [31:0] pc;
    logic [31:0] inst;
    logic [63:0] order;

    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [31:0] rs1_rdata;
    logic [31:0] rs2_rdata;

    logic        reg_write;
    logic [4:0]  rd_addr;
    logic [31:0] result;

    logic        is_load;
    logic        is_store;
    logic [2:0]  mem_funct3;    //type of load or store
    //logic [31:0] eff_addr;      //computed address
    logic [31:0] store_data;   //

    logic   [3:0]       dmem_rmask;
    logic   [3:0]       dmem_wmask;
    logic   [31:0]      dmem_wdata;
    logic [31: 0]       dmem_rdata;

    logic        branch_taken;
    logic [31:0] branch_target;

} ex_mem_t;

typedef struct packed {
    logic           valid;
    logic        valid_bit;
    logic [31:0] inst;
    logic [63:0] order;

    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [31:0] rs1_rdata;
    logic [31:0] rs2_rdata;
    
    logic [4:0]  rd_addr;
    logic [31:0] rd_wdata;
    
    logic [31:0] pc_rdata;
    logic [31:0] pc_wdata;
    
    logic        reg_write;

    logic [31:0] mem_addr;
    logic [3:0]  mem_rmask;
    logic [3:0]  mem_wmask;
    logic [31:0] mem_rdata;
    logic [31:0] mem_wdata;
    
} mem_wb_t;

endpackage
