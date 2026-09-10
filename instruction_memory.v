module inst_memory #(parameter DEPTH=64)(input [31:0] addr, output [31:0] data);

reg [7:0] mem [0:DEPTH*4-1];

initial begin
 // ==================================================================
 // BTFNT verification program
 // ==================================================================

 // ---- Test 1: Backward BTFNT loop (predicted TAKEN both iterations)
 //      iter1: actual taken  -> correct prediction, NO flush
 //      iter2: actual NOT taken -> misprediction, flush required
 {mem[3],  mem[2],  mem[1],  mem[0]}   = 32'h00200493; // addr 0:   addi x9,x0,2      counter=2
 {mem[7],  mem[6],  mem[5],  mem[4]}   = 32'h00000513; // addr 4:   addi x10,x0,0     accumulator=0
 // LOOP1:
 {mem[11], mem[10], mem[9],  mem[8]}   = 32'hFFF48493; // addr 8:   addi x9,x9,-1
 {mem[15], mem[14], mem[13], mem[12]}  = 32'h00A50513; // addr 12:  addi x10,x10,10
 {mem[19], mem[18], mem[17], mem[16]}  = 32'hFE049CE3; // addr 16:  bne x9,x0,LOOP1   backward, predicted TAKEN. iter1: taken(correct). iter2: not-taken(mispredict->flush)
 {mem[23], mem[22], mem[21], mem[20]}  = 32'h30900593; // addr 20:  addi x11,x0,777   landing after loop exit -> expect x11=777

 // ---- Test 2: Forward branch, correctly predicted NOT taken
 {mem[27], mem[26], mem[25], mem[24]}  = 32'h00500613; // addr 24:  addi x12,x0,5
 {mem[31], mem[30], mem[29], mem[28]}  = 32'h00A00693; // addr 28:  addi x13,x0,10
 {mem[35], mem[34], mem[33], mem[32]}  = 32'h00D60663; // addr 32:  beq x12,x13,SKIP2 forward, predicted NT. 5!=10 -> actual NT (correct, no flush)
 {mem[39], mem[38], mem[37], mem[36]}  = 32'h06F00713; // addr 36:  addi x14,x0,111   falls through -> expect x14=111
 {mem[43], mem[42], mem[41], mem[40]}  = 32'h0DE00793; // addr 40:  addi x15,x0,222   falls through -> expect x15=222
 // SKIP2:
 {mem[47], mem[46], mem[45], mem[44]}  = 32'h00000013; // addr 44:  nop               landing marker

 // ---- Test 3: Forward branch, MISPREDICTED (predicted NT, actually taken)
 {mem[51], mem[50], mem[49], mem[48]}  = 32'h00700813; // addr 48:  addi x16,x0,7
 {mem[55], mem[54], mem[53], mem[52]}  = 32'h00700893; // addr 52:  addi x17,x0,7
 {mem[59], mem[58], mem[57], mem[56]}  = 32'h01180663; // addr 56:  beq x16,x17,TARGET3 forward, predicted NT. 7==7 -> actual TAKEN -> mispredict -> flush
 {mem[63], mem[62], mem[61], mem[60]}  = 32'h3E700913; // addr 60:  addi x18,x0,999   POISON (fall-through path) -> must NOT commit, expect x18=0
 {mem[67], mem[66], mem[65], mem[64]}  = 32'h37800993; // addr 64:  addi x19,x0,888   POISON (fall-through path) -> must NOT commit, expect x19=0
 // TARGET3:
 {mem[71], mem[70], mem[69], mem[68]}  = 32'h22B00A13; // addr 68:  addi x20,x0,555   correct landing -> expect x20=555

 // ---- Test 4: JAL sanity -- EX_Override must fire on Jump regardless of Predicted_Taken
 {mem[75], mem[74], mem[73], mem[72]}  = 32'h00C0006F; // addr 72:  jal x0,TARGET4    unconditional jump
 {mem[79], mem[78], mem[77], mem[76]}  = 32'h3E700A93; // addr 76:  addi x21,x0,999   POISON -> expect x21=0
 {mem[83], mem[82], mem[81], mem[80]}  = 32'h37800A93; // addr 80:  addi x21,x0,888   POISON -> expect x21=0
 // TARGET4:
 {mem[87], mem[86], mem[85], mem[84]}  = 32'h22B00B13; // addr 84:  addi x22,x0,555   jal landing -> expect x22=555

 // ---- Test 5: JALR sanity
 {mem[91], mem[90], mem[89], mem[88]}  = 32'h06800B93; // addr 88:  addi x23,x0,104   x23 = absolute addr of TARGET5
 {mem[95], mem[94], mem[93], mem[92]}  = 32'h000B8067; // addr 92:  jalr x0,x23,0     jump to x23+0
 {mem[99], mem[98], mem[97], mem[96]}  = 32'h3E700C13; // addr 96:  addi x24,x0,999   POISON -> expect x24=0
 {mem[103],mem[102],mem[101],mem[100]} = 32'h37800C13; // addr 100: addi x24,x0,888   POISON -> expect x24=0
 // TARGET5:
 {mem[107],mem[106],mem[105],mem[104]} = 32'h22B00C93; // addr 104: addi x25,x0,555   jalr landing -> expect x25=555

 // ---- Test 6: 0-gap load-use STALL feeding a backward BTFNT branch, ending in misprediction
 //      Exercises stall_unit + forwarding_unit + BTFNT + flush all together.
 {mem[111],mem[110],mem[109],mem[108]} = 32'h02002423; // addr 108: sw x0,40(x0)     mem[40]=0
 {mem[115],mem[114],mem[113],mem[112]} = 32'h00000093; // addr 112: addi x1,x0,0     pre-marker (ordinary sequential code)
 // BACK6:
 {mem[119],mem[118],mem[117],mem[116]} = 32'h3E700113; // addr 116: addi x2,x0,999   backward branch target. Executes once normally (x2=999 transiently). A correct BTFNT+flush must prevent this from committing a 2nd time via the wrongly-predicted-taken speculative refetch.
 {mem[123],mem[122],mem[121],mem[120]} = 32'h02802E03; // addr 120: lw x28,40(x0)    load mem[40]=0
 {mem[127],mem[126],mem[125],mem[124]} = 32'hFE0E1CE3; // addr 124: bne x28,x0,BACK6 0-gap load-use (rs1=x28) -> STALL must fire. Backward -> predicted TAKEN. Actual x28==0 -> NOT taken -> mispredict -> flush
 {mem[131],mem[130],mem[129],mem[128]} = 32'h22B00113; // addr 128: addi x2,x0,555   correct landing. If stall+forward+flush all correct -> final x2=555. If broken -> x2 gets stuck/corrupted here.

 // ---- Test 7: Back-to-back branches, ZERO gap, opposite/independent predictions
 //      Confirms Predicted_Taken is computed fresh per-instruction and isn't
 //      corrupted by the previous branch sitting one pipeline stage ahead.
 // BLOCK7_START:
 {mem[135],mem[134],mem[133],mem[132]} = 32'h00100193; // addr 132: addi x3,x0,1
 {mem[139],mem[138],mem[137],mem[136]} = 32'h00200213; // addr 136: addi x4,x0,2      (x3 != x4)
 // BR_A:
 {mem[143],mem[142],mem[141],mem[140]} = 32'h00418663; // addr 140: beq x3,x4,SKIP7   forward, predicted NT. 1!=2 -> actual NT (correct, no flush) -> falls straight into BR_B, ZERO gap
 // BR_B:
 {mem[147],mem[146],mem[145],mem[144]} = 32'hFE418AE3; // addr 144: beq x3,x4,BLOCK7_START  backward -> predicted TAKEN. 1!=2 -> actual NOT taken -> MISPREDICT -> flush
 {mem[151],mem[150],mem[149],mem[148]} = 32'h0DE00413; // addr 148: addi x8,x0,222    correct landing after BR_B's own mispredict-redirect. expect x8=222
 // SKIP7:
 {mem[155],mem[154],mem[153],mem[152]} = 32'h00000013; // addr 152: nop               (BR_A's target, never reached since BR_A never taken)

 // ---- Test 8: A branch as the landing instruction of a misprediction redirect
 //      Confirms the instruction fetched at EX_RedirectPC gets its own correct
 //      Predicted_Taken, and that two mispredicts back-to-back both flush cleanly.
 // BLOCK8:
 {mem[159],mem[158],mem[157],mem[156]} = 32'h00000D13; // addr 156: addi x26,x0,0     condition reg for LAND8's own branch
 {mem[163],mem[162],mem[161],mem[160]} = 32'h00900293; // addr 160: addi x5,x0,9
 {mem[167],mem[166],mem[165],mem[164]} = 32'h00900313; // addr 164: addi x6,x0,9      (x5 == x6)
 {mem[171],mem[170],mem[169],mem[168]} = 32'h00628663; // addr 168: beq x5,x6,LAND8   forward, predicted NT. 9==9 -> actual TAKEN -> MISPREDICT #1 -> flush -> redirect to LAND8
 {mem[175],mem[174],mem[173],mem[172]} = 32'h3E700393; // addr 172: addi x7,x0,999    POISON (mispredict #1 fall-through) -> expect x7=0
 // POISON8B:
 {mem[179],mem[178],mem[177],mem[176]} = 32'h37800E93; // addr 176: addi x29,x0,888   POISON, also LAND8's own (never-taken) backward target -> expect x29=0
 // LAND8:
 {mem[183],mem[182],mem[181],mem[180]} = 32'hFE0D1EE3; // addr 180: bne x26,x0,POISON8B  LANDING instr of mispredict #1 IS a branch. backward -> predicted TAKEN. x26==0 -> actual NOT taken -> MISPREDICT #2 -> flush
 {mem[187],mem[186],mem[185],mem[184]} = 32'h22B00F13; // addr 184: addi x30,x0,555   final landing after mispredict #2. expect x30=555

 // TRUE_END:
 {mem[191],mem[190],mem[189],mem[188]} = 32'h00100F93; // addr 188: addi x31,x0,1     true end marker -> expect x31=1
end

assign data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};

endmodule