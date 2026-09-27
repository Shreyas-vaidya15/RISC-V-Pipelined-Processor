module inst_memory #(parameter DEPTH = 128) (input [31:0] addr, output [31:0] data);

reg [7:0] mem [0:DEPTH*4-1];

integer i;
initial begin
    for (i = 0; i < DEPTH*4; i = i + 1)
        mem[i] = 8'h00;

    {mem[3], mem[2], mem[1], mem[0]} = 32'h0c800113;      // addr   0: addi x2,x0,200         -- sp = 200
    {mem[7], mem[6], mem[5], mem[4]} = 32'h06f00313;      // addr   4: addi x6,x0,111         -- LIVE reg x6 -- must survive every trap below
    {mem[11], mem[10], mem[9], mem[8]} = 32'h0de00393;    // addr   8: addi x7,x0,222         -- LIVE reg x7 -- must survive every trap below
    {mem[15], mem[14], mem[13], mem[12]} = 32'h00100a13;  // addr  12: addi x20,x0,1          -- PHASE A trigger: keyboard alone
    {mem[19], mem[18], mem[17], mem[16]} = 32'h00200a93;  // addr  16: addi x21,x0,2          -- post-A
    {mem[23], mem[22], mem[21], mem[20]} = 32'h00300a13;  // addr  20: addi x20,x0,3          -- PHASE B trigger: disk alone
    {mem[27], mem[26], mem[25], mem[24]} = 32'h00400a93;  // addr  24: addi x21,x0,4          -- post-B
    {mem[31], mem[30], mem[29], mem[28]} = 32'h00500a13;  // addr  28: addi x20,x0,5          -- PHASE C trigger: simultaneous kb+disk
    {mem[35], mem[34], mem[33], mem[32]} = 32'h00600a93;  // addr  32: addi x21,x0,6          -- post-C
    {mem[39], mem[38], mem[37], mem[36]} = 32'h00700a13;  // addr  36: addi x20,x0,7          -- PHASE D trigger: kb outer, disk nests @160
    {mem[43], mem[42], mem[41], mem[40]} = 32'h00800a93;  // addr  40: addi x21,x0,8          -- post-D
    {mem[47], mem[46], mem[45], mem[44]} = 32'h00900a13;  // addr  44: addi x20,x0,9          -- PHASE E trigger: disk outer, kb nests @240
    {mem[51], mem[50], mem[49], mem[48]} = 32'h00a00a93;  // addr  48: addi x21,x0,10         -- post-E
    {mem[55], mem[54], mem[53], mem[52]} = 32'h00b00a13;  // addr  52: addi x20,x0,11         -- PHASE F trigger: kb outer, kb self-nests @160 (2-level)
    {mem[59], mem[58], mem[57], mem[56]} = 32'h00c00a93;  // addr  56: addi x21,x0,12         -- post-F
    {mem[63], mem[62], mem[61], mem[60]} = 32'h00d00a13;  // addr  60: addi x20,x0,13         -- PHASE G trigger: kb outer, disk asserted @140 during mie=0 (unsafe window)
    {mem[67], mem[66], mem[65], mem[64]} = 32'h00e00a93;  // addr  64: addi x21,x0,14         -- post-G
    {mem[71], mem[70], mem[69], mem[68]} = 32'h00f00a13;  // addr  68: addi x20,x0,15         -- PHASE H trigger: kb outer, kb self-nests @160 TWICE (3-level)
    {mem[75], mem[74], mem[73], mem[72]} = 32'h01000a93;  // addr  72: addi x21,x0,16         -- post-H
    {mem[79], mem[78], mem[77], mem[76]} = 32'h0e00006f;  // addr  76: jal x0,300             -- skip over both ISR regions
    {mem[131], mem[130], mem[129], mem[128]} = 32'hff010113;// addr 128: addi x2,x2,-16         -- [KEYBOARD ISR] alloc 4 stack words
    {mem[135], mem[134], mem[133], mem[132]} = 32'h00612023;// addr 132: sw x6,0(x2)            -- [KEYBOARD ISR] save x6
    {mem[139], mem[138], mem[137], mem[136]} = 32'h00712223;// addr 136: sw x7,4(x2)            -- [KEYBOARD ISR] save x7
    {mem[143], mem[142], mem[141], mem[140]} = 32'h00002ef3;// addr 140: csrrs x29,mepc,x0      -- [KEYBOARD ISR] x29 = old mepc  <-- G's unsafe-window pulse lands here (mie still 0)
    {mem[147], mem[146], mem[145], mem[144]} = 32'h01d12423;// addr 144: sw x29,8(x2)           -- [KEYBOARD ISR] push mepc
    {mem[151], mem[150], mem[149], mem[148]} = 32'h00202ef3;// addr 148: csrrs x29,mcause,x0    -- [KEYBOARD ISR] x29 = old mcause
    {mem[155], mem[154], mem[153], mem[152]} = 32'h01d12623;// addr 152: sw x29,12(x2)          -- [KEYBOARD ISR] push mcause
    {mem[159], mem[158], mem[157], mem[156]} = 32'h0010d073;// addr 156: csrrwi x0,mie,1        -- [KEYBOARD ISR] mie <= 1 -- re-enable, nesting allowed from here
    {mem[163], mem[162], mem[161], mem[160]} = 32'h001f0f13;// addr 160: addi x30,x30,1         -- [KEYBOARD ISR] trap-entry counter++  <-- D/F/H nested injections land here
    {mem[167], mem[166], mem[165], mem[164]} = 32'h3e700313;// addr 164: addi x6,x0,999         -- [KEYBOARD ISR] CLOBBER x6 (poison) -- proves save/restore matters
    {mem[171], mem[170], mem[169], mem[168]} = 32'h37800393;// addr 168: addi x7,x0,888         -- [KEYBOARD ISR] CLOBBER x7 (poison)
    {mem[175], mem[174], mem[173], mem[172]} = 32'h00c12e83;// addr 172: lw x29,12(x2)          -- [KEYBOARD ISR] x29 = saved mcause
    {mem[179], mem[178], mem[177], mem[176]} = 32'h002e9073;// addr 176: csrrw x0,mcause,x29    -- [KEYBOARD ISR] restore mcause
    {mem[183], mem[182], mem[181], mem[180]} = 32'h00812e83;// addr 180: lw x29,8(x2)           -- [KEYBOARD ISR] x29 = saved mepc
    {mem[187], mem[186], mem[185], mem[184]} = 32'h000e9073;// addr 184: csrrw x0,mepc,x29      -- [KEYBOARD ISR] restore mepc
    {mem[191], mem[190], mem[189], mem[188]} = 32'h00012303;// addr 188: lw x6,0(x2)            -- [KEYBOARD ISR] restore x6
    {mem[195], mem[194], mem[193], mem[192]} = 32'h00412383;// addr 192: lw x7,4(x2)            -- [KEYBOARD ISR] restore x7
    {mem[199], mem[198], mem[197], mem[196]} = 32'h01010113;// addr 196: addi x2,x2,16          -- [KEYBOARD ISR] free stack words
    {mem[203], mem[202], mem[201], mem[200]} = 32'h30200073;// addr 200: mret                   -- [KEYBOARD ISR] return -> PC = restored mepc
    {mem[211], mem[210], mem[209], mem[208]} = 32'hff010113;// addr 208: addi x2,x2,-16         -- [DISK ISR] alloc 4 stack words
    {mem[215], mem[214], mem[213], mem[212]} = 32'h00612023;// addr 212: sw x6,0(x2)            -- [DISK ISR] save x6
    {mem[219], mem[218], mem[217], mem[216]} = 32'h00712223;// addr 216: sw x7,4(x2)            -- [DISK ISR] save x7
    {mem[223], mem[222], mem[221], mem[220]} = 32'h00002ef3;// addr 220: csrrs x29,mepc,x0      -- [DISK ISR] x29 = old mepc  <-- G's unsafe-window pulse lands here (mie still 0)
    {mem[227], mem[226], mem[225], mem[224]} = 32'h01d12423;// addr 224: sw x29,8(x2)           -- [DISK ISR] push mepc
    {mem[231], mem[230], mem[229], mem[228]} = 32'h00202ef3;// addr 228: csrrs x29,mcause,x0    -- [DISK ISR] x29 = old mcause
    {mem[235], mem[234], mem[233], mem[232]} = 32'h01d12623;// addr 232: sw x29,12(x2)          -- [DISK ISR] push mcause
    {mem[239], mem[238], mem[237], mem[236]} = 32'h0010d073;// addr 236: csrrwi x0,mie,1        -- [DISK ISR] mie <= 1 -- re-enable, nesting allowed from here
    {mem[243], mem[242], mem[241], mem[240]} = 32'h001f0f13;// addr 240: addi x30,x30,1         -- [DISK ISR] trap-entry counter++  <-- D/F/H nested injections land here
    {mem[247], mem[246], mem[245], mem[244]} = 32'h3e700313;// addr 244: addi x6,x0,999         -- [DISK ISR] CLOBBER x6 (poison) -- proves save/restore matters
    {mem[251], mem[250], mem[249], mem[248]} = 32'h37800393;// addr 248: addi x7,x0,888         -- [DISK ISR] CLOBBER x7 (poison)
    {mem[255], mem[254], mem[253], mem[252]} = 32'h00c12e83;// addr 252: lw x29,12(x2)          -- [DISK ISR] x29 = saved mcause
    {mem[259], mem[258], mem[257], mem[256]} = 32'h002e9073;// addr 256: csrrw x0,mcause,x29    -- [DISK ISR] restore mcause
    {mem[263], mem[262], mem[261], mem[260]} = 32'h00812e83;// addr 260: lw x29,8(x2)           -- [DISK ISR] x29 = saved mepc
    {mem[267], mem[266], mem[265], mem[264]} = 32'h000e9073;// addr 264: csrrw x0,mepc,x29      -- [DISK ISR] restore mepc
    {mem[271], mem[270], mem[269], mem[268]} = 32'h00012303;// addr 268: lw x6,0(x2)            -- [DISK ISR] restore x6
    {mem[275], mem[274], mem[273], mem[272]} = 32'h00412383;// addr 272: lw x7,4(x2)            -- [DISK ISR] restore x7
    {mem[279], mem[278], mem[277], mem[276]} = 32'h01010113;// addr 276: addi x2,x2,16          -- [DISK ISR] free stack words
    {mem[283], mem[282], mem[281], mem[280]} = 32'h30200073;// addr 280: mret                   -- [DISK ISR] return -> PC = restored mepc
    {mem[303], mem[302], mem[301], mem[300]} = 32'h3e700e13;// addr 300: addi x28,x0,999        -- TRUE END marker -- only reached if ISR skip-jump worked

end

assign data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};

endmodule