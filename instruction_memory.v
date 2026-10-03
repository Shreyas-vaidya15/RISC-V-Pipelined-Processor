module inst_memory #(parameter DEPTH = 256) (input [31:0] addr, output [31:0] data);

// Extra test image for the INSTRUCTION ACCESS FAULT exception (cause 1): the cases the first image did not cover.
// Instruction memory is 1024 bytes: valid fetch addresses 0..1020 (DEPTH 256 words).
// Layout (byte addresses):
//     0         jal x0,200       skip over the handler
//   100..140    exception handler (mtvec = 100):
//                 x29 = mcause, x30++ (trap counter), x28 = mepc + 4
//                 if mcause == 1  -> x28 = x31 (recovery address; mepc+4 would also be out of range)
//                 mepc = x28, mret
//   200..       main program, 4 cases (see comments); each cause-1 case sets x31 = where the handler must resume
//  1016..1020   tail of memory: nop, then lw x16,0(x5)  (CASE 3)
// Cases:
//   1  forward branch, predicted NOT taken, really taken to an out-of-range target   -> cause 1, mepc = 1216
//   2  mret with an out-of-range mepc (2000)                                            -> cause 1, mepc = 2000
//   4  jal to a target that is out of range AND misaligned (1026)                       -> cause 0 at the jal (mepc = 300), NOT cause 1
//   3a lw at the last word, misaligned address                                          -> cause 4 (mepc 1020), then cause 1 (mepc 1024)
//   3b lw at the last word, aligned but out-of-range data address                       -> cause 5 (mepc 1020), then cause 1 (mepc 1024)
//   3c lw at the last word, valid address: the lw completes (x16 = 1234)                -> cause 1 (mepc 1024)
// In 3a/3b the out-of-range fetch (1024) is sitting in ID in the SAME cycle as the older lw exception in EX: the older one must win.
// Expected traps (8, in order): cause 1, cause 1, cause 0, cause 4, cause 1, cause 5, cause 1, cause 1.
// Case numbers are not in execution order: 1, 2, 4, 3a, 3b, 3c.
// NOTE: CSR numbers are the current custom ones (mepc = 0, mcause = 2); regenerate the csr fields when you move to the standard addresses.

reg [7:0] mem [0:DEPTH*4-1];

