# RV32I RISC-V Processor with Priority-Based Nested Interrupts (5-Stage Pipeline)

A **32-bit RV32I RISC-V Processor** implemented in **Verilog HDL** and built up in stages: a single-cycle design, converted into a **5-stage pipelined implementation** (IF → ID → EX → MEM → WB), then given hazard control (full data forwarding and load-use stall handling), then **BTFNT static branch prediction** (backward-taken, forward-not-taken: a branch that jumps backward, like a loop, is guessed taken; one that jumps forward is guessed not taken), and finally extended with **machine-mode trap handling for two external interrupt sources (keyboard, disk) with hardware priority tracking and software-managed nesting**.

The design implements the **RV32I Base Integer Instruction Set** using a modular datapath, plus privileged-mode logic (`mepc`, `mcause`, `mtvec`, `mie`, `mret`, current/previous priority registers, and the `csrrw`/`csrrs`/`csrrc` family) so that multiple interrupt sources are handled correctly across all pipeline hazard conditions, including interrupts nesting inside one another.

---

## Features

- 32-bit RV32I architecture
- **5-stage pipelined datapath**: IF, ID, EX, MEM, WB
- Dedicated pipeline registers: `IF_ID_reg`, `ID_EX_reg`, `EX_MEM_reg`, `MEM_WB_reg`
- **Full data forwarding**: `forwarding_unit` + `forward_mux` resolve RAW hazards from EX/MEM and MEM/WB (ALU operands, store data/address, `jalr` base, CSR reads)
- **Load-use stall detection**: `stall_unit` inserts a one-cycle bubble when a load's result is needed by the next instruction
- **BTFNT static branch prediction** (backward-taken, forward-not-taken): predicted in IF from the sign of the branch offset, resolved in EX; mispredicts and jumps flush `IF_ID_reg` and `ID_EX_reg`
- **Two external interrupt sources (keyboard, disk)**, each with its own pending latch (`interrupt_latch`)
- **Priority-based arbitration**: `interrupt_priority_encoder` reports the highest pending source (disk = 2, keyboard = 1, none = 0). A trap is taken only if that level is **>= the level currently running** (`current_priority`)
- **Hardware priority save/restore**: on trap entry `previous_priority <= current_priority` and `current_priority <= interrupt_ID`; `mret` restores `current_priority <= previous_priority`
- **Vectored traps**: PC redirects to `mtvec + 4 * cause` (keyboard cause 7, disk cause 27); the losing source's pending bit is *not* dropped
- **Software-managed nesting, arbitrary depth**: the ISR saves `mepc`, `mcause`, `previous_priority` and any live GPRs on a stack in `data_memory` *before* re-enabling `mie`; verified 3 levels deep
- Register file with same-cycle write-read bypass
- Data memory with byte/halfword/word access and sign/zero-extended loads (also serves as the interrupt stack)
- Self-checking Verilog testbench with an expected-trap scoreboard

---

## Project Structure

```text
.
├── alu.v
├── alu_decoder.v
├── alu_mux.v
├── csr_addr_decoder.v            # CSR address -> write-enable for mepc/mie/mcause/current_priority/previous_priority
├── csr_read_data.v               # selects old CSR value returned to rd
├── csr_write_data.v              # selects new CSR value to write, per funct3
├── current_priority.v            # priority level of the code currently running (0 = main program)
├── previous_priority.v           # level that was interrupted; restored into current_priority by mret
├── interrupt_priority_encoder.v  # pending keyboard/disk -> interrupt_ID (2 = disk, 1 = keyboard, 0 = none)
├── interrupt_latch.v             # per-source pending latch (keyboard + disk instances)
├── data_memory.v
├── instruction_memory.v
├── main_decoder.v
├── mcause.v                      # trap cause register (7 = keyboard, 27 = disk)
├── mepc.v                        # PC of the instruction that was interrupted
├── mie.v                         # interrupt enable (cleared on trap, set by mret / CSR write)
├── mtvec.v                       # trap vector base address (100)
├── pc.v
├── pc_mtvec_mcause.v             # trap target = mtvec + 4 * cause
├── pc_mux.v
├── pc_plus_4.v
├── pc_target.v
├── register_file.v
├── result_mux.v
├── sign_extender.v
├── IF_stage.v / IF_ID_reg.v
├── ID_stage.v / ID_EX_reg.v
├── EX_stage.v / EX_MEM_reg.v
├── MEM_stage.v / MEM_WB_reg.v
├── forwarding_unit.v             # RAW hazard detection (EX/MEM, MEM/WB)
├── forward_mux.v                 # 3-input operand select
├── stall_unit.v                  # load-use hazard detection
├── top.v                         # pipeline + interrupt logic top module
├── tb.v
└── README.md
```

