# RV32I RISC-V Processor with Machine-Mode Interrupt Handling (Single-Cycle → 5-Stage Pipeline)

A **32-bit RV32I RISC-V Processor** implemented in **Verilog HDL**, originally built as a single-cycle design, converted into a **5-stage pipelined implementation** (IF → ID → EX → MEM → WB) with full data forwarding and load-use stall handling, and now extended with **machine-mode trap handling for two external interrupt sources (keyboard, disk) with software-managed nesting**.

This project implements the **RV32I Base Integer Instruction Set Architecture (ISA)** using a modular datapath, plus privileged-mode logic (`mepc`, `mcause`, `mtvec`, `mie`, `mret`, plus `csrrw`/`csrrs`/`csrrwi`) to handle multiple external interrupt sources correctly across all pipeline hazard conditions, including interrupts nesting inside one another. The design is divided into independent RTL modules, making it easier to understand, verify, and extend into more advanced processor architectures.

---

## Features

- 32-bit RV32I architecture
- **5-stage pipelined datapath**: IF, ID, EX, MEM, WB
- Dedicated pipeline registers: `IF_ID_reg`, `ID_EX_reg`, `EX_MEM_reg`, `MEM_WB_reg`
- **Full data forwarding**: `forwarding_unit` + `forward_mux` resolve RAW hazards from EX/MEM and MEM/WB, covering ALU-operand forwarding, store-data forwarding, store-address forwarding, jalr base-register forwarding, and CSR-read forwarding
- **Load-use stall detection**: `stall_unit` inserts a one-cycle bubble when a load's result is needed by the immediately following instruction
- **Branch/jump flush**: `IF_ID_reg` and `ID_EX_reg` flush on a taken branch or jump, resolved in EX
- **Multi-source external interrupt handling (keyboard + disk)**: each source has its own pending latch (`interrupt_latch`); a pending, enabled interrupt redirects the PC to a vectored trap address (`mtvec + 4*mcause`), captures the trapped instruction's PC in `mepc`, and clears `mie` until `mret`
- **Fixed-priority arbitration on simultaneous requests**: disk always wins a same-cycle tie; the losing source's pending bit is *not* dropped — it persists and fires as soon as `mie` is next re-enabled
- **Software-managed interrupt nesting, arbitrary depth**: the ISR explicitly saves `mepc`/`mcause` (via non-destructive `csrrs`) and any live GPRs it uses to a stack in `data_memory` *before* re-enabling `mie`, so a nested trap can safely overwrite the hardware CSRs without losing the outer trap's state; verified to at least 3 levels deep
- Modular RTL design, one module per pipeline stage
- Separate control decoding (`main_decoder`, `alu_decoder`) inside the ID stage
- Arithmetic Logic Unit (ALU)
- Register File with same-cycle write-read bypass
- Program Counter (PC) with branch/jump/trap redirect muxing
- Instruction Memory
- Data Memory with byte/halfword/word width control and sign/zero-extended loads, doubling as the interrupt-nesting stack
- Sign Extension Unit
- Multiplexers for datapath control
- Verilog testbench for functional verification

---

## Project Structure

```text
.
├── alu.v
├── alu_decoder.v
├── alu_mux.v
├── csr_addr_decoder.v       # maps CSR address field to mepc/mie/mcause write-enables
├── csr_read_data.v          # selects old CSR value returned to rd
├── csr_write_data.v         # selects new CSR value to write, per funct3
├── data_memory.v
├── instruction_memory.v
├── interrupt_latch.v        # per-source pending-interrupt latch (keyboard + disk instances)
├── main_decoder.v
├── mcause.v                 # trap cause register (7=keyboard, 27=disk)
├── mepc.v                   # trapped-instruction PC capture register
├── mie.v                    # interrupt-enable register (cleared on trap, set on mret/CSR write)
├── mtvec.v                  # trap vector base address
├── pc.v
├── pc_mtvec_mcause.v        # trap target address computation (mtvec + 4*mcause)
├── pc_mux.v
├── pc_plus_4.v
├── pc_target.v
├── register_file.v
├── result_mux.v
├── sign_extender.v
├── IF_stage.v
├── IF_ID_reg.v
├── ID_stage.v
├── ID_EX_reg.v
├── EX_stage.v
├── EX_MEM_reg.v
├── MEM_stage.v
├── MEM_WB_reg.v
├── forwarding_unit.v        # RAW hazard detection (EX/MEM, MEM/WB)
├── forward_mux.v            # 3-input operand select (regfile / EX-MEM / MEM-WB)
├── stall_unit.v             # load-use hazard detection
├── top.v                    # pipeline top module
├── tb.v
├── .gitignore
└── README.md
```

