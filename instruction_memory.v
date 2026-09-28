module inst_memory #(parameter DEPTH = 256) (input [31:0] addr, output [31:0] data);

// Layout (byte addresses):
//    0.. 76  main program (phases A-H)
//  128       [KEYBOARD VECTOR]  jal -> 256   (mtvec 100 + 4*7)
//  208       [DISK VECTOR]      jal -> 384   (mtvec 100 + 4*27)
//  256..348  [KEYBOARD ISR body]
//  384..476  [DISK ISR body]
//  512       TRUE END marker
// CSR map: 0=mepc 1=mie 2=mcause 3=current_priority 4=previous_priority
// Priority: keyboard=01, disk=10. Trap taken iff mie & ID!=0 & ID >= current_priority.

reg [7:0] mem [0:DEPTH*4-1];

integer i;
initial begin
    for (i = 0; i < DEPTH*4; i = i + 1)
        mem[i] = 8'h00;

    {mem[3], mem[2], mem[1], mem[0]} = 32'h0c800113;// addr   0: addi x2,x0,200         -- sp = 200
    {mem[7], mem[6], mem[5], mem[4]} = 32'h06f00313;// addr   4: addi x6,x0,111         -- LIVE reg x6 -- must survive every trap below
    {mem[11], mem[10], mem[9], mem[8]} = 32'h0de00393;// addr   8: addi x7,x0,222         -- LIVE reg x7 -- must survive every trap below
    {mem[15], mem[14], mem[13], mem[12]} = 32'h00100a13;// addr  12: addi x20,x0,1          -- PHASE A trigger: keyboard alone
    {mem[19], mem[18], mem[17], mem[16]} = 32'h00200a93;// addr  16: addi x21,x0,2          -- post-A
    {mem[23], mem[22], mem[21], mem[20]} = 32'h00300a13;// addr  20: addi x20,x0,3          -- PHASE B trigger: disk alone
    {mem[27], mem[26], mem[25], mem[24]} = 32'h00400a93;// addr  24: addi x21,x0,4          -- post-B
    {mem[31], mem[30], mem[29], mem[28]} = 32'h00500a13;// addr  28: addi x20,x0,5          -- PHASE C trigger: simultaneous kb+disk (disk wins, kb waits for disk's mret)
    {mem[35], mem[34], mem[33], mem[32]} = 32'h00600a93;// addr  32: addi x21,x0,6          -- post-C
    {mem[39], mem[38], mem[37], mem[36]} = 32'h00700a13;// addr  36: addi x20,x0,7          -- PHASE D trigger: kb outer, disk nests @296 (disk 2 >= kb 1)
    {mem[43], mem[42], mem[41], mem[40]} = 32'h00800a93;// addr  40: addi x21,x0,8          -- post-D
    {mem[47], mem[46], mem[45], mem[44]} = 32'h00900a13;// addr  44: addi x20,x0,9          -- PHASE E trigger: disk outer, kb pulse @424 must be BLOCKED (1 < 2) until disk's mret
    {mem[51], mem[50], mem[49], mem[48]} = 32'h00a00a93;// addr  48: addi x21,x0,10         -- post-E
    {mem[55], mem[54], mem[53], mem[52]} = 32'h00b00a13;// addr  52: addi x20,x0,11         -- PHASE F trigger: kb outer, kb self-nests @296 (1 >= 1, 2-level)
    {mem[59], mem[58], mem[57], mem[56]} = 32'h00c00a93;// addr  56: addi x21,x0,12         -- post-F
    {mem[63], mem[62], mem[61], mem[60]} = 32'h00d00a13;// addr  60: addi x20,x0,13         -- PHASE G trigger: kb outer, disk asserted @268 during mie=0 (unsafe window)
    {mem[67], mem[66], mem[65], mem[64]} = 32'h00e00a93;// addr  64: addi x21,x0,14         -- post-G
    {mem[71], mem[70], mem[69], mem[68]} = 32'h00f00a13;// addr  68: addi x20,x0,15         -- PHASE H trigger: kb outer, kb self-nests @296 TWICE (3-level)
    {mem[75], mem[74], mem[73], mem[72]} = 32'h01000a93;// addr  72: addi x21,x0,16         -- post-H
    {mem[79], mem[78], mem[77], mem[76]} = 32'h1b40006f;// addr  76: jal x0,512            -- skip over vectors + both ISR bodies to the END marker
    {mem[131], mem[130], mem[129], mem[128]} = 32'h0800006f;// addr 128: jal x0,256            -- [KEYBOARD VECTOR] mtvec(100)+4*7 = 128, ISR body is too long for the 80-byte slot, so trampoline
    {mem[211], mem[210], mem[209], mem[208]} = 32'h0b00006f;// addr 208: jal x0,384            -- [DISK VECTOR]     mtvec(100)+4*27 = 208, trampoline to disk ISR body
    {mem[259], mem[258], mem[257], mem[256]} = 32'hfe010113;// addr 256: addi x2,x2,-32        -- [KEYBOARD ISR] alloc 8 stack words (5 used: x6,x7,mepc,mcause,prev_prio)
    {mem[263], mem[262], mem[261], mem[260]} = 32'h00612023;// addr 260: sw x6,0(x2)           -- [KEYBOARD ISR] save x6
    {mem[267], mem[266], mem[265], mem[264]} = 32'h00712223;// addr 264: sw x7,4(x2)           -- [KEYBOARD ISR] save x7
    {mem[271], mem[270], mem[269], mem[268]} = 32'h00002ef3;// addr 268: csrrs x29,mepc,x0     -- [KEYBOARD ISR] x29 = this trap's return PC  <-- G's unsafe-window pulse lands here (mie still 0)
    {mem[275], mem[274], mem[273], mem[272]} = 32'h01d12423;// addr 272: sw x29,8(x2)          -- [KEYBOARD ISR] push mepc
    {mem[279], mem[278], mem[277], mem[276]} = 32'h00202ef3;// addr 276: csrrs x29,mcause,x0    -- [KEYBOARD ISR] x29 = this trap's mcause
    {mem[283], mem[282], mem[281], mem[280]} = 32'h01d12623;// addr 280: sw x29,12(x2)         -- [KEYBOARD ISR] push mcause
    {mem[287], mem[286], mem[285], mem[284]} = 32'h00402ef3;// addr 284: csrrs x29,prev_prio,x0  -- [KEYBOARD ISR] x29 = previous_priority (level this trap interrupted, latched by hardware at trap entry)
    {mem[291], mem[290], mem[289], mem[288]} = 32'h01d12823;// addr 288: sw x29,16(x2)         -- [KEYBOARD ISR] push previous_priority
    {mem[295], mem[294], mem[293], mem[292]} = 32'h0010d073;// addr 292: csrrwi x0,mie,1       -- [KEYBOARD ISR] mie <= 1 -- re-enable, priority compare now decides who may nest
    {mem[299], mem[298], mem[297], mem[296]} = 32'h001f0f13;// addr 296: addi x30,x30,1        -- [KEYBOARD ISR] trap-entry counter++  <-- D/E/F/H injections land here
    {mem[303], mem[302], mem[301], mem[300]} = 32'h3e700313;// addr 300: addi x6,x0,999        -- [KEYBOARD ISR] CLOBBER x6 (poison) -- proves save/restore matters
    {mem[307], mem[306], mem[305], mem[304]} = 32'h37800393;// addr 304: addi x7,x0,888        -- [KEYBOARD ISR] CLOBBER x7 (poison)
    {mem[311], mem[310], mem[309], mem[308]} = 32'h00105073;// addr 308: csrrwi x0,mie,0       -- [KEYBOARD ISR] mie <= 0 -- epilogue is atomic: a trap after the CSR restores below would clobber mepc/prev_prio (mret sets mie back to 1)
    {mem[315], mem[314], mem[313], mem[312]} = 32'h00c12e83;// addr 312: lw x29,12(x2)         -- [KEYBOARD ISR] x29 = saved mcause
    {mem[319], mem[318], mem[317], mem[316]} = 32'h002e9073;// addr 316: csrrw x0,mcause,x29    -- [KEYBOARD ISR] restore mcause
    {mem[323], mem[322], mem[321], mem[320]} = 32'h00812e83;// addr 320: lw x29,8(x2)          -- [KEYBOARD ISR] x29 = saved mepc
    {mem[327], mem[326], mem[325], mem[324]} = 32'h000e9073;// addr 324: csrrw x0,mepc,x29      -- [KEYBOARD ISR] restore mepc
    {mem[331], mem[330], mem[329], mem[328]} = 32'h01012e83;// addr 328: lw x29,16(x2)         -- [KEYBOARD ISR] x29 = saved previous_priority
    {mem[335], mem[334], mem[333], mem[332]} = 32'h004e9073;// addr 332: csrrw x0,prev_prio,x29   -- [KEYBOARD ISR] restore previous_priority (>=1 instr before mret: mret samples it in ID)
    {mem[339], mem[338], mem[337], mem[336]} = 32'h00012303;// addr 336: lw x6,0(x2)           -- [KEYBOARD ISR] restore x6
    {mem[343], mem[342], mem[341], mem[340]} = 32'h00412383;// addr 340: lw x7,4(x2)           -- [KEYBOARD ISR] restore x7
    {mem[347], mem[346], mem[345], mem[344]} = 32'h02010113;// addr 344: addi x2,x2,32         -- [KEYBOARD ISR] free stack words
    {mem[351], mem[350], mem[349], mem[348]} = 32'h30200073;// addr 348: mret                  -- [KEYBOARD ISR] return -> PC = restored mepc; hardware: current_priority <= previous_priority, mie <= 1
    {mem[387], mem[386], mem[385], mem[384]} = 32'hfe010113;// addr 384: addi x2,x2,-32        -- [DISK ISR] alloc 8 stack words (5 used: x6,x7,mepc,mcause,prev_prio)
    {mem[391], mem[390], mem[389], mem[388]} = 32'h00612023;// addr 388: sw x6,0(x2)           -- [DISK ISR] save x6
    {mem[395], mem[394], mem[393], mem[392]} = 32'h00712223;// addr 392: sw x7,4(x2)           -- [DISK ISR] save x7
    {mem[399], mem[398], mem[397], mem[396]} = 32'h00002ef3;// addr 396: csrrs x29,mepc,x0     -- [DISK ISR] x29 = this trap's return PC  <-- G's unsafe-window pulse lands here (mie still 0)
    {mem[403], mem[402], mem[401], mem[400]} = 32'h01d12423;// addr 400: sw x29,8(x2)          -- [DISK ISR] push mepc
    {mem[407], mem[406], mem[405], mem[404]} = 32'h00202ef3;// addr 404: csrrs x29,mcause,x0    -- [DISK ISR] x29 = this trap's mcause
    {mem[411], mem[410], mem[409], mem[408]} = 32'h01d12623;// addr 408: sw x29,12(x2)         -- [DISK ISR] push mcause
    {mem[415], mem[414], mem[413], mem[412]} = 32'h00402ef3;// addr 412: csrrs x29,prev_prio,x0  -- [DISK ISR] x29 = previous_priority (level this trap interrupted, latched by hardware at trap entry)
    {mem[419], mem[418], mem[417], mem[416]} = 32'h01d12823;// addr 416: sw x29,16(x2)         -- [DISK ISR] push previous_priority
    {mem[423], mem[422], mem[421], mem[420]} = 32'h0010d073;// addr 420: csrrwi x0,mie,1       -- [DISK ISR] mie <= 1 -- re-enable, priority compare now decides who may nest
    {mem[427], mem[426], mem[425], mem[424]} = 32'h001f0f13;// addr 424: addi x30,x30,1        -- [DISK ISR] trap-entry counter++  <-- D/E/F/H injections land here
    {mem[431], mem[430], mem[429], mem[428]} = 32'h3e700313;// addr 428: addi x6,x0,999        -- [DISK ISR] CLOBBER x6 (poison) -- proves save/restore matters
    {mem[435], mem[434], mem[433], mem[432]} = 32'h37800393;// addr 432: addi x7,x0,888        -- [DISK ISR] CLOBBER x7 (poison)
    {mem[439], mem[438], mem[437], mem[436]} = 32'h00105073;// addr 436: csrrwi x0,mie,0       -- [DISK ISR] mie <= 0 -- epilogue is atomic: a trap after the CSR restores below would clobber mepc/prev_prio (mret sets mie back to 1)
    {mem[443], mem[442], mem[441], mem[440]} = 32'h00c12e83;// addr 440: lw x29,12(x2)         -- [DISK ISR] x29 = saved mcause
    {mem[447], mem[446], mem[445], mem[444]} = 32'h002e9073;// addr 444: csrrw x0,mcause,x29    -- [DISK ISR] restore mcause
    {mem[451], mem[450], mem[449], mem[448]} = 32'h00812e83;// addr 448: lw x29,8(x2)          -- [DISK ISR] x29 = saved mepc
    {mem[455], mem[454], mem[453], mem[452]} = 32'h000e9073;// addr 452: csrrw x0,mepc,x29      -- [DISK ISR] restore mepc
    {mem[459], mem[458], mem[457], mem[456]} = 32'h01012e83;// addr 456: lw x29,16(x2)         -- [DISK ISR] x29 = saved previous_priority
    {mem[463], mem[462], mem[461], mem[460]} = 32'h004e9073;// addr 460: csrrw x0,prev_prio,x29   -- [DISK ISR] restore previous_priority (>=1 instr before mret: mret samples it in ID)
    {mem[467], mem[466], mem[465], mem[464]} = 32'h00012303;// addr 464: lw x6,0(x2)           -- [DISK ISR] restore x6
    {mem[471], mem[470], mem[469], mem[468]} = 32'h00412383;// addr 468: lw x7,4(x2)           -- [DISK ISR] restore x7
    {mem[475], mem[474], mem[473], mem[472]} = 32'h02010113;// addr 472: addi x2,x2,32         -- [DISK ISR] free stack words
    {mem[479], mem[478], mem[477], mem[476]} = 32'h30200073;// addr 476: mret                  -- [DISK ISR] return -> PC = restored mepc; hardware: current_priority <= previous_priority, mie <= 1
    {mem[515], mem[514], mem[513], mem[512]} = 32'h3e700e13;// addr 512: addi x28,x0,999        -- TRUE END marker -- only reached if ISR skip-jump worked

end

assign data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};

endmodule