---

## Pipeline Architecture

```text
IF_stage → IF_ID_reg → ID_stage → ID_EX_reg → EX_stage → EX_MEM_reg → MEM_stage → MEM_WB_reg → result_mux → (register file)
```

- **IF**: PC register, PC+4 adder, branch predictor, PC mux (trap / EX redirect / `mret` / predicted target / PC+4), instruction memory
- **ID**: register file read (with write bypass), immediate extension, control decode, `mret` detection (redirects PC to `mepc` from here)
- **EX**: ALU, branch resolution, `jalr`/`auipc` handling, CSR read/write value computation, trap-acceptance point
- **MEM**: data memory access, load sign/zero-extension
- **WB**: `result_mux` selects ALU result / memory data / PC+4 / old CSR value

### Hazard Control

- **Forwarding**: EX/MEM has priority over MEM/WB. The EX/MEM candidate is `ALUResult` normally, `PC+4` for `jal`/`jalr`, and the old CSR value for CSR reads.
- **Stalling**: a load in EX whose destination matches a source of the instruction in ID holds the pipeline one cycle. Stalling is suppressed while an `mret` is in ID (its `rs2` field bits are not a register, so it would otherwise stall falsely).
- **Flush**: a mispredicted branch or a jump resolves in EX and flushes the two younger instructions.

---

## Interrupt Handling

### Trap acceptance

A trap is taken in a cycle when **all** of these hold:

```text
interrupt_taken = mie
                & (interrupt_ID != 0)
                & (interrupt_ID >= current_priority)
                & EX is not a bubble
                & EX is not an mret
```

The last two conditions guarantee `mepc` never captures a bogus PC (a bubble has PC 0; an `mret` in EX has already redirected fetch).

### What happens on trap entry

- `mepc <= PC` of the instruction in EX (that instruction is squashed and re-executed after `mret`)
- `mcause <= cause code`, `mie <= 0`
- `previous_priority <= current_priority`, `current_priority <= interrupt_ID`
- IF/ID, ID/EX and EX/MEM are flushed; PC <= `mtvec + 4 * cause`
- The served source's pending bit is cleared; the other source's stays set

### What happens on `mret`

- PC <= `mepc` (redirected from the ID stage)
- `mie <= 1`, `current_priority <= previous_priority`
- A wrong-path `mret` (behind a mispredicted branch) is ignored for these updates

### Priority and nesting rules

| Running at | Disk (2) asserts | Keyboard (1) asserts |
|---|---|---|
| Main program (0) | taken | taken |
| Keyboard ISR (1) | taken (nests, 2 >= 1) | taken (self-nests, 1 >= 1) |
| Disk ISR (2) | taken (self-nests) | **blocked** (1 < 2) until disk's `mret` |

Both sources at once: disk wins; keyboard stays pending and fires after disk's `mret`.

### ISR structure

Identical body for both sources (24 instructions, reached through a `jal` trampoline at each vector):