---

## Pipeline Architecture

```text
IF_stage → IF_ID_reg → ID_stage → ID_EX_reg → EX_stage → EX_MEM_reg → MEM_stage → MEM_WB_reg → result_mux → (write-back into register file)
```

- **IF**: PC register, PC+4 adder, branch/jump/trap target mux, instruction memory
- **ID**: register file read (with same-cycle write bypass), immediate sign-extension, control signal decode (`main_decoder`, `alu_decoder`), `mret` detection
- **EX**: ALU, ALU-source mux, PC-target adder, branch decision, `jalr`/`auipc` muxing, CSR read/write value computation — operands arrive pre-resolved via `forward_mux` before reaching this stage
- **MEM**: data memory access, load sign/zero-extension based on `Funct3`
- **WB**: result mux (ALU result / memory data / PC+4 / CSR read value) selects final write-back value; no dedicated WB module — `result_mux` is instantiated directly in `top.v`

### Hazard Control

- **Forwarding**: `forwarding_unit` compares the ID/EX-stage instruction's `rs1`/`rs2` against `EX_MEM_reg`'s and `MEM_WB_reg`'s destination register, with EX/MEM given priority when both match. The EX/MEM candidate is `ALUResult` for most instructions, `PC+4` for `jal`/`jalr`, and the old CSR value for CSR reads (`ResultSrc==2'b11`) — this last case matters because the ISR's `csrrs`-then-store sequences are a real forwarding hazard, not a cosmetic one.
- **Stalling**: `stall_unit` detects a load in EX whose destination matches a source register of the instruction in ID, and holds the pipeline for one cycle. The CSR-restore sequences in the ISR (`lw` immediately followed by `csrrw`) are a real, verified instance of this hazard.
- **Flush**: a taken branch or jump resolves in EX and flushes the two younger, wrong-path instructions in `IF_ID_reg` and `ID_EX_reg`.
- **Interrupt trap**: an enabled, pending interrupt takes priority over branch/jump redirect at the PC mux, flushes `IF_ID_reg` and `ID_EX_reg`, captures the EX-stage instruction's PC into `mepc`, records the cause in `mcause`, clears `mie`, and redirects fetch to the vectored trap address. `mret` restores fetch to `mepc`.

### Interrupt Arbitration & Nesting

- Two independent pending latches (keyboard, disk); on a simultaneous request, **disk always wins** the current cycle. Keyboard's request is *not* lost — its pending bit stays set and it is serviced automatically the moment `mie` is next re-enabled (including mid-ISR, i.e. it can nest into the very interrupt that just preempted it).
- The trap handler is intentionally **source-agnostic**: identical code at both vectors, saving `mepc`, `mcause`, and any live GPRs it touches before re-enabling `mie`. This makes true nesting safe at arbitrary depth, since each level's state lives in its own stack frame rather than in the (single, shared) hardware CSRs.
- **Current priority scheme is fixed, not configurable**: disk unconditionally outranks keyboard on ties; there is no priority register or preemption of a lower-priority ISR by a lower-priority-but-still-pending request. A currently-running ISR can only be preempted by a *source whose own trap fires* once `mie` allows it — not by explicit priority comparison. Extending this to a real priority scheme (e.g. a priority-encoded `mie`/priority register, or letting a higher-priority source preempt a lower-priority ISR mid-body rather than waiting for its own `mie` re-enable point) is a planned next step, not yet implemented.

---

## Supported Instructions

All **37 RV32I base instructions** have been individually verified through the pipeline, plus machine-mode trap handling:

| Category | Instructions |
|---|---|
| R-type ALU | `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and` |
| I-type ALU | `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai` |
| Loads | `lb`, `lh`, `lw`, `lbu`, `lhu` |
| Stores | `sb`, `sh`, `sw` |
| Branches | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu` |
| Jumps | `jal`, `jalr` |
| Upper immediate | `lui`, `auipc` |
| Privileged (machine-mode) | `mret`, `csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci` (custom CSR addresses: 0=`mepc`, 1=`mie`, 2=`mcause`) |

