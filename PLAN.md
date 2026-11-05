# Frontend implementation plan

Based on the supplied October 31, 2026 specification and checked-in interfaces.
Work through one step per review. Do not change shared packages or interfaces.

## Architecture and data movement (CDR implementation notes)

The descriptions below follow checked-in RTL and the supplied October 31 spec.
Implemented means RTL exists, not that simulation or FPGA validation has passed.
Future structures are proposed internal designs; unresolved external semantics
must be coordinated with the backend/instructors before implementation.

```text
request PC registers -> synchronous instruction ROM -> held response + PC
                                                     |
                 predictor/BTB (planned) -> prediction + lane validity
                                                     |
                                       four-slot ready buffer
                                                     |
                                    two combinational decoders
                                                     |
                                  rename + dispatch admission (planned)
                                       /                      \
                              ROB allocation              backend dispatch
                                   ^                           |
                                   +---- two completion lanes -+
                                   |
                            head-only retirement -> free old physical register

backend branch resolution -> predictor update + checkpoint release/recovery
backend misprediction     -> invalidate younger ROB work + restore rename state
                          -> flush ready buffer + redirect fetch
```

Prediction, rename, ROB, recovery, and a connected frontend top level are not yet
implemented. br_pred.sv, reg_rename.sv, and reorder_buff_retire.sv are placeholders.
The ready buffer and decoder are standalone modules at this stage.

### Fetch state and the ROM boundary 

- request_pc_q is the address of the next requested pair. response_pc_q and
  response_valid_q identify the ROM's held response. RESET_PC initializes fetch.
- The existing ROM interface returns 64 bits at one base byte address: low word
  at PC, high word at PC+4. It does not expose independently addressed ports.
  Each enabled clock edge updates both words and both error bits synchronously.
- A read is permitted when the response is empty or its current bundle is accepted.
  The same edge records the requested PC and advances request_pc_q by eight.
  A stalled response holds its PC and ROM output; no replacement read is issued.
- Redirect suppresses reads and old valid outputs immediately, invalidates the
  response at the edge, and installs the exact target, including targets at PC=4.
  The target read occurs on the following edge. Reset and recovery take priority.
- Faulting words remain valid with error metadata. Neither fetch nor the buffer
  silently drops an error; exception execution semantics still need coordination.

### Ready-buffer and decoder boundary

fetch_slot_t is a frontend-private packed record with 32-bit PC, 32-bit instruction,
32-bit predicted_next_pc, and one fetch_error bit (97 bits total). Four records
plus occupancy form the queue; this costs 388 payload bits and three count bits.
The existing elastic_buffer remains useful for whole transactions, but cannot by
itself compact a two-instruction transaction after partial acceptance.

Planned wiring: fetch downstream_ready_i connects to buffer input_ready_o. Without
prediction, input_count is 2 when fetch_valid0_o is asserted and otherwise 0;
each slot's predicted_next_pc is its own PC+4. The response can transfer to the
queue while the ROM simultaneously supplies the next pair. Queue capacity is
reserved for the held response before permitting that transfer/read replacement.
The ROM response is an additional holding location outside the four queue slots.

The queue presents a contiguous prefix of zero, one, or two raw instructions.
The existing frontend_decode_pair wrapper decodes the two payloads; output_count
determines which decoded lanes are meaningful. The decoders have no state and do
not dequeue instructions. Rename/dispatch returns the number actually accepted;
only that prefix is removed. Unaccepted raw payloads and their decoded meanings
remain stable. If lane 0 advances, the old lane 1 moves to lane 0. A newly available
second lane may appear while a single held head stays unchanged.

Example: the queue holds A,B,C,D and accepts only A. It retains B,C,D, cannot take
a new two-word bundle yet, and presents B,C next cycle. If B alone then advances,
there is room to append E,F on that same edge, leaving C,D,E,F. No instruction is
lost, duplicated, or passed by a younger instruction.

When prediction is added, retain the selected next PC with each surviving slot.
A taken prediction in lane 0 sends only lane 0 to the queue and invalidates lane 1;
a taken lane 1 allows both lanes. Prediction redirects must preserve the branch
and older queued instructions. They must NOT use the global recovery flush that
discards the queue. Fetch redirection and queue flush therefore need distinct
internal controls at integration. No such prediction wiring exists today.

### Decode records (implemented, system semantics incomplete)

