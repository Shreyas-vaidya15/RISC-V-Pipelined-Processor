# RV32I RISC-V Processor with Nested Interrupts, Exceptions and an AHB-Lite Data Bus (5-Stage Pipeline)

A **32-bit RV32I RISC-V Processor** implemented in **Verilog HDL** and built up in stages: a single-cycle design, converted into a **5-stage pipelined implementation** (IF → ID → EX → MEM → WB), then given hazard control (full data forwarding and load-use stall handling), then **BTFNT static branch prediction** (backward-taken, forward-not-taken: a branch that jumps backward, like a loop, is guessed taken; one that jumps forward is guessed not taken), then extended with **machine-mode trap handling for two external interrupt sources (keyboard, disk) with hardware priority tracking and software-managed nesting**, then with **synchronous exceptions** (illegal instruction, misaligned memory accesses, `ecall`, `ebreak`, instruction faults), and finally with an **AHB-Lite data bus**: the data memory now sits outside the CPU as an AHB slave that can insert **wait states** and answer with an **ERROR response**, which the CPU turns into a load/store access-fault exception.

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
- **AHB-Lite data bus** (CPU = master, data memory = slave) with **wait states** (`HREADY` freezes the pipeline) and a **two-cycle ERROR response** (`HRESP`)
- **Two external interrupt sources (keyboard, disk)**, each with its own pending latch (`interrupt_latch`); both are reported as machine external interrupts (cause 11)
- **Priority-based arbitration**: `interrupt_priority_encoder` reports the highest pending source (disk = 2, keyboard = 1, none = 0). A trap is taken only if that level is **strictly greater than** the level currently running (`current_priority`)
- **Hardware priority save/restore**: on trap entry `previous_priority <= current_priority` and `current_priority <= interrupt_ID`; `mret` restores `current_priority <= previous_priority`
- **Software-managed nesting**: a handler saves `mepc`, `mcause`, `previous_priority` and any live registers on a stack in data memory *before* re-enabling `mstatus.MIE`
- **Exceptions** raised from ID, EX and WB, each with its spec cause code and an `mtval` value (see [Exceptions](#exceptions))
- **Older-transfer hold**: an exception never overtakes an older load/store that is still on the bus (see [Older-transfer hold](#older-transfer-hold))
- **Official CSR set**: `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, plus custom `current_priority` / `previous_priority`
- **Writable `mtvec`** with direct and vectored modes
- `csrrs`/`csrrc`/`csrrsi`/`csrrci` with `rs1`/`uimm` = 0 only read, as the spec requires
- CSR write bypasses so an `mret` or a trap in ID sees a CSR write that is still in EX
- Register file with same-cycle write-read bypass
- Self-checking Verilog testbench that sweeps an interrupt across every cycle of a program, in four wait-state modes, with bus errors in the program

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
├── instruction_memory.v          # program image (built by an initial block, see Verification)
├── main_decoder.v
├── illegal_function.v            # illegal funct3 / funct7 detection
├── illegal_csr_addr.v            # CSR address that is not implemented
├── misaligned_detect.v           # misaligned load/store (EX)
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
├── load_extend.v                 # sign/zero-extends HRDATA for lb/lh/lw/lbu/lhu (WB)
├── IF_stage.v / IF_ID_reg.v
├── ID_stage.v / ID_EX_reg.v
├── EX_stage.v / EX_MEM_reg.v
├── MEM_WB_reg.v
├── forwarding_unit.v             # RAW hazard detection (EX/MEM, MEM/WB)
├── forward_mux.v                 # 3-input operand select
├── stall_unit.v                  # load-use hazard detection
├── AHB_master_CPU_interface.v    # EX/MEM register outputs -> AHB-Lite master signals
├── data_memory.v                 # byte-organised memory array (little-endian)
├── AHB_data_memory.v             # AHB-Lite slave: wait states, ERROR response, wraps data_memory
├── top.v                         # the CPU: pipeline + interrupt/exception logic + bus master side
├── soc_top.v                     # CPU + AHB data slave, connected by the bus
├── tb.v                          # interrupt sweep testbench (module tb_sweep)
└── README.md
```

There is no separate MEM-stage module: the data memory is outside the CPU, so the MEM stage is just the `EX_MEM_reg` outputs driving the bus (`AHB_master_CPU_interface`).

---

## Pipeline Architecture

```text
IF_stage → IF_ID_reg → ID_stage → ID_EX_reg → EX_stage → EX_MEM_reg → (AHB bus) → MEM_WB_reg → load_extend / result_mux → (register file)
```

- **IF**: PC register, PC+4 adder, branch predictor, PC mux (trap / EX redirect / `mret` / predicted target / PC+4), instruction memory, instruction access fault check
- **ID**: register file read (with write bypass), immediate extension, control decode, illegal-instruction detection, `mret` detection (redirects PC to `mepc` from here)
- **EX**: ALU, branch resolution, `jalr`/`auipc` handling, CSR read/write value computation, misaligned-access detection, interrupt acceptance point
- **MEM**: the **address phase** of a load/store goes out on the bus (`HADDR`, `HWRITE`, `HSIZE`, `HTRANS`) from the `EX_MEM_reg` outputs
- **WB**: the **data phase** of the same load/store happens while it sits in WB (`HRDATA` comes back, `HWDATA` goes out, a bus ERROR arrives). `load_extend` extends the data, `result_mux` selects ALU result / memory data / PC+4 / old CSR value

### Hazard Control

- **Forwarding**: EX/MEM has priority over MEM/WB. The EX/MEM candidate is `ALUResult` normally, `PC+4` for `jal`/`jalr`, and the old CSR value for CSR reads.
- **Stalling**: a load in EX whose destination matches a source of the instruction in ID holds the pipeline one cycle. Stalling is suppressed while an `mret` is in ID (its `rs2` field bits are not a register, so it would otherwise stall falsely).
- **Flush**: a mispredicted branch or a jump resolves in EX and flushes the two younger instructions.
- **Bus wait (`HREADY` low)**: the whole pipeline freezes (see below).

---

## AHB-Lite Data Bus

The CPU (`top.v`) is an AHB-Lite **master**; `AHB_data_memory.v` is the **slave**. `soc_top.v` joins them. With one slave, `HSEL` is tied to 1 and the bus-wide `HREADY` is simply the slave's `HREADYOUT`.

### Master side (`AHB_master_CPU_interface.v`)

| Signal | Driven by |
|---|---|
| `HADDR` | `ALUResult_MEM` (the load/store address) |
| `HWRITE` | `MemWrite_MEM` |
| `HSIZE` | `{1'b0, Width_MEM}` (byte / halfword / word) |
| `HTRANS` | NONSEQ (`2'b10`) when a load or store is in MEM, otherwise IDLE (`2'b00`). Forced to IDLE in the last cycle of an ERROR response (`HRESP & HREADY`), which cancels the transfer that would otherwise be accepted in that cycle |
| `HWDATA` | `RD2_WB` (store data, one cycle after the address phase) |

### Wait states (`HREADY` low)

While `HREADY = 0` everything is frozen: `EX_MEM_reg` and `MEM_WB_reg` hold, the front of the pipeline (`pc`, `IF_ID_reg`, `ID_EX_reg`) holds, and nothing acts: no register write, no CSR write, no interrupt, no exception. A frozen stage acts **once**, in the last cycle (the one where `HREADY = 1`). All bus signals driven by the master stay unchanged while `HREADY` is low (the one allowed change is `HTRANS` going to IDLE in the last cycle of an ERROR response).

### Slave (`AHB_data_memory.v`)

A four-state FSM drives the response wires. Outputs depend only on the state:

| State | `HREADYOUT` | `HRESP` | `HRDATA` | Meaning |
|---|---|---|---|---|
| `OKAY` | 1 | 0 | memory data | ready |
| `WAIT` | 0 | 0 | `0xBAD0BAD0` | inserting wait states |
| `ERR1` | 0 | 1 | 0 | first ERROR cycle |
| `ERR2` | 1 | 1 | 0 | second (last) ERROR cycle |

- **Wait states**: `WAIT_CYCLES` (a 4-bit input, a test knob) is the number of wait states given to each accepted transfer (0 = none).
- **Out-of-range address**: `HADDR >= DEPTH * 4` (start address only; `DEPTH` is in words, default 64 = 256 bytes) gives an ERROR response. Wait states come first, then the two-cycle ERROR.
- **Writes**: the address phase is saved and the write happens in the data phase, only when `HREADYOUT = 1` and `HRESP = 0`, so a bad store never writes anything.
- Misaligned accesses never reach the slave: they trap in EX first.

Not implemented yet: more than one slave (address decoder, per-slave `HSEL`, `HRDATA`/`HREADYOUT`/`HRESP` mux, default slave for unmapped addresses). Known gap that does not affect this SoC: in `ERR2` the slave ignores a transfer that the master did not cancel.

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
                & HREADY                 (bus not waiting: a frozen stage acts once)
                & no bus error this cycle
                & no load/store in MEM
```

- The bubble and `mret` conditions guarantee `mepc` never captures a bogus PC (a bubble has no real PC; an `mret` in EX has already redirected fetch).
- **No interrupt while a load/store is in MEM.** Otherwise the interrupt would squash the instruction in EX but let the older transfer finish, and a bus error from that transfer would arrive as a second trap right after the interrupt, overwriting `mepc` and `MPIE`. The interrupt just waits one cycle. Because of this, the instructions right behind a load/store are never interrupted (by design).
- Keyboard and disk share the single external-interrupt enable (`mie[11]`); the priority registers are what tell them apart.

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
- An `mret` acts once even if it waits in ID for a hold or a bus wait

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
| 5 | Load access fault: the slave answered a load with an **ERROR response** | WB (bus response) | the bad address |
| 6 | Store address misaligned | EX | the bad address |
| 7 | Store access fault: the slave answered a store with an **ERROR response** | WB (bus response) | the bad address |
| 11 | `ecall` | ID | 0 |

**Illegal instruction** covers: unknown opcode, illegal `funct3`, illegal `funct7`, an unimplemented CSR address, and a SYSTEM instruction with `funct3 = 000` whose immediate is not `ecall`, `ebreak`, `mret` or `wfi`.

### Load/store access faults come from the bus

There is no address-range check in the CPU. The slave is the only judge of out-of-range addresses, and the CPU learns about it from the ERROR response:

- The ERROR response lasts two cycles (`HRESP = 1`: `ERR1` with `HREADY = 0`, then `ERR2` with `HREADY = 1`). The CPU traps in the **last** cycle: `bus_error = HRESP & HREADY`.
- The faulting load/store is in **WB** at that moment. So `mepc = PC_Plus_4_WB - 4`, `mtval = ALUResult_WB`, and the cause is 5 for a load (`IsLoad_WB`) or 7 for a store.
- A faulting load does **not** write `rd` (the register write is blocked in the trap cycle, so `rd` keeps its old value). A faulting store writes nothing to memory (the slave blocks the write while `HRESP` is high). The slave returns `HRDATA = 0` during the ERROR.
- In that cycle `HTRANS` is forced to IDLE so no new transfer starts. The instructions younger than the faulting one (in EX, ID, IF) are squashed and re-run after `mret`.

### Rules

- `mepc` is the PC of the instruction that caused the exception (for `ecall`/`ebreak` the handler must add 4 itself before `mret`; for a bus error the handler adds 4 to skip the faulting load/store, or fixes the cause).
- On entry `mstatus.MPIE <= mstatus.MIE` and `mstatus.MIE <= 0`.
- **Priority when several things happen in the same cycle**: bus error > interrupt > exception from EX > exception from ID. The bus error belongs to the oldest instruction (WB), so it always goes first. An interrupt beats an exception: the instruction is squashed and re-faults after `mret`.
- An exception from EX squashes the instruction in EX. An exception from ID lets the older instruction in EX finish first.
- An exception behind a mispredicted branch or a jump is on the wrong path and is ignored.
- When several causes occur in the same cycle, the order is: bus error, misaligned access, instruction address misaligned, instruction access fault, `ecall`, `ebreak`, illegal instruction.
- Exceptions do not change `current_priority`; the entry saves it into `previous_priority`.

**Memory sizes** (word counts, set by parameters): data memory `DEPTH = 64` words (256 bytes, parameter of `AHB_data_memory`); instruction memory `DEPTH = 256` words by default (set in `IF_stage`; the testbench overrides it to 1024, which the sweep image needs).

---

## Older-transfer hold

**Problem.** An exception B (from EX or ID) taken while an **older** load/store A is in MEM would trap first. Then A's bus error would trap a second time, overwriting `mepc` and `MPIE`. A is older, so A must be allowed to finish first.

An interrupt can simply wait (see the gate above), but an exception cannot move on, so it waits one cycle:

| Case | What happens during the hold |
|---|---|
| **`ex_hold`**: exception pending in **EX** (misaligned access, bad jump/branch target) with a load/store in MEM | B stays in EX. `pc`, `IF_ID_reg` and `ID_EX_reg` freeze (`pipe_ready` low); `EX_MEM_reg` takes a bubble, so B's own access never reaches the bus. `ID_EX_reg` also **captures B's forwarded operands**, because the instruction that supplied them leaves the pipeline during the hold and the forwarding source disappears |
| **`id_hold`**: exception pending in **ID** (illegal, `ecall`, `ebreak`, fetch fault) with a load/store in MEM | B stays in ID. Treated like the load-use stall: `pc` and `IF_ID_reg` freeze, `ID_EX_reg` takes a bubble. The older instruction in EX moves on normally |

Next cycle A is in WB. If A errors, `bus_error` traps for A and squashes B (B re-runs after `mret`). If not, B traps normally. There is no deadlock: after the hold, MEM holds a bubble (or an older instruction that is not stuck), so the gate turns off. An ID instruction behind a mispredicted branch or jump is on the wrong path and is flushed, not held.

The holds only matter when `HREADY = 1`; while `HREADY` is low everything is frozen anyway.

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

## Verification

### Interrupt sweep with wait states and bus errors (`tb_sweep`)

`tb.v` (module `tb_sweep`) is self-checking and tests `soc_top` (CPU + AHB slave). It pairs with `instruction_memory.v`, which builds one deterministic program with Verilog functions that act as a small assembler. A passing run prints `=== ALL CHECKS PASSED ===`.

**The program.** It takes **14 exceptions on purpose** (11 bus errors + 3 exceptions from EX) and reads only CSRs whose values a trap would not change (`mscratch`, `misa`, `mie`, and `mstatus` only in windows where `MIE = 0`). Both handlers are **transparent**:

- the **interrupt handler** only increments `x23`;
- the **exception handler** counts the exception in `x24`, skips the faulting instruction (`mepc += 4`) using `x26` as scratch, clears `x26` again and does `mret`.

So with the same exceptions taken, everything except `x23` must be identical to a run with no interrupt.

| Section | What it covers |
|---|---|
| S1 | back-to-back ALU forwarding, shifts, `slt`/`sltu`, `lui` |
| S2 | stores/loads of every width, store-to-load, load-use stalls |
| S3 / S3b | loops (backward-taken branches, loop-exit mispredict, load-use in a loop); every branch type, taken / not taken, forward / backward |
| S4 | `jal` / `jalr`, call and return, `jalr` to a computed address |
| S5 | `mscratch` `csrrw`/`csrrs`/`csrrc`/`csrrsi` with the result used at once, `misa` read |
| S6 | `mstatus.MIE = 0` window, then `csrrw mepc ; mret` back to back |
| S7 | CSR / load-pointer / `mret` cases right behind a memory op (checks that a frozen stage acts once during wait states) |
| S8 | **bus errors**: bad load, bad store, a good access right behind a bad one, back-to-back bad accesses, a bad access inside a loop, a bad load right before a mispredicted branch and before a `jal` |
| S9 | **operand capture during the older-transfer hold**: an EX exception (misaligned load, misaligned store, taken branch with a misaligned target) right behind a load/store, with the operand it needs coming from a producer one place before that load/store. The stale operand would give a different result (no exception, a load that runs, a store that writes) |

**Wait modes.** The whole test is run once per mode:

| Mode | Slave behaviour | Reference run length |
|---|---|---|
| 0 | no wait states | 579 cycles |
| 1 | every transfer waits 1 cycle | 660 cycles |
| 2 | every transfer waits 2 cycles | 741 cycles |
| 3 | pseudo-random 0..3 waits per transfer (fixed per cycle number) | 701 cycles |

**Parts of each mode**

| Part | What it does |
|---|---|
| 1. Reference run | Runs with no interrupt. Checks the final registers and data memory against golden values written next to the program, checks that exactly 14 exceptions were taken and that the image caused at least 3 older-transfer holds, then saves the final state |
| 2. Sweep | For each kind (keyboard, disk, both in the same cycle) and each injection cycle from 0 to the end of the program plus 8, resets, delivers one 1-cycle pulse, runs to the end marker, and compares against the reference run |
| 3. Reset in a handler | Resets 0 to 14 cycles after a trap is taken, checks every piece of trap state (CPU and slave) is back at its reset value, then reruns the whole program and compares |
| 3b. Reset in an error response | Resets 0 to 5 cycles after an ERROR response starts (the first, a middle and the last error of the program), checks the reset state, then reruns and compares |

**Compared on every run:** all registers except `x23`, every byte of data memory, `mscratch`, `mie`, `mtvec`, `mstatus.MIE`, `mstatus.MPIE`, `current_priority`, the interrupt count in `x23`, **the number of exceptions equals the reference run's**, no pending bits left, bus idle and slave idle at the end.

**Monitors that run every cycle**

- **AHB hold monitor**: if `HREADY` was low in the previous cycle, `HADDR`/`HTRANS`/`HWRITE`/`HSIZE`/`HWDATA` must be unchanged, with one exception: in the last cycle of an ERROR response `HTRANS` may change to IDLE.
- **Bus error monitor**: in every bus-error cycle `HTRANS` is IDLE, no register is written, no interrupt or other exception is taken, and the slave is in `ERR2`. In the next cycle `mepc`/`mcause`/`mtval` must hold the faulting load/store's PC, cause 5 or 7, and the bad address (the instruction at that PC must really be a load or a store, and the address must be outside data memory). It also counts how often an interrupt was ready to fire in the very cycle of a bus error (the bus error must win; this must happen at least once).
- **Coverage check**: for every instruction address where the interrupt gate was open at least once in the reference run, the sweep must have landed an interrupt there. A miss is a "hole" and fails the test. Addresses that are never open are blocked by design: before `MIE` is on, inside `MIE = 0` windows, right behind a load/store, and on `mret`.

**Result (from the run that was checked):** 8763 runs across the four modes, **0 failures, 0 coverage holes**, `=== ALL CHECKS PASSED ===` in all four modes. In the reference run, 137 of 197 executed instruction addresses were open to an interrupt (an interrupt landed on all of them); the other 60 are blocked by design as listed above.

### Known limitations

- Interrupt inputs must be **1-cycle pulses**: the latch is level-sensitive, so an input held high re-latches right after being served.
- Priority scheme is fixed at two levels (keyboard 1, disk 2); adding sources means widening the priority registers and encoder.
- Keyboard and disk share `mie[11]`; there is no per-source enable. `mie[7]` (timer) is stored but there is no timer source yet.
- `mstatus` writes only affect `MIE` and `MPIE`; `MPP` always reads `11`. Writes to `misa` and `mip` are ignored without an exception.
- `fence` and `wfi` are treated as `nop`.
- Misaligned loads and stores trap instead of being handled in hardware.
- A single AHB slave (`HSEL` tied to 1); no address decoder or default slave yet.
- Interrupts are not taken while a load/store is in MEM (they wait one cycle).
- The slave's `ERR2` ignores a transfer accepted in that cycle if the master did not cancel it (the CPU master always cancels).
- The register file and data memory have no reset; the testbench clears them itself on every reset.

---

## Development Environment

- Visual Studio Code, GitHub Desktop
- Verilog HDL, Icarus Verilog, GTKWave, Git, GitHub

---

## Running the Simulation

The `-s` name must match the testbench module in `tb.v` (`tb_sweep`), and the matching `instruction_memory.v` image must be in the folder.

```bash
iverilog -s tb_sweep -o sim_out *.v
vvp sim_out
```

To also write a waveform file for the sweep:

```bash
iverilog -DDUMP -s tb_sweep -o sim_out *.v
vvp sim_out
gtkwave waves_sweep.vcd
```

On Windows, GTKWave can be launched with `"C:\iverilog\gtkwave\bin\gtkwave.exe" waves_sweep.vcd`.

---

## Version Control

- `main` — current 5-stage pipeline with forwarding, stalling, priority-based nested interrupts, exceptions, the official-spec CSR set and the AHB-Lite data bus
- `pipeline` — development branch where forwarding/stalling and interrupt handling were built and verified before merging

The original single-cycle implementation remains in the commit history prior to the pipeline merge.

---

## Author

**Shreyas Vaidya**

---

## License

This project is shared for **educational and learning purposes**.