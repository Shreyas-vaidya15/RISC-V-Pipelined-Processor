# RV32I RISC-V Processor with Priority-Based Nested Interrupts and Exceptions (5-Stage Pipeline)

A **32-bit RV32I RISC-V Processor** implemented in **Verilog HDL** and built up in stages: a single-cycle design, converted into a **5-stage pipelined implementation** (IF → ID → EX → MEM → WB), then given hazard control (full data forwarding and load-use stall handling), then **BTFNT static branch prediction** (backward-taken, forward-not-taken: a branch that jumps backward, like a loop, is guessed taken; one that jumps forward is guessed not taken), then extended with **machine-mode trap handling for two external interrupt sources (keyboard, disk) with hardware priority tracking and software-managed nesting**, and finally with **synchronous exceptions** (illegal instruction, misaligned and faulting memory accesses, `ecall`, `ebreak`).

The control and status registers (CSRs) follow the **official RISC-V privileged spec**: standard CSR addresses, `mstatus` bit layout, `mie`, `mip`, `mtvec` (with direct/vectored mode), `mtval`, `mscratch` and `misa`. The only non-standard CSRs are the two priority registers, placed in the spec's custom machine-mode address range.

---

## Features

- 32-bit RV32I architecture, machine mode only
- **5-stage pipelined datapath**: IF, ID, EX, MEM, WB
- Dedicated pipeline registers: `IF_ID_reg`, `ID_EX_reg`, `EX_MEM_reg`, `MEM_WB_reg`
- **Full data forwarding**: `forwarding_unit` + `forward_mux` resolve RAW hazards from EX/MEM and MEM/WB (ALU operands, store data/address, `jalr` base, CSR reads)
- **Load-use stall detection**: `stall_unit` inserts a one-cycle bubble when a load's result is needed by the next instruction
- **BTFNT static branch prediction**: predicted in IF from the sign of the branch offset, resolved in EX; mispredicts and jumps flush `IF_ID_reg` and `ID_EX_reg`
- **Real `nop` bubbles**: a flushed or stalled slot holds `addi x0, x0, 0` (`0x00000013`) as the spec requires, and a `Valid` bit travels with each instruction so the core can tell a bubble from a real `nop`
- **Two external interrupt sources (keyboard, disk)**, each with its own pending latch (`interrupt_latch`); both are reported as machine external interrupts (cause 11)
- **Priority-based arbitration**: `interrupt_priority_encoder` reports the highest pending source (disk = 2, keyboard = 1, none = 0). A trap is taken only if that level is **strictly greater than** the level currently running (`current_priority`)
- **Hardware priority save/restore**: on trap entry `previous_priority <= current_priority` and `current_priority <= interrupt_ID`; `mret` restores `current_priority <= previous_priority`
- **Software-managed nesting**: a handler saves `mepc`, `mcause`, `previous_priority` and any live registers on a stack in `data_memory` *before* re-enabling `mstatus.MIE`
- **Exceptions** raised from ID and EX, each with its spec cause code and an `mtval` value (see [Exceptions](#exceptions))
- **Official CSR set**: `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, plus custom `current_priority` / `previous_priority`
- **Writable `mtvec`** with direct and vectored modes
- `csrrs`/`csrrc`/`csrrsi`/`csrrci` with `rs1`/`uimm` = 0 only read, as the spec requires
- CSR write bypasses so an `mret` or a trap in ID sees a CSR write that is still in EX
- Register file with same-cycle write-read bypass
- Data memory with byte/halfword/word access and sign/zero-extended loads (also serves as the interrupt stack)
- Self-checking Verilog testbench that sweeps an interrupt across every cycle of a program

---

## Project Structure

```text
.
├── alu.v
├── alu_decoder.v
├── alu_mux.v
├── csr_addr_decoder.v            # CSR address -> "which CSR is addressed" select signals
├── csr_read_data.v               # selects the old CSR value returned to rd
├── csr_write_data.v              # selects the new CSR value to write, per funct3
├── current_priority.v            # priority level of the code currently running (0 = main program)
├── previous_priority.v           # level that was interrupted; restored into current_priority by mret
├── interrupt_priority_encoder.v  # pending keyboard/disk -> interrupt_ID (2 = disk, 1 = keyboard, 0 = none)
├── interrupt_latch.v             # per-source pending latch (keyboard + disk instances)
├── data_memory.v
├── instruction_memory.v          # program image for the interrupt sweep (built by an initial block)
├── main_decoder.v
├── illegal_function.v            # illegal funct3 / funct7 detection
├── illegal_csr_addr.v            # CSR address that is not implemented
├── misaligned_detect.v           # misaligned load/store (EX)
├── load_store_access_fault.v     # data address outside data memory (EX)
├── instruction_address_misalign.v# taken branch/jump to a target with bit 1 set (EX)
├── instruction_access_fault.v    # fetch address outside instruction memory (IF)
├── mepc.v                        # PC of the instruction that trapped
├── mcause.v                      # trap cause register
├── mtval.v                       # extra trap info (bad address / instruction bits)
├── mtvec.v                       # trap vector base + mode (writable, resets to 0x65)
├── mie.v                         # mstatus.MIE (global interrupt enable)
├── mpie.v                        # mstatus.MPIE (MIE saved on trap entry)
├── mie_csr.v                     # mie CSR (0x304): per-source enables
├── mscratch.v                    # scratch register for software
├── misa.v                        # hardwired RV32I
├── pc.v
├── pc_mtvec_mcause.v             # trap target from mtvec mode, base and cause
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
├── top.v                         # pipeline + interrupt/exception logic top module
├── tb.v                          # interrupt sweep testbench (module tb_sweep)
└── README.md
```

---

## Pipeline Architecture

```text
IF_stage → IF_ID_reg → ID_stage → ID_EX_reg → EX_stage → EX_MEM_reg → MEM_stage → MEM_WB_reg → result_mux → (register file)
```

- **IF**: PC register, PC+4 adder, branch predictor, PC mux (trap / EX redirect / `mret` / predicted target / PC+4), instruction memory, instruction access fault check
- **ID**: register file read (with write bypass), immediate extension, control decode, illegal-instruction detection, `mret` detection (redirects PC to `mepc` from here)
- **EX**: ALU, branch resolution, `jalr`/`auipc` handling, CSR read/write value computation, misaligned and access-fault detection, interrupt acceptance point
- **MEM**: data memory access, load sign/zero-extension
- **WB**: `result_mux` selects ALU result / memory data / PC+4 / old CSR value

### Hazard Control

- **Forwarding**: EX/MEM has priority over MEM/WB. The EX/MEM candidate is `ALUResult` normally, `PC+4` for `jal`/`jalr`, and the old CSR value for CSR reads.
- **Stalling**: a load in EX whose destination matches a source of the instruction in ID holds the pipeline one cycle. Stalling is suppressed while an `mret` is in ID (its `rs2` field bits are not a register, so it would otherwise stall falsely).
- **Flush**: a mispredicted branch or a jump resolves in EX and flushes the two younger instructions.

---

## CSR Map

| Address | CSR | Notes |
|---|---|---|
| `0x300` | `mstatus` | Read: `MIE` at bit 3, `MPIE` at bit 7, `MPP` (bits 12:11) fixed to `11`. Write: only `MIE` and `MPIE` change |
| `0x301` | `misa` | Hardwired `0x40000100` (32-bit, base `I`). Writes ignored |
| `0x304` | `mie` | Per-source enables. Only bit 11 (external) and bit 7 (timer) are stored |
| `0x305` | `mtvec` | Resets to `0x65` (base `0x64`, vectored mode). Bit 1 is forced to 0; bit 0 is the mode |
| `0x340` | `mscratch` | Plain read/write |
| `0x341` | `mepc` | Low 2 bits forced to 0 on write |
| `0x342` | `mcause` | Writable |
| `0x343` | `mtval` | Writable |
| `0x344` | `mip` | Read-only. Bit 11 = keyboard or disk pending. Writes ignored |
| `0x7C0` | `current_priority` | Custom (spec's custom machine-mode range). Level of the running code |
| `0x7C1` | `previous_priority` | Custom. Level that was interrupted |

Accessing any other CSR address raises an illegal-instruction exception (cause 2).

Reset values: `MIE` = 0 and `MPIE` = 0, so **interrupts are off after reset**. Software must set `mie[11]` and then `mstatus.MIE` before an interrupt can be taken.

---

## Interrupt Handling

### Trap acceptance

A trap is taken in a cycle when **all** of these hold:

```text
interrupt_taken = mstatus.MIE
                & mie[11]
                & (interrupt_ID != 0)
                & (interrupt_ID > current_priority)
                & EX is not a bubble
                & EX is not an mret
```

The last two conditions guarantee `mepc` never captures a bogus PC (a bubble has no real PC; an `mret` in EX has already redirected fetch). Keyboard and disk share the single external-interrupt enable (`mie[11]`); the priority registers are what tell them apart.

### What happens on trap entry

- `mepc <= PC` of the instruction in EX (that instruction is squashed and re-executed after `mret`)
- `mcause <= 0x8000000B` (interrupt bit set, cause 11 = machine external), `mtval <= 0`
- `mstatus.MPIE <= mstatus.MIE`, then `mstatus.MIE <= 0`
- `previous_priority <= current_priority`, `current_priority <= interrupt_ID`
- IF/ID, ID/EX and EX/MEM are flushed
- PC <= trap target (see below)
- The served source's pending bit is cleared; the other source's stays set

### Trap vector

`mtvec` holds a base address and a mode in bit 0:

| Mode (`mtvec[0]`) | Interrupts go to | Exceptions go to |
|---|---|---|
| 0 (direct) | base | base |
| 1 (vectored) | base + 4 × cause | base |

After reset `mtvec = 0x65`, so base = `0x64` and mode = vectored. Both interrupt sources have cause 11, so they land at `0x64 + 44 = 0x90` (144). Exceptions land at `0x64` (100).

### What happens on `mret`

- PC <= `mepc` (redirected from the ID stage)
- `mstatus.MIE <= mstatus.MPIE`, `mstatus.MPIE <= 1`
- `current_priority <= previous_priority`
- A wrong-path `mret` (behind a mispredicted branch) is ignored for these updates
- If an `mepc`, `previous_priority` or `mstatus` write is still in EX when the `mret` is in ID, the `mret` uses the value being written (CSR write bypass)

### Priority and nesting rules

The comparison is strict (`>`), as in the spec-style PLIC rule: a source cannot interrupt a handler of its own level.

| Running at | Disk (2) asserts | Keyboard (1) asserts |
|---|---|---|
| Main program (0) | taken | taken |
| Keyboard ISR (1) | taken (nests, 2 > 1) | **blocked** (1 is not > 1) until keyboard's `mret` |
| Disk ISR (2) | **blocked** (2 is not > 2) until disk's `mret` | **blocked** (1 < 2) until disk's `mret` |

Both sources at once: disk wins; keyboard stays pending and fires after disk's `mret`. With two sources, nesting is at most keyboard → disk.

### Handler structure

A handler that wants to allow nesting should:

1. Allocate a stack frame; save any live registers, `mepc`, `mcause` and `previous_priority`
2. Set `mstatus.MIE` (nesting is now possible, still gated by the priority compare)
3. Do the work
4. Clear `mstatus.MIE` (the epilogue must not be interrupted), restore the saved CSRs and registers, free the frame, `mret`

---

## Exceptions

Exceptions are synchronous: they come from the instruction itself. They use the same trap machinery as interrupts, with `mcause[31] = 0`.

| Cause | Meaning | Detected in | `mtval` holds |
|---|---|---|---|
| 0 | Instruction address misaligned (taken branch / `jal` / `jalr` target has bit 1 set) | EX | the bad target address |
| 1 | Instruction access fault (fetch address outside instruction memory) | ID (flag set in IF) | the fetch PC |
| 2 | Illegal instruction | ID | the instruction bits |
| 3 | `ebreak` | ID | 0 |
| 4 | Load address misaligned | EX | the bad address |
| 5 | Load access fault (address outside data memory) | EX | the bad address |
| 6 | Store address misaligned | EX | the bad address |
| 7 | Store access fault (address outside data memory) | EX | the bad address |
| 11 | `ecall` | ID | 0 |

**Illegal instruction** covers: unknown opcode, illegal `funct3`, illegal `funct7`, an unimplemented CSR address, and a SYSTEM instruction with `funct3 = 000` whose immediate is not `ecall`, `ebreak`, `mret` or `wfi`.

**Rules**

- `mepc` is the PC of the instruction that caused the exception (for `ecall`/`ebreak` the handler must add 4 itself before `mret`).
- On entry `mstatus.MPIE <= mstatus.MIE` and `mstatus.MIE <= 0`.
- An interrupt in the same cycle wins; the instruction is squashed and re-faults after `mret`.
- An exception from EX squashes the instruction in EX. An exception from ID lets the older instruction in EX finish first.
- An exception behind a mispredicted branch or a jump is on the wrong path and is ignored.
- When several causes occur in the same cycle, the order is: misaligned access, load/store access fault, instruction address misaligned, instruction access fault, `ecall`, `ebreak`, illegal instruction.
- Exceptions do not change `current_priority`.

**Memory sizes** (word counts, set by parameters): data memory `DEPTH = 64` words (256 bytes, `DATA_DEPTH` in `top.v`); instruction memory `DEPTH = 256` words by default (set in `IF_stage`; the testbench overrides it to 1024).

---

## Supported Instructions

All **40 RV32I base instructions**, the Zicsr CSR instructions, plus machine-mode trap support:

| Category | Instructions |
|---|---|
| R-type ALU | `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and` |
| I-type ALU | `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai` |
| Loads | `lb`, `lh`, `lw`, `lbu`, `lhu` |
| Stores | `sb`, `sh`, `sw` |
| Branches | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu` |
| Jumps | `jal`, `jalr` |
| Upper immediate | `lui`, `auipc` |
| System | `ecall`, `ebreak`, `mret` |
| Zicsr | `csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci` |
| Treated as `nop` | `fence`, `wfi` |

---

## Verification Status

`tb.v` (module `tb_sweep`) is self-checking and pairs with `instruction_memory.v`, which builds one deterministic program with Verilog functions that act as a small assembler. The program has no exceptions and uses only `mscratch`, `misa` and `mie` among the CSRs, so a transparent interrupt handler (it only increments `x23`) must leave everything else identical to a run with no interrupt.

| Part | What it does |
|---|---|
| 1. Reference run | Runs with no interrupt. Checks the final registers and data memory against golden values written next to the program, then saves the final state |
| 2. Sweep | For each kind (keyboard, disk, both in the same cycle) and each injection cycle from 0 to the end of the program plus 8, resets, delivers one 1-cycle pulse, runs to the end marker, and compares against the reference run |
| 3. Reset in a handler | Resets 0 to 14 cycles after a trap is taken, checks every piece of trap state is back at its reset value, then reruns the whole program and compares |

The program covers an interrupt landing on: back-to-back ALU forwarding, loads and stores of every width, load-use stalls, loops (predicted-taken branches and loop-exit mispredicts), every branch type, `jal`/`jalr`, CSR instructions whose result is used immediately, a window with `mstatus.MIE = 0`, and `csrrw mepc` followed directly by `mret`.

Compared on every run: all registers except `x23`, every byte of data memory, `mscratch`, `mie`, `mtvec`, `mstatus.MIE`, `mstatus.MPIE`, `current_priority`, the interrupt count in `x23`, no exceptions taken, and no pending bits left. The testbench also prints which instruction addresses an interrupt was actually taken on. A passing run prints `=== ALL CHECKS PASSED ===`.

### Known limitations

- Interrupt inputs must be **1-cycle pulses**: the latch is level-sensitive, so an input held high re-latches right after being served.
- Priority scheme is fixed at two levels (keyboard 1, disk 2); adding sources means widening the priority registers and encoder.
- Keyboard and disk share `mie[11]`; there is no per-source enable. `mie[7]` (timer) is stored but there is no timer source yet.
- `mstatus` writes only affect `MIE` and `MPIE`; `MPP` always reads `11`. Writes to `misa` and `mip` are ignored without an exception.
- `fence` and `wfi` are treated as `nop`.
- Misaligned loads and stores trap instead of being handled in hardware.
- The register file and data memory have no reset; the testbench clears them itself on every reset.

---

## Development Environment

- Visual Studio Code, GitHub Desktop
- Verilog HDL, Icarus Verilog, GTKWave, Git, GitHub

---

## Running the Simulation

```bash
iverilog -s tb_sweep -o sim_out *.v
vvp sim_out
```

`-s tb_sweep` selects the testbench as the top module. To also write a waveform file:

```bash
iverilog -DDUMP -s tb_sweep -o sim_out *.v
vvp sim_out
gtkwave waves_sweep.vcd
```

On Windows, GTKWave can be launched with `"C:\iverilog\gtkwave\bin\gtkwave.exe" waves_sweep.vcd`.

---

## Version Control

- `main` — current 5-stage pipeline with forwarding, stalling, priority-based nested interrupts, exceptions and the official-spec CSR set
- `pipeline` — development branch where forwarding/stalling and interrupt handling were built and verified before merging

The original single-cycle implementation remains in the commit history prior to the pipeline merge.

---

## Author

**Shreyas Vaidya**

---

## License

This project is shared for **educational and learning purposes**.