Each decoder constructs decoded_uop_t combinationally from one raw slot. It
preserves PC/instruction/predicted next PC/error, extracts rs1/rs2/rd and immediate,
and emits ALU, operand mux, memory, branch, and CSR controls. Immediate extension
and exact funct3/funct7 legality checks are in RTL. frontend_decode_pair provides
two lanes; meaningful-lane count is carried outside decoded_uop_t.
Unsupported system instructions are flagged illegal today. This is an incomplete
exception contract, not full implementation of all required system instructions.

### Tournament predictor and BTB 

The CDR specifies tournament prediction, consistent with Group 1's assignment;
confirm team assignment before implementation. Planned structures are a
PC-indexed local-history table, local two-bit counter table indexed by that history,
global history register, gshare two-bit counter table indexed by PC XOR global
history, chooser two-bit counters, and a tagged valid/target BTB. Table sizes and
history widths remain to be chosen explicitly in step 4; none are RTL parameters yet.
The XOR belongs in gshare indexing. The local component uses PC to select history,
then that history to select a direction counter.

The chooser selects a component's direction. A taken direction needs a usable
target; a BTB miss falls back to sequential fetch until a target is available.
Retain prediction-time local/global indexes, component predictions, selected
direction/target, and branch identity for later training. Train counters on actual
outcome, train the chooser when components disagree, and count resolved predictions
and correct predictions for accuracy. Direct/indirect jump handling must be defined.
Begin with resolution-updated history to avoid speculative history rollback;
speculative history, if later added, needs its own checkpoint/recovery design.

Current branch resolution fields carry a tag, misprediction bit, and PC, but no
explicit actual-taken bit or distinct actual-target field. Agree on their meaning
and how to obtain training direction/target before connecting predictor updates.

### Rename and dispatch state 

Use 32 six-bit speculative RAT entries initialized RAT[x]=x; x0 always maps to p0.
Use a 32-entry circular free-register FIFO initialized with p32 through p63, read
and write pointers, and occupancy. Retiring one destination returns its old mapping;
the allocated destination remains live. Instructions without a nonzero destination
consume neither a free register nor a RAT update.

Compute lane 0 source mappings from the current RAT before changing its destination.
Compute lane 1 against the tentative RAT after lane 0, so same-cycle RAW forwards
lane 0's new mapping and WAW saves that mapping as lane 1's old destination.
Build renamed_uop_t with decoded controls, physical sources/destination, full ROB
tag, and under_unresolved_branch; keep old_pdst in frontend ROB metadata.

Offer only a prefix for which physical registers, ROB entries, and the one-unresolved-
branch rule permit admission. Commit RAT/free-list/ROB changes ONLY for backend
dispatch_accept_count on that edge. Unaccepted candidates can be recomputed from
the held raw queue entries; they must not consume resources. Actual resource
reservation and backend stalled-offer stability rules need verification in step 5.
On every branch_resolve_valid event dispatch acceptance must be zero, including
correct predictions. Resource availability controls dispatch admission; it propagates
to the queue and then fetch when local holding capacity fills.

### ROB storage, completion, and retirement

Use 16 entries storing valid, complete, full tag, decoded metadata, new/old physical
destination, has_destination, and completion value. Maintain head/tail tags and an
occupancy count. Each tag has four index bits and two generation bits; increment
the logical tag on allocation, carrying into generation at index wraparound.
Compare age by modular distance from the live head, not by ordinary generation
ordering. Retain valid/full-tag checks when a slot is reused after recovery.

Allocate only accepted dispatch lanes in program order. Both completion channels
can mark matching live entries complete out of order; PRF writeback is separately
qualified by writeback_valid. Retire at most one complete head per cycle because
the interface exposes a single retire event. Publish rob_head_tag for backend
head-only operations. Retirement removes the entry and reclaims old_pdst when
has_destination; simultaneous retirement/allocation must account for freed capacity.
Two generation bits do not solve arbitrarily delayed stale completions: coordinate
the maximum response lifetime/tag reuse contract with the backend.

### Recovery organization and the CDR dirty/clean proposal
Use one unresolved control-flow checkpoint under the current shared bundle contract.
Take a full speculative RAT snapshot at the branch boundary, after the branch's
own destination mapping (e.g. JAL link) and before any younger lane's mapping.
Track its branch ROB tag. On correct resolution release the checkpoint and clear
the younger-work tracking state on both sides under the agreed backend protocol.
Do not admit a second unresolved branch until the first checkpoint is released.

