
module arm(input  logic        clk, reset,
           output logic [31:0] PC,
           input  logic [31:0] Instr,
           output logic        MemWrite, MemByte,
           output logic [31:0] ALUResult, WriteData,
           input  logic [31:0] ReadData);

  logic [3:0] ALUFlags;
  logic       RegWrite, ALUSrc,
              MemtoReg, PCSrc,
	      Reverse;   // Used to tell if SrcA and SrcB need to be switched
  logic [1:0] RegSrc, ImmSrc, ALUControl;

  controller c(clk, reset, Instr[31:12], ALUFlags, 
               RegSrc, RegWrite, ImmSrc, 
               ALUSrc, Reverse, MemByte, ALUControl,
               MemWrite, MemtoReg, PCSrc);
  datapath dp(clk, reset, 
              RegSrc, RegWrite, ImmSrc,
              ALUSrc, Reverse, ALUControl,
              MemtoReg, PCSrc,
              ALUFlags, PC, Instr,
              ALUResult, WriteData, ReadData);
endmodule

module controller(input  logic         clk, reset,
	          input  logic [31:12] Instr,
                  input  logic [3:0]   ALUFlags,
                  output logic [1:0]   RegSrc,
                  output logic         RegWrite,
                  output logic [1:0]   ImmSrc,
                  output logic         ALUSrc, Reverse, MemByte,
                  output logic [1:0]   ALUControl,
                  output logic         MemWrite, MemtoReg,
                  output logic         PCSrc);

  logic [1:0] FlagW;
  logic       PCS, RegW, MemW;
  
  decode dec(Instr[27:26], Instr[25:20], Instr[15:12],
             FlagW, PCS, RegW, MemW,
             MemtoReg, ALUSrc, Reverse, MemByte, ImmSrc, RegSrc, ALUControl);
  condlogic cl(clk, reset, Instr[31:28], ALUFlags,
               FlagW, PCS, RegW, MemW,
               PCSrc, RegWrite, MemWrite);
endmodule

module decode(input  logic [1:0] Op,
              input  logic [5:0] Funct,
              input  logic [3:0] Rd,
              output logic [1:0] FlagW,
              output logic       PCS, RegW, MemW,
              output logic       MemtoReg, ALUSrc, Reverse, MemByte,
              output logic [1:0] ImmSrc, RegSrc, ALUControl);

  logic [10:0] controls;
  logic       Branch, ALUOp;

  // Main Decoder
  
  always_comb
  	casex(Op)
  	                        
  	  2'b00:   // Data-Processing Instructions
		   if (Funct[5])
		      controls = 11'b00001010010; // Data processing immediate
  	           else
		      controls = 11'b00000010010; // Data processing register
  	  2'b01:   // Memory Instructions
		   if (Funct[0])
		      controls = 11'b00011110000; // LDR
  	           else
		   begin
		      if (Funct[2])
		         controls = 11'b10011101001; // STRB
		      else
		         controls = 11'b10011101000; // STR
		   end
  	  2'b10:   // Branch Instructions
		   controls = 11'b01101000100; // B
  	  default: // Unimplemented
		   controls = 11'bx;
  	endcase

  assign {RegSrc, ImmSrc, ALUSrc, MemtoReg, 
          RegW, MemW, Branch, ALUOp, MemByte} = controls; 
          
  // ALU Decoder             
  always_comb
    if (ALUOp) begin                 // which DP Instr?
      case(Funct[4:1]) 
  	    4'b0100: // ADD
		     begin
			Reverse = 1'b0;
		        ALUControl = 2'b00;
		     end
  	    4'b0010: // SUB
		     begin
			Reverse = 1'b0;
		        ALUControl = 2'b01;
		     end
  	    4'b0011: // RSB
		     begin
			Reverse = 1'b1;
		        ALUControl = 2'b01;
		     end
            4'b0000: // AND
		     begin
			Reverse = 1'b0;
		        ALUControl = 2'b10;
		     end
  	    4'b1100: // ORR
		     begin
			Reverse = 1'b0;
		        ALUControl = 2'b11;
		     end
  	    default: // unimplemented
		     begin
			Reverse = 1'bx;
		        ALUControl = 2'bx;
		     end
      endcase
      // update flags if S bit is set 
	// (C & V only updated for arith instructions)
      FlagW[1]      = Funct[0]; // FlagW[1] = S-bit
	// FlagW[0] = S-bit & (ADD | SUB)
      FlagW[0]      = Funct[0] & 
        (ALUControl == 2'b00 | ALUControl == 2'b01); 
    end else begin
      ALUControl = 2'b00; // add for non-DP instructions
      FlagW      = 2'b00; // don't update Flags
    end
              
  // PC Logic
  assign PCS  = ((Rd == 4'b1111) & RegW) | Branch; 
endmodule

module condlogic(input  logic       clk, reset,
                 input  logic [3:0] Cond,
                 input  logic [3:0] ALUFlags,
                 input  logic [1:0] FlagW,
                 input  logic       PCS, RegW, MemW,
                 output logic       PCSrc, RegWrite, MemWrite);
                 
  logic [1:0] FlagWrite;
  logic [3:0] Flags;
  logic       CondEx;

  flopenr #(2)flagreg1(clk, reset, FlagWrite[1], 
                       ALUFlags[3:2], Flags[3:2]);
  flopenr #(2)flagreg0(clk, reset, FlagWrite[0], 
                       ALUFlags[1:0], Flags[1:0]);

  // write controls are conditional
  condcheck cc(Cond, Flags, CondEx);
  assign FlagWrite = FlagW & {2{CondEx}};
  assign RegWrite  = RegW  & CondEx;
  assign MemWrite  = MemW  & CondEx;
  assign PCSrc     = PCS   & CondEx;
