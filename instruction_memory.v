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

   {mem[3],mem[2],mem[1],mem[0]}         = 32'h00128293; // addr   0: addi x5,x5,1
{mem[7],mem[6],mem[5],mem[4]}         = 32'h00228293; // addr   4: addi x5,x5,2
{mem[11],mem[10],mem[9],mem[8]}       = 32'h00328293; // addr   8: addi x5,x5,3
{mem[15],mem[14],mem[13],mem[12]}     = 32'h00428293; // addr  12: addi x5,x5,4
{mem[19],mem[18],mem[17],mem[16]}     = 32'h005282FF; // addr  16: ILLEGAL (addi x5,x5,5 with opcode changed to 1111111)
{mem[23],mem[22],mem[21],mem[20]}     = 32'h00628293; // addr  20: addi x5,x5,6
{mem[27],mem[26],mem[25],mem[24]}     = 32'h00728293; // addr  24: addi x5,x5,7
{mem[31],mem[30],mem[29],mem[28]}     = 32'h00828293; // addr  28: addi x5,x5,8
{mem[35],mem[34],mem[33],mem[32]}     = 32'h00928293; // addr  32: addi x5,x5,9
{mem[39],mem[38],mem[37],mem[36]}     = 32'h00a28293; // addr  36: addi x5,x5,10
{mem[43],mem[42],mem[41],mem[40]}     = 32'h06300e13; // addr  40: addi x28,x0,99   -- end marker
{mem[47],mem[46],mem[45],mem[44]} = 32'h0000006f; // addr 44: jal x0,0   -- spin here forever
{mem[111],mem[110],mem[109],mem[108]} = 32'h001f0f13; // addr 108: addi x30,x30,1      -- exception counter
{mem[115],mem[114],mem[113],mem[112]} = 32'h00202ff3; // addr 112: csrrs x31,mcause,x0 -- x31 = cause
{mem[119],mem[118],mem[117],mem[116]} = 32'h00002ef3; // addr 116: csrrs x29,mepc,x0   -- x29 = PC of bad instr
{mem[123],mem[122],mem[121],mem[120]} = 32'h004e8e93; // addr 120: addi x29,x29,4      -- skip it
{mem[127],mem[126],mem[125],mem[124]} = 32'h000e9073; // addr 124: csrrw x0,mepc,x29   -- mepc = mepc + 4
{mem[131],mem[130],mem[129],mem[128]} = 32'h00000013; // addr 128: nop                 -- gap so mret sees the new mepc
{mem[135],mem[134],mem[133],mem[132]} = 32'h30200073; // addr 132: mret

end

assign data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};

endmodule