# ECE 411: mp_pipeline GUIDE

## Pipelined RV32I Processor

**This document, GUIDE.md, serves as a gentle, guided tour of the MP. For
strictly the specification and rubric, see [README.md](./README.md).**

# Getting Started
The intended microarchitecture of your pipelined, in-order processor is shown in
figure 1.
<p align="center">
  <img src="doc/images/pipeline_cpu.svg"/>
  <p align="center">Figure 1: Processor block diagram.</p>
</p>

The intended CPU functionality will be similar to the CPU provided in Part 4 of
`mp_verif`, since they implement the same instruction set. We encourage you to
copy over any parts of that provided code you deem re-useable. 

We recommend partitioning your design into multiple modules across many files
to keep your code readable. We highly suggest separating each pipeline
stage into their own module and to connect them together in `rtl/cpu.sv`.

We also highly recommend using a struct for your pipeline stage registers.
We have provided some starter code in `rtl/pkg/types.sv`.

## Running Simulation

A quick recap on how to run the simulation:

```bash
$ scons sim PROG=tests/cp1_example.s
```

To run with a memory model that does not stall, edit the instantiation of
`memory_model` in `tb/top_tb/top_tb.sv` with `MAGIC(1)`
instead of `MAGIC(0)`.

## Gotchas

It is highly recommended that members of one struct are all assigned in a single
always block.  This not only improves readability of your code, but also makes
simulation faster.  We have also noted that if you do not do so, there is a rare
chance you will trigger a bug in VCS where the simulation behavior is undefined.

There is a bug in DC where if you have a signal with the same name as a member
in a struct in the same file, DC will throw an "Internal Assertion Fault" and
terminate itself. If you do see this error, try to find any duplicate names in
your code.

# The RV32I ISA
If you are unsure about what a specific instruction does, it might be a good
idea to check what the CPU in `mp_verif` does to execute that instruction.

