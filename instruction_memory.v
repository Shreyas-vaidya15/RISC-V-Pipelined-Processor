module inst_memory #(parameter DEPTH = 256) (input [31:0] addr, output [31:0] data);

// ============================================================================================
// INTERRUPT SWEEP IMAGE  (pairs with tb_sweep.v)
//
// One deterministic program, run many times by the testbench. Each run delivers ONE interrupt pulse
// (keyboard, disk or both) at a different cycle, and the final registers / data memory / CSRs are compared
// with a run that had no interrupt. The interrupt handler is transparent: it only touches x23.
//
// The program has no exceptions and never reads a CSR whose value a trap would change (mstatus, mepc, mcause,
// mtval, priorities). It only uses mscratch, misa and mie, so "interrupted run == reference run" must hold.
//
// Fixed layout:  0 jal x0,MAIN | 100 jal x0,EXC_H | 144 jal x0,IRQ_H (mtvec reset 0x65, cause 11 -> base+44)
//                160 IRQ_H: x23++ ; mret        192 EXC_H: x24++ ; mepc += 4 ; mret (never expected to run)
//                512.. main program
//
// Reserved registers: x23 interrupt counter, x24 exception counter, x30 end marker (99), x26 stays 0
// (it is only written by instructions that must be skipped).
//
// What the program covers (an interrupt can land on any of these):
//   S1  back-to-back ALU forwarding, shifts, slt/sltu, lui
//   S2  stores/loads of every width, store-to-load, load-use stalls
//   S3  loops: backward-taken branches (BTFNT predicted taken), loop exit mispredict, load-use inside a loop
//   S3b every branch type, taken/not taken, forward/backward, mispredicts
//   S4  jal / jalr, call and return, jalr to a computed address
//   S5  mscratch csrrw/csrrs/csrrc/csrrsi with the result used at once, misa read
//   S6  mstatus.MIE = 0 window, then "csrrw mepc ; mret" back to back (a software mret jump)
// ============================================================================================

reg [7:0] mem [0:DEPTH*4-1];

localparam [31:0] NOP  = 32'h00000013;
localparam [31:0] MRET = 32'h30200073;

localparam [11:0] CSR_MSTATUS = 12'h300, CSR_MISA = 12'h301, CSR_MIE = 12'h304,
                  CSR_MSCRATCH = 12'h340, CSR_MEPC = 12'h341;

integer pc, pass, i, k;
integer n_greg, n_gmem, prog_end;

// ---- golden tables read by the testbench (checked on the reference run) ----
integer        gold_reg   [0:63];
reg [31:0]     gold_rval  [0:63];
reg [8*24-1:0] gold_rname [0:63];
integer        gold_addr  [0:63];
reg [31:0]     gold_mval  [0:63];

integer L_main, L_irq, L_exc;
integer L_l1, L_l2, L_l3, L_b1, L_b2, L_b3, L_b4, L_b5, L_b6, L_fn, L_after, L_mret_t, L_mret_t2;