endmodule    

module condcheck(input  logic [3:0] Cond,
                 input  logic [3:0] Flags,
                 output logic       CondEx);
  
  logic neg, zero, carry, overflow, ge;
  
  assign {neg, zero, carry, overflow} = Flags;
  assign ge = (neg == overflow);
                  
  always_comb
    case(Cond)
      4'b0000: CondEx = zero;             // EQ
      4'b0001: CondEx = ~zero;            // NE
      4'b0010: CondEx = carry;            // CS
      4'b0011: CondEx = ~carry;           // CC
      4'b0100: CondEx = neg;              // MI
      4'b0101: CondEx = ~neg;             // PL
      4'b0110: CondEx = overflow;         // VS
      4'b0111: CondEx = ~overflow;        // VC
      4'b1000: CondEx = carry & ~zero;    // HI
      4'b1001: CondEx = ~(carry & ~zero); // LS
      4'b1010: CondEx = ge;               // GE
      4'b1011: CondEx = ~ge;              // LT
      4'b1100: CondEx = ~zero & ge;       // GT
      4'b1101: CondEx = ~(~zero & ge);    // LE
      4'b1110: CondEx = 1'b1;             // Always
      default: CondEx = 1'bx;             // undefined
    endcase
endmodule

module datapath(input  logic        clk, reset,
                input  logic [1:0]  RegSrc,
                input  logic        RegWrite,
                input  logic [1:0]  ImmSrc,
                input  logic        ALUSrc, Reverse,
                input  logic [1:0]  ALUControl,
                input  logic        MemtoReg,
                input  logic        PCSrc,
                output logic [3:0]  ALUFlags,
                output logic [31:0] PC,
                input  logic [31:0] Instr,
                output logic [31:0] ALUResult, WriteData,
                input  logic [31:0] ReadData);

  logic [31:0] PCNext, PCPlus4, PCPlus8;
  logic [31:0] ExtImm, SrcA, SrcB, Result;
  logic [3:0]  RA1, RA2;
  logic [31:0] RD1, RD2;

  // next PC logic
  mux2 #(32)  pcmux(PCPlus4, Result, PCSrc, PCNext);
  flopr #(32) pcreg(clk, reset, PCNext, PC);
  adder #(32) pcadd1(PC, 32'b100, PCPlus4);
  adder #(32) pcadd2(PCPlus4, 32'b100, PCPlus8);

  // register file logic
  mux2 #(4)   ra1mux(Instr[19:16], 4'b1111, RegSrc[0], RA1);
  mux2 #(4)   ra2mux(Instr[3:0], Instr[15:12], RegSrc[1], RA2);
  regfile     rf(clk, RegWrite, RA1, RA2,
                 Instr[15:12], Result, PCPlus8, 
                 RD1, RD2);
  mux2 #(32)  resmux(ALUResult, ReadData, MemtoReg, Result);
  extend      ext(Instr[23:0], ImmSrc, ExtImm);

  // ALU logic
  mux2 #(32)  srcamux(RD1, RD2, Reverse, SrcA);         // Mux to determine SrcA
  mux2 #(32)  Wdmux(RD2, RD1, Reverse, WriteData);      // Mux to determine WriteData
  mux2 #(32)  srcbmux(WriteData, ExtImm, ALUSrc, SrcB); // Mux to determine SrcB
  alu         alu(SrcA, SrcB, ALUControl, 
                  ALUResult, ALUFlags);
endmodule
