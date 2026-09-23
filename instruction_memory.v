module inst_memory #(parameter DEPTH=64)(input [31:0] addr, output [31:0] data);

reg [7:0] mem [0:DEPTH*4-1];

initial begin
 // ==================================================================
 // Single-interrupt v1 verification program
 // mtvec = 100, mcause hardcoded to {1,7} -> vector slot = 100 + 4*7 = 128
 // ==================================================================

 // ---- Phase 1: baseline correctness (Case 1, 2) ----
 {mem[3],  mem[2],  mem[1],  mem[0]}   = 32'h00500093; // addr 0:   addi x1,x0,5
 {mem[7],  mem[6],  mem[5],  mem[4]}   = 32'h00A00113; // addr 4:   addi x2,x0,10
 {mem[11], mem[10], mem[9],  mem[8]}   = 32'h00F00193; // addr 8:   addi x3,x0,15    assert interrupt while this is in EX -> mepc should = 8
 {mem[15], mem[14], mem[13], mem[12]}  = 32'h01400213; // addr 12:  addi x4,x0,20
 {mem[19], mem[18], mem[17], mem[16]}  = 32'h01900293; // addr 16:  addi x5,x0,25

 // ---- Phase 2: same trap window as Phase 1 (Case 3) ----
 // No new instructions here -- while the ISR triggered above (addr 128) is
 // still running, pulse `interrupt` a SECOND time before its mret executes.
 // MIE should be 0 the whole time -> mepc/mcause must NOT change, and x30
 // (ISR entry counter) must NOT increment a second time for this pulse.

 // ---- Phase 3: branch unresolved in EX at trap time (Case 4, 5) ----
 {mem[23], mem[22], mem[21], mem[20]}  = 32'h00100313; // addr 20:  addi x6,x0,1
 {mem[27], mem[26], mem[25], mem[24]}  = 32'h00100393; // addr 24:  addi x7,x0,1     (x6 == x7)
 {mem[31], mem[30], mem[29], mem[28]}  = 32'h00730663; // addr 28:  beq x6,x7,40     assert interrupt while this is in EX -> mepc should = 28. Taken -> lands at 40
 {mem[35], mem[34], mem[33], mem[32]}  = 32'h3E700413; // addr 32:  addi x8,x0,999   POISON -> must stay 0
 {mem[39], mem[38], mem[37], mem[36]}  = 32'h37800413; // addr 36:  addi x8,x0,888   POISON -> must stay 0
 {mem[43], mem[42], mem[41], mem[40]}  = 32'h22B00493; // addr 40:  addi x9,x0,555   correct landing after re-executed branch -> expect x9=555

 // ---- Phase 4: interrupt during an active load-use stall (Case 6) ----
 {mem[47], mem[46], mem[45], mem[44]}  = 32'h00002503; // addr 44:  lw x10,0(x0)     assert interrupt while this is in EX (Stall active) -> mepc should = 44. loads data_mem[0]=0
 {mem[51], mem[50], mem[49], mem[48]}  = 32'h00550593; // addr 48:  addi x11,x10,5   load-use dependency -> expect x11=5 (after correct re-execution)
 {mem[55], mem[54], mem[53], mem[52]}  = 32'h04D00613; // addr 52:  addi x12,x0,77

 // ---- Phase 5: jal in EX at trap time (Case 5, 7) ----
 {mem[59], mem[58], mem[57], mem[56]}  = 32'h0080006F; // addr 56:  jal x0,64        assert interrupt while this is in EX -> mepc should = 56
 {mem[63], mem[62], mem[61], mem[60]}  = 32'h3E700693; // addr 60:  addi x13,x0,999  POISON -> must stay 0
 {mem[67], mem[66], mem[65], mem[64]}  = 32'h06F00713; // addr 64:  addi x14,x0,111  correct landing after re-executed jal -> expect x14=111

 // ---- wrap up main program, skip over the ISR region ----
 {mem[71], mem[70], mem[69], mem[68]}  = 32'h0DE00793; // addr 68:  addi x15,x0,222
 {mem[75], mem[74], mem[73], mem[72]}  = 32'h0580006F; // addr 72:  jal x0,160        skip over ISR region entirely

 // ---- ISR (reached only via mtvec + 4*mcause_code = 100 + 4*7 = 128) ----
 {mem[131],mem[130],mem[129],mem[128]} = 32'h001F0F13; // addr 128: addi x30,x30,1   counts every REAL trap entry -> should end at exactly 4
 {mem[135],mem[134],mem[133],mem[132]} = 32'h00100E93; // addr 132: addi x29,x0,1    ISR body marker -> expect x29=1 after each entry
 {mem[139],mem[138],mem[137],mem[136]} = 32'h30200073; // addr 136: mret             return to mepc, restore MIE

 // ---- Phase 6: continue after all interrupts, prove nothing corrupted ----
 {mem[163],mem[162],mem[161],mem[160]} = 32'h14D00813; // addr 160: addi x16,x0,333
 {mem[167],mem[166],mem[165],mem[164]} = 32'h1BC00893; // addr 164: addi x17,x0,444
 // TRUE_END:
 {mem[171],mem[170],mem[169],mem[168]} = 32'h00100913; // addr 168: addi x18,x0,1    true end marker -> expect x18=1

end

assign data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};

endmodule