integer i;
initial begin
    for (i = 0; i < DEPTH*4; i = i + 1)
        mem[i] = 8'h00;

    {mem[3], mem[2], mem[1], mem[0]} = 32'h0c80006f;// addr 0: jal x0,200            -- skip over the handler
    {mem[103], mem[102], mem[101], mem[100]} = 32'h00202ef3;// addr 100: csrrs x29,mcause,x0   -- [HANDLER] x29 = mcause
    {mem[107], mem[106], mem[105], mem[104]} = 32'h001f0f13;// addr 104: addi x30,x30,1        -- [HANDLER] trap counter++
    {mem[111], mem[110], mem[109], mem[108]} = 32'h00002e73;// addr 108: csrrs x28,mepc,x0     -- [HANDLER] x28 = mepc
    {mem[115], mem[114], mem[113], mem[112]} = 32'h004e0e13;// addr 112: addi x28,x28,4        -- [HANDLER] default: skip the trapping instruction
    {mem[119], mem[118], mem[117], mem[116]} = 32'hfffe8d13;// addr 116: addi x26,x29,-1       -- [HANDLER] x26 = mcause - 1
    {mem[123], mem[122], mem[121], mem[120]} = 32'h000d1463;// addr 120: bne x26,x0,+8         -- [HANDLER] cause != 1 -> keep mepc+4
    {mem[127], mem[126], mem[125], mem[124]} = 32'h000f8e13;// addr 124: addi x28,x31,0        -- [HANDLER] cause == 1 -> resume at the recovery address in x31
    {mem[131], mem[130], mem[129], mem[128]} = 32'h000e1073;// addr 128: csrrw x0,mepc,x28     -- [HANDLER] mepc = x28
    {mem[135], mem[134], mem[133], mem[132]} = 32'h00000013;// addr 132: nop                   -- [HANDLER] (mepc must be written >= 1 instr before mret)
    {mem[139], mem[138], mem[137], mem[136]} = 32'h00000013;// addr 136: nop                   -- [HANDLER]
    {mem[143], mem[142], mem[141], mem[140]} = 32'h30200073;// addr 140: mret                  -- [HANDLER]
    {mem[203], mem[202], mem[201], mem[200]} = 32'h04d00813;// addr 200: addi x16,x0,77        -- sentinel: a squashed lw must NOT overwrite x16
    {mem[207], mem[206], mem[205], mem[204]} = 32'h00000013;// addr 204: nop
    {mem[211], mem[210], mem[209], mem[208]} = 32'h0e800f93;// addr 208: addi x31,x0,232      -- CASE 1: recovery address
    {mem[215], mem[214], mem[213], mem[212]} = 32'h00000013;// addr 212: nop
    {mem[219], mem[218], mem[217], mem[216]} = 32'h3e000463;// addr 216: beq x0,x0,+1000       -- CASE 1: forward => predicted NOT taken; really taken to 1216 (out of range) -> mispredict redirect, then TRAP cause 1, mepc=1216
    {mem[223], mem[222], mem[221], mem[220]} = 32'h00158593;// addr 220: addi x11,x11,1        -- CASE 1 wrong path: must NEVER execute
    {mem[227], mem[226], mem[225], mem[224]} = 32'h00158593;// addr 224: addi x11,x11,1        -- CASE 1 wrong path: must NEVER execute
    {mem[231], mem[230], mem[229], mem[228]} = 32'h00158593;// addr 228: addi x11,x11,1        -- CASE 1 wrong path: must NEVER execute
    {mem[235], mem[234], mem[233], mem[232]} = 32'h001a0a13;// addr 232: addi x20,x20,1        -- CASE 1 marker (recovery point)
    {mem[239], mem[238], mem[237], mem[236]} = 32'h00000013;// addr 236: nop
    {mem[243], mem[242], mem[241], mem[240]} = 32'h00000013;// addr 240: nop
    {mem[247], mem[246], mem[245], mem[244]} = 32'h11800f93;// addr 244: addi x31,x0,280      -- CASE 2: recovery address
    {mem[251], mem[250], mem[249], mem[248]} = 32'h7d000293;// addr 248: addi x5,x0,2000        -- CASE 2: bad return address (aligned, outside memory)
    {mem[255], mem[254], mem[253], mem[252]} = 32'h00029073;// addr 252: csrrw x0,mepc,x5       -- CASE 2: mepc = 2000
    {mem[259], mem[258], mem[257], mem[256]} = 32'h00000013;// addr 256: nop
    {mem[263], mem[262], mem[261], mem[260]} = 32'h00000013;// addr 260: nop
    {mem[267], mem[266], mem[265], mem[264]} = 32'h30200073;// addr 264: mret                  -- CASE 2: mret itself completes, then the fetch at 2000 -> TRAP cause 1, mepc=2000
    {mem[271], mem[270], mem[269], mem[268]} = 32'h00160613;// addr 268: addi x12,x12,1        -- CASE 2 wrong path: must NEVER execute
    {mem[275], mem[274], mem[273], mem[272]} = 32'h00160613;// addr 272: addi x12,x12,1        -- CASE 2 wrong path: must NEVER execute
    {mem[279], mem[278], mem[277], mem[276]} = 32'h00160613;// addr 276: addi x12,x12,1        -- CASE 2 wrong path: must NEVER execute
    {mem[283], mem[282], mem[281], mem[280]} = 32'h001a8a93;// addr 280: addi x21,x21,1        -- CASE 2 marker (recovery point)
    {mem[287], mem[286], mem[285], mem[284]} = 32'h00000013;// addr 284: nop
    {mem[291], mem[290], mem[289], mem[288]} = 32'h00000013;// addr 288: nop
    {mem[295], mem[294], mem[293], mem[292]} = 32'h04d00093;// addr 292: addi x1,x0,77         -- CASE 4: x1 sentinel (the faulting jal must NOT write its link)
    {mem[299], mem[298], mem[297], mem[296]} = 32'h00000013;// addr 296: nop
    {mem[303], mem[302], mem[301], mem[300]} = 32'h2d6000ef;// addr 300: jal x1,1026            -- CASE 4: target is out of range AND misaligned -> TRAP cause 0 at the jal, mepc=300 (no fetch happens)
    {mem[307], mem[306], mem[305], mem[304]} = 32'h001b0b13;// addr 304: addi x22,x22,1        -- CASE 4 marker (handler resumes at jal+4)
    {mem[311], mem[310], mem[309], mem[308]} = 32'h00000013;// addr 308: nop
    {mem[315], mem[314], mem[313], mem[312]} = 32'h00000013;// addr 312: nop
    {mem[319], mem[318], mem[317], mem[316]} = 32'h14800f93;// addr 316: addi x31,x0,328      -- CASE 3a: recovery address
    {mem[323], mem[322], mem[321], mem[320]} = 32'h10200293;// addr 320: addi x5,x0,258        -- CASE 3a: lw address is misaligned (and out of range): lw traps cause 4 first, then the fetch at 1024 traps cause 1
    {mem[327], mem[326], mem[325], mem[324]} = 32'h2b40006f;// addr 324: jal x0,1016           -- CASE 3a: run into the tail
    {mem[331], mem[330], mem[329], mem[328]} = 32'h001b8b93;// addr 328: addi x23,x23,1        -- CASE 3a marker (recovery point)
    {mem[335], mem[334], mem[333], mem[332]} = 32'h00000013;// addr 332: nop
    {mem[339], mem[338], mem[337], mem[336]} = 32'h00000013;// addr 336: nop
    {mem[343], mem[342], mem[341], mem[340]} = 32'h16000f93;// addr 340: addi x31,x0,352      -- CASE 3b: recovery address
    {mem[347], mem[346], mem[345], mem[344]} = 32'h10000293;// addr 344: addi x5,x0,256        -- CASE 3b: lw address is aligned but out of range: lw traps cause 5 first, then the fetch at 1024 traps cause 1
    {mem[351], mem[350], mem[349], mem[348]} = 32'h29c0006f;// addr 348: jal x0,1016           -- CASE 3b: run into the tail
    {mem[355], mem[354], mem[353], mem[352]} = 32'h001c0c13;// addr 352: addi x24,x24,1        -- CASE 3b marker (recovery point)
    {mem[359], mem[358], mem[357], mem[356]} = 32'h00000013;// addr 356: nop
    {mem[363], mem[362], mem[361], mem[360]} = 32'h00000013;// addr 360: nop
    {mem[367], mem[366], mem[365], mem[364]} = 32'h0fc00293;// addr 364: addi x5,x0,252        -- CASE 3c: valid aligned data address
    {mem[371], mem[370], mem[369], mem[368]} = 32'h4d200313;// addr 368: addi x6,x0,1234       -- CASE 3c: value to load back
    {mem[375], mem[374], mem[373], mem[372]} = 32'h0062a023;// addr 372: sw x6,0(x5)          -- CASE 3c: mem[252] = 1234
    {mem[379], mem[378], mem[377], mem[376]} = 32'h18000f93;// addr 376: addi x31,x0,384      -- CASE 3c: recovery address
    {mem[383], mem[382], mem[381], mem[380]} = 32'h27c0006f;// addr 380: jal x0,1016           -- CASE 3c: run into the tail; lw completes, then TRAP cause 1 at 1024
    {mem[387], mem[386], mem[385], mem[384]} = 32'h001c8c93;// addr 384: addi x25,x25,1        -- CASE 3c marker (recovery point)
    {mem[391], mem[390], mem[389], mem[388]} = 32'h00000013;// addr 388: nop
    {mem[395], mem[394], mem[393], mem[392]} = 32'h00000013;// addr 392: nop
    {mem[399], mem[398], mem[397], mem[396]} = 32'h3e700793;// addr 396: addi x15,x0,999       -- TRUE END marker
    {mem[403], mem[402], mem[401], mem[400]} = 32'h0000006f;// addr 400: jal x0,0              -- park here forever
    {mem[1019], mem[1018], mem[1017], mem[1016]} = 32'h00000013;// addr 1016: nop                   -- CASE 3 tail: last-but-one word (1016)
    {mem[1023], mem[1022], mem[1021], mem[1020]} = 32'h0002a803;// addr 1020: lw x16,0(x5)          -- CASE 3 tail: LAST valid word (1020); the next fetch (1024) is out of range

end

assign data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};

endmodule