// ---- instruction encoders (arguments in assembly order) ----
function [31:0] CSRRW;  input [4:0] rd; input [11:0] csr; input [4:0] rs1; CSRRW  = {csr, rs1, 3'b001, rd, 7'b1110011}; endfunction
function [31:0] CSRRS;  input [4:0] rd; input [11:0] csr; input [4:0] rs1; CSRRS  = {csr, rs1, 3'b010, rd, 7'b1110011}; endfunction
function [31:0] CSRRC;  input [4:0] rd; input [11:0] csr; input [4:0] rs1; CSRRC  = {csr, rs1, 3'b011, rd, 7'b1110011}; endfunction
function [31:0] CSRRSI; input [4:0] rd; input [11:0] csr; input [4:0] imm; CSRRSI = {csr, imm, 3'b110, rd, 7'b1110011}; endfunction
function [31:0] ADDI;   input [4:0] rd; input [4:0] rs1; input [11:0] imm; ADDI = {imm, rs1, 3'b000, rd, 7'b0010011}; endfunction
function [31:0] SLLI;   input [4:0] rd; input [4:0] rs1; input [4:0] sh; SLLI = {7'b0000000, sh, rs1, 3'b001, rd, 7'b0010011}; endfunction
function [31:0] SRLI;   input [4:0] rd; input [4:0] rs1; input [4:0] sh; SRLI = {7'b0000000, sh, rs1, 3'b101, rd, 7'b0010011}; endfunction
function [31:0] SRAI;   input [4:0] rd; input [4:0] rs1; input [4:0] sh; SRAI = {7'b0100000, sh, rs1, 3'b101, rd, 7'b0010011}; endfunction
function [31:0] LUI;    input [4:0] rd; input [19:0] imm; LUI = {imm, rd, 7'b0110111}; endfunction
function [31:0] AUIPC;  input [4:0] rd; input [19:0] imm; AUIPC = {imm, rd, 7'b0010111}; endfunction
function [31:0] ADD;    input [4:0] rd; input [4:0] rs1; input [4:0] rs2; ADD  = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011}; endfunction
function [31:0] SUB;    input [4:0] rd; input [4:0] rs1; input [4:0] rs2; SUB  = {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011}; endfunction
function [31:0] SLT;    input [4:0] rd; input [4:0] rs1; input [4:0] rs2; SLT  = {7'b0000000, rs2, rs1, 3'b010, rd, 7'b0110011}; endfunction
function [31:0] SLTU;   input [4:0] rd; input [4:0] rs1; input [4:0] rs2; SLTU = {7'b0000000, rs2, rs1, 3'b011, rd, 7'b0110011}; endfunction
function [31:0] XOR;    input [4:0] rd; input [4:0] rs1; input [4:0] rs2; XOR  = {7'b0000000, rs2, rs1, 3'b100, rd, 7'b0110011}; endfunction
function [31:0] OR;     input [4:0] rd; input [4:0] rs1; input [4:0] rs2; OR   = {7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011}; endfunction
function [31:0] AND;    input [4:0] rd; input [4:0] rs1; input [4:0] rs2; AND  = {7'b0000000, rs2, rs1, 3'b111, rd, 7'b0110011}; endfunction
function [31:0] LB;     input [4:0] rd; input [11:0] imm; input [4:0] rs1; LB  = {imm, rs1, 3'b000, rd, 7'b0000011}; endfunction
function [31:0] LH;     input [4:0] rd; input [11:0] imm; input [4:0] rs1; LH  = {imm, rs1, 3'b001, rd, 7'b0000011}; endfunction
function [31:0] LW;     input [4:0] rd; input [11:0] imm; input [4:0] rs1; LW  = {imm, rs1, 3'b010, rd, 7'b0000011}; endfunction
function [31:0] LBU;    input [4:0] rd; input [11:0] imm; input [4:0] rs1; LBU = {imm, rs1, 3'b100, rd, 7'b0000011}; endfunction
function [31:0] LHU;    input [4:0] rd; input [11:0] imm; input [4:0] rs1; LHU = {imm, rs1, 3'b101, rd, 7'b0000011}; endfunction
function [31:0] SB;     input [4:0] rs2; input [11:0] imm; input [4:0] rs1; SB = {imm[11:5], rs2, rs1, 3'b000, imm[4:0], 7'b0100011}; endfunction
function [31:0] SH;     input [4:0] rs2; input [11:0] imm; input [4:0] rs1; SH = {imm[11:5], rs2, rs1, 3'b001, imm[4:0], 7'b0100011}; endfunction
function [31:0] SW;     input [4:0] rs2; input [11:0] imm; input [4:0] rs1; SW = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011}; endfunction
function [31:0] JALR;   input [4:0] rd; input [4:0] rs1; input [11:0] imm; JALR = {imm, rs1, 3'b000, rd, 7'b1100111}; endfunction

function [31:0] JALO;   input [4:0] rd; input [31:0] off; JALO = {off[20], off[10:1], off[11], off[19:12], rd, 7'b1101111}; endfunction
function [31:0] BRO;    input [2:0] f3; input [4:0] rs1; input [4:0] rs2; input [31:0] off;
    BRO = {off[12], off[10:5], rs2, rs1, f3, off[4:1], off[11], 7'b1100011};
endfunction

// jump / branch to a label (offset worked out from the current pc)
function [31:0] JAL;    input [4:0] rd; input [31:0] tgt;
    reg [31:0] o;
    begin o = tgt - pc; JAL = JALO(rd, o); end
endfunction
function [31:0] BRL;    input [2:0] f3; input [4:0] rs1; input [4:0] rs2; input [31:0] tgt;
    reg [31:0] o;
    begin o = tgt - pc; BRL = BRO(f3, rs1, rs2, o); end
endfunction

// ---- program-building helpers ----
task emit;
    input [31:0] w;
    begin
        {mem[pc+3], mem[pc+2], mem[pc+1], mem[pc]} = w;
        pc = pc + 4;
    end
endtask

task LI;
    input [4:0] rd;
    input [31:0] v;
    reg [31:0] hi;
    begin
        hi = v + 32'h800;
        emit(LUI(rd, hi[31:12]));
        emit(ADDI(rd, rd, v[11:0]));
    end
endtask

// golden expectations (checked by the testbench on the reference run only)
task gr;   // register r must hold v at the end
    input integer r; input [31:0] v; input [8*24-1:0] nm;
    begin gold_reg[n_greg] = r; gold_rval[n_greg] = v; gold_rname[n_greg] = nm; n_greg = n_greg + 1; end
endtask
task gm;   // data memory word at byte address a must hold v at the end
    input integer a; input [31:0] v;
    begin gold_addr[n_gmem] = a; gold_mval[n_gmem] = v; n_gmem = n_gmem + 1; end
endtask

// ============================================================================================
task build;
begin
    n_greg = 0; n_gmem = 0;
    L_main = 512; L_irq = 160; L_exc = 192;

    // ---- boot and vectors ----
    pc = 0;   emit(JAL(0, L_main));
    pc = 100; emit(JAL(0, L_exc));
    pc = 144; emit(JAL(0, L_irq));

    // ---- interrupt handler: transparent, only x23 ----
    pc = 160;
    emit(ADDI(23, 23, 1));
    emit(MRET);

    // ---- exception handler: should never run (x24 is checked) ----
    pc = 192;
    emit(ADDI(24, 24, 1));
    emit(CSRRS(28, CSR_MEPC, 0));
    emit(ADDI(28, 28, 4));
    emit(CSRRW(0, CSR_MEPC, 28));
    emit(NOP); emit(NOP);
    emit(MRET);

    // ================= main program =================
    pc = 512;

    // ---------- S0: enable interrupts (mie[11], then mstatus.MIE) ----------
    LI(5, 32'h800);
    emit(CSRRW(0, CSR_MIE, 5));
    emit(CSRRSI(0, CSR_MSTATUS, 5'd8));

    // ---------- S1: ALU chain, every result feeds the next instruction ----------
    emit(ADDI(1, 0, 7));
    emit(ADDI(2, 1, 5));              // 12
    emit(ADD(3, 1, 2));               // 19
    emit(SUB(4, 3, 1));               // 12
    emit(XOR(5, 4, 3));               // 31
    emit(SLLI(6, 5, 3));              // 248
    emit(SRLI(7, 6, 1));              // 124
    emit(LUI(8, 20'h12345));          // 0x12345000
    emit(ADDI(9, 8, 12'h678));        // 0x12345678
    emit(OR(10, 9, 7));               // 0x1234567C
    emit(AND(11, 10, 9));             // 0x12345678
    emit(ADDI(12, 0, -100));
    emit(SRAI(13, 12, 2));            // -25
    emit(SLT(14, 12, 1));             // 1
    emit(SLTU(15, 12, 1));            // 0
    gr(3, 32'd19, "x3 add chain");
    gr(5, 32'd31, "x5 xor");
    gr(7, 32'd124, "x7 srli");
    gr(10, 32'h1234567C, "x10 or");
    gr(11, 32'h12345678, "x11 and");
    gr(13, 32'hFFFFFFE7, "x13 srai");
    gr(14, 32'd1, "x14 slt");
    gr(15, 32'd0, "x15 sltu");

    // ---------- S2: memory, every width, store->load, load-use ----------
    emit(ADDI(16, 0, 64));
    emit(SW(10, 0, 16));              // mem[64..67] = 0x1234567C
    emit(LW(17, 0, 16));
    emit(ADD(18, 17, 17));            // load-use: 0x2468ACF8
    emit(SB(3, 5, 16));               // mem[69] = 0x13
    emit(SH(10, 10, 16));             // mem[74..75] = 0x567C
    emit(LBU(19, 5, 16));             // 0x13
    emit(LB(21, 0, 16));              // 0x7C
    emit(LHU(22, 10, 16));            // 0x567C
    emit(LH(25, 10, 16));             // 0x567C
    emit(SB(12, 6, 16));              // mem[70] = 0x9C
    emit(LB(27, 6, 16));              // 0xFFFFFF9C
    emit(SH(12, 12, 16));             // mem[76..77] = 0xFF9C
    emit(LH(31, 12, 16));             // 0xFFFFFF9C
    emit(ADD(20, 27, 31));            // load-use on x31: 0xFFFFFF38
    emit(SW(20, 240, 0));
    gr(17, 32'h1234567C, "x17 lw");
    gr(18, 32'h2468ACF8, "x18 load-use add");
    gr(19, 32'h13, "x19 lbu");
    gr(21, 32'h7C, "x21 lb");
    gr(22, 32'h567C, "x22 lhu");
    gr(25, 32'h567C, "x25 lh");
    gm(240, 32'hFFFFFF38);

    // ---------- S3: loops ----------
    emit(ADDI(28, 0, 0)); emit(ADDI(29, 0, 10));
    L_l1 = pc;
    emit(ADD(28, 28, 29));
    emit(ADDI(29, 29, -1));
    emit(BRL(3'b001, 29, 0, L_l1));   // bne, backward: predicted taken, exit is a mispredict
    emit(SW(28, 200, 0));             // 55
    gm(200, 32'd55);

    emit(ADDI(27, 0, 128)); emit(ADDI(20, 0, 8)); emit(ADDI(29, 0, 1));
    L_l2 = pc;
    emit(SW(29, 0, 27));
    emit(ADDI(29, 29, 3));
    emit(ADDI(27, 27, 4));
    emit(ADDI(20, 20, -1));
    emit(BRL(3'b001, 20, 0, L_l2));   // array 1,4,7,...,22
    emit(ADDI(27, 0, 128)); emit(ADDI(20, 0, 8)); emit(ADDI(31, 0, 0));
    L_l3 = pc;
    emit(LW(29, 0, 27));
    emit(ADD(31, 31, 29));            // load-use inside a loop
    emit(ADDI(27, 27, 4));
    emit(ADDI(20, 20, -1));
    emit(BRL(3'b001, 20, 0, L_l3));
    emit(SW(31, 204, 0));             // 92
    gm(204, 32'd92);

    // ---------- S3b: every branch type ----------
    emit(ADDI(28, 0, 0));
    emit(ADDI(29, 0, 5)); emit(ADDI(20, 0, 5)); emit(ADDI(31, 0, -3));
    emit(BRL(3'b000, 29, 20, L_b1));  // beq taken (forward, mispredicted)
    emit(ADDI(28, 28, 100));          // skipped
    L_b1 = pc;
    emit(ADDI(28, 28, 1));
    emit(BRL(3'b001, 29, 20, L_b2));  // bne not taken (forward, predicted right)
    emit(ADDI(28, 28, 2));
    L_b2 = pc;
    emit(BRL(3'b100, 31, 29, L_b3));  // blt taken (-3 < 5)
    emit(ADDI(28, 28, 200));          // skipped
    L_b3 = pc;
    emit(BRL(3'b110, 31, 29, L_b4));  // bltu not taken (0xFFFFFFFD > 5)
    emit(ADDI(28, 28, 4));
    L_b4 = pc;
    emit(BRL(3'b111, 31, 29, L_b5));  // bgeu taken
    emit(ADDI(28, 28, 300));          // skipped
    L_b5 = pc;
    emit(BRL(3'b101, 29, 31, L_b6));  // bge taken (5 >= -3)
    emit(ADDI(28, 28, 400));          // skipped
    L_b6 = pc;
    emit(ADDI(28, 28, 8));
    emit(BRL(3'b001, 29, 29, L_b6));  // bne x29,x29 backward: predicted taken, never taken
    emit(ADDI(28, 28, 16));
    emit(SW(28, 208, 0));             // 1+2+4+8+16 = 31
    gm(208, 32'd31);

    // ---------- S4: jal / jalr ----------
    emit(ADDI(29, 0, 0));
    emit(JAL(20, L_fn));              // call 1
    emit(JAL(20, L_fn));              // call 2
    emit(JAL(0, L_after));
    L_fn = pc;
    emit(ADDI(29, 29, 10));
    emit(JALR(0, 20, 0));             // return
    L_after = pc;
    emit(SW(29, 212, 0));             // 20
    gm(212, 32'd20);

    emit(AUIPC(27, 0));               // jalr to a computed address: pc + 16
    emit(ADDI(27, 27, 16));
    emit(JALR(0, 27, 0));
    emit(ADDI(26, 0, 12'hBAD));       // skipped
    emit(ADDI(28, 0, 77));
    emit(SW(28, 244, 0));
    gm(244, 32'd77);

    // ---------- S5: mscratch / misa, CSR result used straight away ----------
    emit(ADDI(28, 0, 12'h2A5));
    emit(CSRRW(29, CSR_MSCRATCH, 28));      // x29 = 0
    emit(CSRRS(20, CSR_MSCRATCH, 0));       // x20 = 0x2A5
    emit(ADD(31, 20, 28));                  // 0x54A
    emit(CSRRSI(27, CSR_MSCRATCH, 5'd8));   // x27 = 0x2A5, mscratch = 0x2AD
    emit(ADDI(28, 0, 15));
    emit(CSRRC(29, CSR_MSCRATCH, 28));      // x29 = 0x2AD, mscratch = 0x2A0
    emit(CSRRS(20, CSR_MSCRATCH, 0));       // 0x2A0
    emit(CSRRS(28, CSR_MISA, 0));           // 0x40000100
    emit(SW(31, 216, 0)); emit(SW(27, 220, 0)); emit(SW(29, 224, 0)); emit(SW(20, 228, 0)); emit(SW(28, 232, 0));
    gm(216, 32'h54A); gm(220, 32'h2A5); gm(224, 32'h2AD); gm(228, 32'h2A0); gm(232, 32'h40000100);

    // ---------- S6: MIE = 0 window, then csrrw mepc ; mret back to back ----------
    // mstatus <- MIE 0, MPIE 1 (so mret leaves MIE = 1, MPIE = 1 whether or not an interrupt happened before).
    // A pulse that arrives in the window stays pending and is taken right after the mret.
    emit(ADDI(28, 0, 12'h080));
    LI(27, L_mret_t);
    emit(CSRRW(0, CSR_MSTATUS, 28));
    emit(CSRRW(0, CSR_MEPC, 27));
    emit(MRET);
    emit(ADDI(26, 0, 12'hBAD));       // skipped
    L_mret_t = pc;
    emit(ADDI(28, 0, 1));
    emit(SW(28, 236, 0));
    gm(236, 32'd1);

    // ---------- S7: CSR / load-pointer / mret cases placed right behind a memory op ----------
    // With wait states the memory op sits in WB for several cycles and everything behind it is frozen.
    // These cases only come out right if a frozen stage acts ONCE (in the last cycle), never once per wait cycle.
    // The result of each case is stored at once and checked by a golden value, so a wrong value cannot be overwritten unseen.
    // mscratch is 0x2A0 here (end of S5). x16 is still 64, mem[64] = 0x1234567C (S2).

    // A: csrrw two places behind a store. rd must get the OLD mscratch, not the value written by this same csrrw.
    emit(ADDI(1, 0, 12'h111));
    emit(SW(1, 248, 0));                    // the memory op that may wait
    emit(NOP);
    emit(CSRRW(20, CSR_MSCRATCH, 1));       // x20 = 0x2A0, mscratch = 0x111
    emit(SW(20, 252, 0));
    gm(248, 32'h111); gm(252, 32'h2A0);

    // B: csrrs (read-modify-write) two places behind a load. rd must get the OLD mscratch.
    emit(ADDI(6, 0, 15));
    emit(LW(27, 0, 16));                    // the memory op that may wait
    emit(NOP);
    emit(CSRRS(28, CSR_MSCRATCH, 6));       // x28 = 0x111, mscratch = 0x11F
    emit(SW(28, 160, 0));
    gm(160, 32'h111);

    // C: a loaded pointer used as the address of the very next load. While the first load waits, its data is not valid yet:
    // the second load (in EX) must not trap or use it until the wait is over.
    emit(ADDI(8, 0, 168));
    emit(ADDI(9, 0, 12'h5A5));
    emit(SW(8, 164, 0));                    // mem[164] = 168 (a pointer)
    emit(SW(9, 168, 0));                    // mem[168] = 0x5A5
    emit(LW(29, 164, 0));                   // x29 = 168, may wait
    emit(LW(31, 0, 29));                    // address comes from the load above
    emit(SW(31, 172, 0));
    gm(164, 32'd168); gm(168, 32'h5A5); gm(172, 32'h5A5);

    // D: csrrw mepc ; mret right behind a store that may wait. The mret must update MIE / MPIE only ONCE.
    // Start with MIE = 0, MPIE = 0: one mret gives MIE = 0, MPIE = 1 (mstatus reads 0x1880). A second mret would give MIE = 1.
    // MIE stays 0 up to the read, so no interrupt can change what is read. Then MIE is turned on again.
    LI(12, L_mret_t2);
    emit(CSRRW(0, CSR_MSTATUS, 0));         // MIE = 0, MPIE = 0
    emit(SW(9, 176, 0));                    // the memory op that may wait
    emit(NOP);
    emit(CSRRW(0, CSR_MEPC, 12));
    emit(MRET);
    emit(ADDI(26, 0, 12'hBAD));             // skipped
    L_mret_t2 = pc;
    emit(CSRRS(20, CSR_MSTATUS, 0));        // read only: 0x1880
    emit(SW(20, 180, 0));
    emit(CSRRSI(0, CSR_MSTATUS, 5'd8));     // MIE = 1 again (MPIE is already 1)
    gm(176, 32'h5A5); gm(180, 32'h1880);

    // ---------- end ----------
    emit(ADDI(30, 0, 99));
    prog_end = pc;
    emit(JALO(0, 0));                 // park

    gr(24, 32'd0, "no exception ran");
    gr(26, 32'd0, "skipped instrs not run");
    gr(30, 32'd99, "end marker");

    if (pass == 1 && pc > 4000) $display("*** inst_memory: main program too long (ends at %0d) ***", pc);
end
endtask

initial begin
    for (i = 0; i < DEPTH*4; i = i + 1)
        mem[i] = 8'h00;

    if (DEPTH < 512) $display("*** inst_memory: this image needs DEPTH >= 512 (tb_sweep.v sets it with a defparam) ***");

    for (pass = 0; pass < 2; pass = pass + 1)
        build;
end

assign data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};

endmodule