1. Allocate a 32-byte stack frame; save `x6`, `x7`, `mepc`, `mcause`, `previous_priority`
2. `mie <= 1` (nesting now allowed, gated by the priority compare)
3. Body (increments a counter and deliberately clobbers `x6`/`x7` to prove save/restore works)
4. `mie <= 0` (epilogue must be atomic), restore `mcause`, `mepc`, `previous_priority`, `x6`, `x7`, free the frame, `mret`

### CSR map (custom addresses)

| Address | CSR |
|---|---|
| 0 | `mepc` |
| 1 | `mie` |
| 2 | `mcause` |
| 3 | `current_priority` |
| 4 | `previous_priority` |

---

## Supported Instructions

All **37 RV32I base instructions**, plus machine-mode trap support:

| Category | Instructions |
|---|---|
| R-type ALU | `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and` |
| I-type ALU | `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai` |
| Loads | `lb`, `lh`, `lw`, `lbu`, `lhu` |
| Stores | `sb`, `sh`, `sw` |
| Branches | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu` |
| Jumps | `jal`, `jalr` |
| Upper immediate | `lui`, `auipc` |
| Privileged | `mret`, `csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci` |

---

## Verification Status

`tb.v` is self-checking: it pulses the interrupt inputs at chosen PCs, compares every trap against an expected `{cause, mepc}` table, and checks final register/CSR state. A passing run prints `=== ALL CHECKS PASSED ===`.

| Phase | Scenario | Traps |
|---|---|---|
| A | Keyboard alone | 1 |
| B | Disk alone | 1 |
| C | Simultaneous: disk first, keyboard after disk's `mret` | 2 |
| D | Keyboard outer, disk nests (2 >= 1) | 2 |
| E | Disk outer, keyboard **blocked** by priority (1 < 2) until `mret` | 2 |
| F | Keyboard self-nests, 2 levels | 2 |
| G | Disk asserted while `mie = 0`; held, fires when `mie` re-enabled | 2 |
| H | Keyboard self-nests, 3 levels | 3 |

Checked at the end of every phase: `sp` back to 200, live registers `x6`/`x7` intact despite ISR clobbering, trap counter matches the number of traps logged. Final checks also cover `mie = 1`, `current_priority = 0`, no pending bits left, and a deepest stack use of 3 frames. Also verified: all 37 RV32I instructions, forwarding (including CSR reads), load-use stalls (including `lw` → `csrrw` in the ISR), branch/jump flush, x0 write immunity.

All Zicsr instructions are exercised: `csrrs`, `csrrw`, `csrrwi` by the interrupt test suite (ISR save/restore), and `csrrc`, `csrrsi`, `csrrci` by a separate short test program whose read-back values (`x10`–`x13` and `mepc`) were checked against expected results, including forwarding into `csrrc` and back-to-back CSR instructions.

### Known limitations

- Interrupt inputs must be **1-cycle pulses**: the latch is level-sensitive, so an input held high re-latches right after being served.
- A CSR write is not forwarded to `mret`: `mepc` and `previous_priority` must be written at least one instruction before `mret` (the ISR does this).
- `csrrs`/`csrrc` with `rs1 = x0` still write the (unchanged) value back; the RISC-V spec says they should not write.
- Priority scheme is fixed at two levels (keyboard 1, disk 2); adding sources means widening the priority registers and encoder.

---

## Development Environment

- Visual Studio Code, GitHub Desktop
- Verilog HDL, Icarus Verilog, GTKWave, Git, GitHub

---

## Running the Simulation

```bash
iverilog -o sim_out *.v
vvp sim_out
gtkwave waves.vcd
```

On Windows, GTKWave can be launched with `"C:\iverilog\gtkwave\bin\gtkwave.exe" waves.vcd`.

---

## Version Control

- `main` — current 5-stage pipeline with forwarding, stalling and priority-based nested interrupts
- `pipeline` — development branch where forwarding/stalling and interrupt handling were built and verified before merging

The original single-cycle implementation remains in the commit history prior to the pipeline merge.

---

## Author

**Shreyas Vaidya**

---

## License

This project is shared for **educational and learning purposes**.