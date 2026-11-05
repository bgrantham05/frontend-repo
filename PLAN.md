# Frontend implementation plan

Based on the supplied October 31, 2026 specification and checked-in interfaces.
Work through one step per review. Do not change shared packages or interfaces.

## 1. Correct synchronous fetch
- Use RESET_PC, request PC and PC+4, and advance by eight without rounding down.
- Track request PC with the synchronous ROM response.
- Hold response during stalls; redirect takes priority and invalidates old work.
- Preserve errors as valid instruction slots for later fault handling.
- Add directed tests for reset, sequential reads, stalls, redirects to PC=4, errors.
- Status: implemented; testbench written, simulation pending simulator availability.

## 2. Implement instruction decode (current step)
- Build a combinational decoder returning decoded_uop_t, then instantiate two lanes.
- Decode RV32I ALU, immediate, shifts, loads/stores, branches, jumps, LUI/AUIPC,
  and Zicsr with exact encoding checks and correct immediate extension.
- Preserve fetch metadata; flag illegal encodings and suppress unintended writes.
- Test instruction categories, negative immediates, x0, and illegal encodings.
- Coordinate system instruction/exception semantics absent from current types.
- Status: single-lane decoder and two-lane wrapper implemented in
  common/instr_decode.sv; directed tests in tb/frontend_decode_tb.sv.
- Encoding checks and whitespace checks passed; RTL simulation remains pending.
- ECALL, EBREAK, FENCE/FENCE.I and privileged operations are currently flagged
  unsupported. Their execution/exception semantics require instructor/backend
  coordination before this step can claim full system-instruction support.
- Backend agreement needed: jumps use ALU PC+4 for the link result and separate
  PC/rs1 plus immediate for the target. CSR commands preserve rd and rs1/zimm
  fields so the backend can apply Zicsr read/write suppression rules.

## 3. Add ordered buffering
- Define frontend-local metadata; retain unaccepted instructions in order.
- Support accepted prefixes of 0, 1, or 2; compact remaining lane 1 into lane 0.
- Reserve storage for synchronous ROM responses; keep stalled packets stable.
- Test partial acceptance, full stalls, simultaneous replacement, and flushes.
- Fetch currently uses whole-bundle ready/valid; this stage adapts to partial dispatch.

## 4. Implement tournament prediction and BTB
- Confirm Group 1 assignment before implementing its assigned predictor.
- Choose local history/counter, gshare, chooser, and BTB sizes explicitly.
- Gshare XORs PC bits with global history; local prediction uses PC-indexed history.
- Retain prediction-time indexes and predictions for training and accuracy counters.
- A taken lane-0 prediction suppresses younger lane 1.
- Follow the current one-unresolved-branch contract unless a change is coordinated.
- Clarify how actual direction/target comes from existing backend resolution fields.
- Test saturation, chooser training, BTB misses/conflicts, and wrong targets.

## 5. Implement register renaming
- Initialize RAT[x]=x, reserve p0, and initially free p32 through p63.
- Read sources before destination updates; bypass same-bundle RAW/WAW dependencies.
- Allocate only accepted instructions writing nonzero rd; save old mapping for ROB.
- Reclaim old mappings at retirement; test exhaustion and duplicate allocation.
- Coordinate checkpoint/free-list recovery with steps 6 and 7.

## 6. Implement ROB and retirement
- Allocate 16 entries in program order only for accepted dispatch instructions.
- Match both completion channels using full generation/index tags and valid bits.
- Retire completed instructions in order using the interface's single retire event.
- Handle full/empty, simultaneous allocation/retirement, and wraparound.
- Test out-of-order completions, stale tags, and repeated wraparound.
- Clarify stale-response lifetime: finite generation bits eventually alias.

## 7. Implement coordinated recovery
- Choose one consistent recovery scheme, preserving older unretired instructions.
- Do not restore only committed RAT state while keeping older live instructions
  unless their mappings are reconstructed.
- Define checkpoint timing, free-list reclamation, ROB survivors, predictor history,
  and checkpoint release on a correct branch resolution.
- Stop dispatch on every branch-resolution event as the interface requires.
- On misprediction, invalidate younger work and redirect; reject stale completions.
- Test older incomplete work, younger writes, stalls, and repeated recovery.
- Coordinate exceptions: current completion structures have no explicit fault fields.

## 8. Integrate and validate
- Add frontend top level exposing provided ROM and backend modports.
- Connect fetch, buffer, dual decode, predictor, rename, dispatch, ROB, and recovery.
- Mock backend: partial acceptance, out-of-order completion, and branch resolution.
- Check retirement order and mappings against a reference model; stress resource
  exhaustion, long stalls, ROB wraparound, and recovery.
- Run simulation/lint and FPGA synthesis checks; document remaining limitations.

## Verification
No SystemVerilog simulator was found on PATH during initial inspection. Written
checks are not passing tests until simulated. Example Questa/ModelSim commands:

```text
vlib work
vlog -sv common/rv32_ooo_pkg.sv common/instruction_memory_pkg.sv common/instruction_memory_if.sv common/instr_fetch.sv tb/frontend_fetch_tb.sv
vsim -c frontend_fetch_tb -do "run -all; quit -f"
vlog -sv common/rv32_ooo_pkg.sv common/instr_decode.sv tb/frontend_decode_tb.sv
vsim -c frontend_decode_tb -do "run -all; quit -f"
```