> Verification method: instruction functionality was first exercised via hazard-free (NOP-padded) sequences; forwarding and stalling were then verified against dedicated hazard-adversarial sequences. Interrupt handling was verified in two stages: a single-source baseline (7 timing-adversarial cases), then extended to a two-source, 8-phase suite covering baseline/simultaneous/cross-nesting/self-nesting/unsafe-window/3-level-nesting, run in Icarus Verilog and cross-checked by hand in GTKWave. See inline comments in `instruction_memory.v` for the mnemonic and purpose of every instruction.

---

## Verification Status

- ✅ All 37 RV32I instructions functionally correct in isolation (the "37" is the RV32I base count and doesn't include the Zicsr extension — see below for that)
- ✅ Pipeline register timing confirmed (4-cycle IF→WB latency)
- ✅ Branch/jump redirect target computation confirmed correct
- ✅ x0 write-immunity confirmed
- ✅ Signed vs. unsigned comparison/shift correctness confirmed
- ✅ EX/MEM and MEM/WB forwarding confirmed, including the CSR-read forwarding case (found and fixed: `EX_MEM_Candidate` previously had no case for CSR-read results)
- ✅ Load-use stalling confirmed, including the `lw`-then-`csrrw` CSR-restore sequences in the ISR
- ✅ Branch/jump flush confirmed — no wrong-path instruction reaches write-back
- ✅ Multi-source interrupt handling confirmed against 8 phases: keyboard alone, disk alone, simultaneous (disk-wins tiebreak, keyboard's request preserved), keyboard→disk nesting, disk→keyboard nesting, 2-level self-nesting, interrupt asserted during the `mie=0` unsafe window (held, fires exactly on re-enable), and 3-level self-nesting
- ✅ GPR save/restore confirmed under nesting: live registers deliberately clobbered inside the ISR are restored correctly even through 3 levels of nesting
- ✅ Stack balance confirmed: `sp` returns to its initial value after every phase, at every nesting depth reached
- ⚠️ Zicsr coverage is partial: `csrrs`, `csrrw`, `csrrwi` are exercised by the interrupt test suite (via the ISR's save/restore sequence). `csrrc`, `csrrsi`, `csrrci` are decoded correctly by `main_decoder`/`alu_decoder` per the truth table, but no test program has actually executed one yet — worth a dedicated test before calling Zicsr support "verified" rather than just "implemented"

---

## Development Environment

- Visual Studio Code
- GitHub Desktop

---

## Tools Used

- Verilog HDL
- Icarus Verilog
- GTKWave
- Git
- GitHub

---

## Requirements

- Icarus Verilog
- GTKWave

---

## Running the Simulation

### Compile the design

```bash
iverilog -o sim_out *.v
```

### Run the simulation

```bash
vvp sim_out
```

### View the waveform

Windows:

```bash
"C:\iverilog\gtkwave\bin\gtkwave.exe" waves.vcd
```

If GTKWave is available in your system PATH:

```bash
gtkwave waves.vcd
```

---

## Version Control

This project is version-controlled using **Git** and hosted on **GitHub**.

- `main` — tracks the current 5-stage pipeline implementation with forwarding and stalling
- `pipeline` — development branch where forwarding/stalling and interrupt handling (single-source, then multi-source with nesting) were built and verified before merging to `main`

The original single-cycle implementation remains available in the commit history prior to the pipeline merge into `main`.

---

## Author

**Shreyas Vaidya**

---

## License

This project is shared for **educational and learning purposes**.