In addition to Chapter 2 and Chapter 34, you should also familiarize yourself
with the RISC-V ISA from a programmer's perspective.  This includes assembler
mnemonics and pseudo-instructions (such as `nop`) which will prove useful when
writing testcode and/or disassembling binaries.  Refer to
[this](https://github.com/riscv-non-isa/riscv-asm-manual/blob/main/src/asm-manual.adoc)
for more details. 

Page 608 of the RISC-V unprivileged reference (ratified in May 2025) is a useful
reference regarding the formatting and bitfields of various instructions.

## Gotchas

### `funct7`

Some instructions require you to look at `funct7` to figure out which exact
variant of the base instructions they are.

### Misaligned `jal`/`jalr`

Note that `jal` and `jalr` require you to mask out the last bit in the resulting
PC.

# Design Tips

## Access Alignment
According to Section 2.6 of the RISC-V specification, a processor should include
support for misaligned memory accesses.  However, for this MP, we will relax
this requirement: you only need to support naturally aligned load and stores.
Simply put, this means that for an *n* byte piece of data, it is guaranteed that
the address of the data mod *n* is 0.  In conjunction with the fact that the
biggest datatype in RV32I is 32-bit integers, the consequence of this is that
all pieces of data will be contained within a single, 4-byte aligned word.

Non-naturally aligned memory accesses will not be tested. As a result, you do
not need to implement trap logic.

When interacting with memory, you should always use 4-byte aligned addresses as
outputs to `imem_addr` and `dmem_addr`.  To specify which part of the 4 bytes to
access, use the `w/rmask`. Each `1` bit in the `w/rmask` indicates the validity
of the respective byte in the 4-byte word. A non-zero `w/rmask` indicates a
write/read request to the memory.

For example, if your processor were to write the byte at address `0x10000002`,
your processor should set `addr` as `0x10000000`, set `w/rmask` to `4'b0100`
(note address are zero indexed hence `0x2` translated to the 3rd place), and
`wdata` shifted: say you are trying to write `0x000000A5`, then your 32-bit
`wdata` should be `0xXXA5XXXX`.

## Branch Prediction
In order to avoid excessive stalls in a pipelined processor, a branch predictor
is necessary. This is because after fetching a branch instruction, you would
like to continue fetching the next instruction in the following cycle.  However,
since the branch instruction will not yet have resolved, your CPU will instead
need to make a *prediction* about which address is correct. For this MP, you may
simply use a static-not-taken branch predictor.  This predictor always assumes
branches will not be taken, i.e. your fetch stage will always fetch the next
instruction (`pc`+4) and flush the erroneously fetched instructions if the
branch is later resolved to be taken.

## Flushing
Since the branch predictor cannot guarantee a correct prediction, you may have
invalid instructions fetched/executed after a branch instruction. Therefore,
when a branch mis-prediction is detected, your processor must flush all the
wrong instructions in the pipeline to prevent them from affecting the
correctness of your CPU's execution.

You can do so either by having a valid bit in your pipeline registers, and
setting this to invalid on a flush, or by changing those signals that will
modify the architectural state (hint: registers and memory) to something where
they would not.  Assigning every signal in the pipeline register to equal to
`nop` is not recommended as that wastes a lot of area and power to accomplish
the same effect as having a correctly implemented valid bit.

## Stalling
Not every stage in the pipeline takes exactly one cycle. The instruction fetch
and memory stages both might wait for memory to respond before their work is
completed, which may take multiple cycles. This will require your processor to
stall.

There are several approaches to stalling. *Global stall*: If the processor is waiting on either `imem` or `dmem` to respond, the entire pipeline will stall. This method is the simplest (conceptually) and will have only slightly reduced performance compared to backpressure. *Backpressure*: If any stage is blocked, everything before it must wait. Additionally, if any stage is blocked, everything *after* it may *continue*. This allows for lower average latency of instructions through the pipeline, but identical throughput compared to global stall. Implementing this more complex logic may help you in future MPs.

You may opt to implement **any** stalling technique.

## Next Cycle Memory Response / Pipelined Memory

You might have noticed that the memory responds on the next cycle instead of in
the same cycle.  A naive implementation of this MP might look like this:

![naive1](./doc/images/naive1.svg)

This comes with some issues. The pipeline register `MM/WB` will actually get the
data 2 cycles after the initial request.  Let's open the black box of this
memory model a bit. Since it has a one cycle delay, we can infer that it
probably looks like this:

![memory_internal](./doc/images/memory_internal.svg)

The "SRAM" block in this diagram is some purely combinational logic.  We will
talk about SRAM in detail in `mp_cache`.  Note that in synthesis we are using
this exact configuration (with the register in the front).

This explains why the naive implementation would not work, as we are making our
pipeline 6 or 7 stages instead of 5!

![naive2](./doc/images/naive2.svg)

How do we solve this problem? One thing we could do is to view the memory model
register as part of the `EX/MM` pipeline register:

![pipelined_memory](./doc/images/pipelined_memory.svg)

This is our recommended method of dealing with pipelined memory.

How this configuration interacts with stalling and flushing is left as an
exercise for the reader.

### Reset Correctness

Since we are considering these registers in the memory model as part of our
pipeline registers, they should be reset in the same way.  However, this is not
entirely straightforward. The memory model’s register does not have a reset
function; it will always take in the next value. How to deal with this is also
left as an exercise for the reader.

## Forwarding
We recommend you refer to the lectures or the textbook (Computer Organization
and Design the Hardware/Software Interface RISC-V edition by Patterson &
Hennessy, Section 4.7), where this topic is discussed in detail.

# Verification
You can use the provided memory models and load RISC-V programs into your
design, after which you may use Spike to generate the golden trace for your
program.

You can also use the random testbench from your `mp_verif` to test your CPU.

You must use RVFI to help check the correctness of your processor.

Here are some recommended targeted tests that we think you should write:

- Every required instruction
  - Including their corner cases, such as when a negative number is involved, etc.
  - This could be generated using a Python script.
- All the forwarding paths:
  - The number of forwarding paths depends on your design. The following are the common ones:
    - MM -> EX
    - WB -> EX
    - WB -> MM
    - Transparent register file
  - Make sure you are not forwarding from an instruction that does not write to the register file.
  - Make sure you are not forwarding `x0`.
  - Also test forwarding when the source and/or target instruction is flushed/invalid.
- Test the bubble/flush/stall mechanism
  - Make sure invalid instructions do not interfere with:
    - Forwarding
    - Memory accesses
    - Register file state

# Spike
It is mandatory for you to have the Spike monitor connected for every
checkpoint.  All you need to do is to fill out `configs/rvfi_reference.yaml`
with signals that represent the instructions you are committing.

For information on what each signal means, refer to
[this](https://github.com/SymbioticEDA/riscv-formal/blob/master/docs/rvfi.md).

A Python script will sanitize this file and generate a `.sv` file, sourced in
`top_tb.sv`.  Your hierarchical reference should start with `dut.`, as
specified in `top_tb.sv`.

- What is a hierarchical reference? Consider the circuit used in Part 2.2
  (`loop`) of `mp_verif`.  If we want to refer to the `internal_counter` logic
  variable in module `foo` starting from the top level design in the HVL
  testbench, we would use the following: `dut.foo.internal_counter`. This is a
  hierarchical reference. Note that the reference names use the *name of the
  module instantiation* and not the *name of the module*. Specifically, we use
  `dut` instead of `top`.

**Never use hierarchical reference in your HDL!**  The usage of hierarchical
references in HDL is **strictly forbidden** in ECE411. Their usage is only
permitted in `configs/rvfi_reference.yaml` and other HVL files. If you find
yourself tending towards hierarchical references in HDL, you most likely need to
add another port to your module.

A few notable signals:

- `valid`: Signifies to Spike that there is a new instruction that needs to be checked.
  Should be high for one and only one cycle for each instruction.
- `order`: The serial number of the instruction. This number should start from 0
  and increase by one on each commit. We highly recommend you assign each
  instruction with this serial number in the fetch stage.

All the signals going to Spike should be from your write-back stage,
corresponding to the current instruction being committed. You should pass all
this commit information down the pipeline.  You do not have to worry about
wasting area on data which the write-back stage does not strictly need, since
the synthesis tool will optimize them out.

A few gotchas:

- `mem_rdata` and `mem_wdata` should be what the memory sees, i.e. `mem_rdata`
  is as-is from memory, and `mem_wdata` is after shifting.


# Optional: Porting `mp_verif`'s `random_tb`

Writing assembly to test your pipelined processor's edge cases is rather
challenging, and, as you remember from `mp_verif`, randomness can help catch
certain classes of issues much faster than writing directed test vectors. The assignment from `mp_verif` can be reused to test your pipeline!

To start using `randinst.sv` and `instr_cg.sv` from `mp_verif` to verify your
pipelined processor, you must port `mp_verif/tb/cpu_tb/random.sv` to work
with `mp_pipeline`'s dual-port memory model. First, copy over all three files:

```bash
$ cp mp_verif/tb/rand_tb/randinst.sv mp_pipeline/tb/top_tb
$ cp mp_verif/tb/rand_tb/instr_cg.sv mp_pipeline/tb/top_tb
$ cp mp_verif/tb/cpu_tb/random.sv mp_pipeline/tb/top_tb
```

You will also need to add 
```yaml
  include_files:
    - top_tb/randinst.sv
    - top_tb/instr_cg.sv  
```
to `tb/svbuild.yaml` under the `top_tb` section.
Next, you should modify `random_tb` to have ports similar to that of
`memory_model.sv`.

Then, modify `random_tb.sv` to use the appropriate interface (`itf.*[0] or
itf.*[1]`) to drive random instructions into your processor, and to respond to
data memory requests via `itf.*[1]`.

Finally, add a line to `top_tb.sv` to instantiate `random_tb`.

Make sure that the `memory_model` instantiation is commented
out if you're using the `random_tb`, since the random testbench acts as the
memory model.