On a misprediction, keep the branch and older ROB entries, invalidate only younger
entries, restore the boundary RAT, flush queued/fetched younger work, and redirect
fetch to the agreed recovery PC. Reclaim the physical destinations allocated by
squashed ROB entries exactly once. Do not simply restore an old free-list pointer:
older instructions may have retired and returned registers since the checkpoint.
One possible implementation scans the at-most-16 ROB entries during recovery and
stalls allocation until reclamation finishes; precise timing is a step 7 decision.

A committed/clean RAT may be maintained on retirement for architectural tracking,
but copying it directly over the speculative RAT while keeping older unretired
instructions is incorrect. The branch snapshot includes those older mappings;
the committed RAT does not. The CDR's dirty/clean description must therefore use
branch-boundary state for branch recovery, or reconstruct older live mappings.
Exception recovery remains unresolved because current completion types have no
explicit exception/fault fields. Do not claim precise exceptions are implemented.

Recovery wins over stalls and normal state updates. Define simultaneous retirement,
completion, and recovery ordering before coding; reject completions for invalidated
tags and coordinate backend cancellation/PRF stale-write protection. Frontend ROB
tag checking alone cannot protect backend physical-register writes after reuse.

### Progress, verification, and integration dependencies

Fetch, dual decode, elastic_buffer, and the ordered ready buffer have RTL. Fetch,
decode, and ready-buffer testbenches exist; simulation remains pending. Rename,
predictor, ROB, recovery, and top-level wiring remain planned. The CDR statement
that testbenches have not been started is therefore out of date.

Next verification layers are buffer/fetch integration with a synchronous ROM model,
rename dependency/resource tests, ROB completion/age/tag tests, predictor training,
and full frontend tests with a mock backend. A reference instruction stream should
check accepted dispatch and retirement order across partial acceptance, prolonged
stalls, redirects, and repeated recovery. Resource stress must exhaust the 32 free
destinations, rather than allocate p0 or assume all 64 registers start free.

Before system integration, coordinate branch resolution PC/direction/target,
unsupported system instruction and fault handling, one-unresolved-branch lifetime,
stale result cancellation, and stalled dispatch-offer requirements. Shared packages
and interfaces remain unchanged by this step.

## 1. Correct synchronous fetch
- Use RESET_PC, request PC and PC+4, and advance by eight without rounding down.
- Track request PC with the synchronous ROM response.
- Hold response during stalls; redirect takes priority and invalidates old work.
- Preserve errors as valid instruction slots for later fault handling.
- Add directed tests for reset, sequential reads, stalls, redirects to PC=4, errors.
- Status: implemented; testbench written, simulation pending simulator availability.

## 2. Implement instruction decode
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
- Status: implemented standalone in common/frontend_ready_buffer.sv with private
  fetch_slot_t in common/frontend_local_pkg.sv. Directed and randomized scoreboard
  tests are in tb/frontend_ready_buffer_tb.sv; RTL simulation pending.
- Integration with fetch, decode, and eventual rename/dispatch remains step 8.
- Organization: four compacted instruction slots and a three-bit occupancy count.
  Each slot holds PC, instruction, predicted next PC, and per-instruction ROM error.
  Valid entries occupy indexes 0 through count-1; no per-slot valid bits are needed.
- Present the oldest min(count, 2) entries. On an edge, remove the accepted prefix,
  shift survivors toward slot 0, and append the incoming prefix after survivors.
  This is a small register array, not a circular FIFO or two independent lane FIFOs.
- Ready reserves two free slots after this edge's accepted prefix. Incoming count
  may be 0, 1, or 2, but even a single instruction conservatively reserves two slots.
  A full queue can pop two and append two on the same edge without a bubble.
- No combinational empty bypass. An enqueue appears at the output after the edge.
  Reset/flush masks output count and input ready, then clears all queue state.
- Tests cover full stalls, one-lane compaction, conservative capacity reservation,
  simultaneous replacement, single-lane input, metadata preservation, flush priority,
  reset while occupied, and 300 randomized cycles against an instruction FIFO model.

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
vlog -sv common/rv32_ooo_pkg.sv common/frontend_local_pkg.sv common/frontend_ready_buffer.sv tb/frontend_ready_buffer_tb.sv
vsim -c frontend_ready_buffer_tb -do "run -all; quit -f"
```
