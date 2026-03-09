# Scan Op Implementation - Quick Reference Guide

## File Locations

| File | Purpose | Key Lines |
|------|---------|-----------|
| scan.h | Scan class template | 69-103 |
| scan_utils.h | OutputIterator, LoopStateVariable | 79-163, 34-68 |
| scan_8.cc | Scan v8 implementation | 191-442 |
| scan_9.cc | Scan v9 implementation | 100-574 |
| scan_utils.cc | Utility implementations | 343-571 |
| loop.cc | Loop operator (comparison) | 508-674 |

## Core Data Structures

### OutputIterator (scan_utils.h:79-163)
```
Purpose: Manages output buffer and slicing for each iteration
Key Methods:
  - AllocateFinalOutput(shape) - Called 1st iteration to allocate when shape known
  - AllocateFinalBuffer() - Creates full buffer and slicers
  - operator*() - Returns current iteration's OrtValue slice
  - operator++() - Moves to next slice
  - FinalOutputAllocated() - Returns is_concrete_shape_
```

### LoopStateVariable (scan_utils.h:34-68)
```
Purpose: Double-buffer management for loop state variables
Strategy: Uses two buffers (a_, b_) and cycles between them
  Iteration 0: original_value (input) → a_ (output)
  Iteration 1: a_ (input) → b_ (output)
  Iteration 2: b_ (input) → a_ (output)
  Final:      a_/b_ (input) → final_value (output)
```

## Execution Flow

### Scan v8 (scan_8.cc:191-442)
```
1. Scan8Impl::Initialize()
   ├─ ValidateInput()     → Sets batch_size_, max_sequence_len_
   └─ AllocateOutputTensors() → Pre-allocates all outputs

2. Scan8Impl::Execute()
   ├─ CreateLoopStateVariables() → For each batch item
   └─ For each batch:
      └─ IterateSequence() → For each sequence element:
         ├─ Feed loop state variable input/output
         ├─ Feed scan input slice
         ├─ Fetch subgraph output
         ├─ Call subgraph
         ├─ Write to output buffer slice
         └─ Advance iterators
   └─ Zero-fill unused outputs for short sequences
```

### Scan v9 (scan_9.cc:100-574)
```
1. ScanImpl::Initialize()
   ├─ ValidateInput()    → Sets sequence_len_
   ├─ SetupInputs()      → Transpose inputs if axis != 0
   └─ AllocateOutputTensors() → Pre-allocate OR mark for dynamic

2. ScanImpl::Execute()
   ├─ CreateLoopStateVariables() → Single global
   └─ IterateSequence() → For each sequence element
   └─ TransposeOutput() → For any outputs with axis != 0
```

## Dynamic Shape Handling

### The Key Mechanism (scan_utils.cc:523-535)

```
Graph Construction:
  ✓ Subgraph output shapes from GraphProto
  ✓ Can have symbolic dims (-1)
  ✓ Scan final shape = [seq_len, ...per_iter_dims...]
  ✓ OutputIterator created with this shape
  ✗ Full buffer NOT allocated if shape not concrete

First Iteration Execution:
  → Subgraph executes, produces actual per-iteration output
  → Custom allocator triggered (no pre-allocated buffer)
  → OutputIterator::AllocateFinalOutput(actual_shape) called
  → Fills symbolic dims with actual values
  → Allocates full Scan output buffer
  → Returns slice for current iteration to subgraph

Subsequent Iterations:
  → Buffer already allocated and concrete
  → Custom allocators cleared
  → Direct writes to slices
  → No allocation overhead
```

### Shape Validation (scan_utils.cc:388-406)

```
MakeShapeConcrete():
  1. Compare per_iteration_shape with final_shape
  2. For each symbolic dim (-1):
     - Replace with actual value from first iteration
  3. For each concrete dim:
     - MUST match actual value exactly
  4. Error if mismatch → "dimensions change across iterations"

Requirement:
  - All iterations MUST produce same shape
  - Sequence length MUST be concrete (never -1)
  - Symbolic dims discovered from first iteration
```

## Memory Management

### Buffer Allocation Strategy

**Concrete Shape Case:**
```
OutputIterator::Initialize()
  → AllocateFinalBuffer()
    → context_.Output(shape) allocates full buffer
    → Create slicer iterators for each iteration
    → No temporary allocations needed
```

**Dynamic Shape Case:**
```
IterateSequence() iteration 0:
  → OutputIterator.FinalOutputAllocated() returns false
  → Custom allocator registered
  → Subgraph executes
  → Executor calls custom allocator with actual shape
  → AllocateFinalOutput(actual_shape)
    → MakeShapeConcrete() validates
    → AllocateFinalBuffer() allocates full buffer
    → Returns sliced portion for iteration

IterateSequence() iterations 1+:
  → FinalOutputAllocated() returns true
  → Use regular sliced iterator
  → Direct write to output buffer
  → Custom allocators cleared
```

### Loop State Variable Memory

```
Double-buffering to minimize copies:
  - Only 2 temporary buffers (a_, b_) regardless of sequence length
  - Original value used for iteration 0
  - Final value used for last iteration
  - Avoids copy for intermediate iterations

v8 vs v9:
  v8: LoopStateVariable created per batch item
  v9: Single LoopStateVariable for entire sequence
```

## Key Functions to Modify for Dynamic Shapes

1. **OutputIterator::AllocateFinalBuffer()** (scan_utils.cc:468-521)
   - Currently assumes all iterations same shape
   - Would need per-iteration tracking

2. **MakeShapeConcrete()** (scan_utils.cc:388-406)
   - Currently enforces shape immutability
   - Would need to track shape changes

3. **IterateSequence()** (scan_utils.cc:186-294)
   - Currently updates single iterator
   - Would need multiple shape handling

4. **OutputIterator::operator++()** (scan_utils.cc:549-571)
   - Currently assumes fixed-size slices
   - Would need variable offset calculation

## Comparison: Scan vs Loop

| Aspect | Scan | Loop |
|--------|------|------|
| Sequence len | Must be known | Can be dynamic |
| Output shapes | Must be fixed | Can vary per iteration |
| Pre-allocation | Full buffer upfront | None (collect during exec) |
| Copy overhead | None (direct writes) | Final concatenation copy |
| Memory usage | O(1) buffers | O(iterations) buffers |
| Implementation | Complex slicing | Simple concatenation |

## Loop Op Reference (scan_utils.cc:508-674)

Loop handles dynamic iteration count and variable shapes:

```
LoopImpl::Execute():
  While iter < max_count AND condition:
    1. Execute subgraph
    2. Save outputs to loop_output_tensors_[] vector
    3. Update loop carried variables

After loop ends:
  For each scan output:
    ConcatenateLoopOutput()
      1. Get shape from first output
      2. Create final output with new first dim = num_iterations
      3. Copy all collected outputs into final output
```

Key insight: Loop stores ALL outputs, THEN concatenates. Can't pre-allocate.

---

## Debugging Checklist

1. Check `is_concrete_shape_` in OutputIterator
2. Verify `AllocateFinalOutput()` called on iteration 0
3. Check shape validation in `MakeShapeConcrete()`
4. Verify custom allocators registered in `IterateSequence()`
5. Check slicer iteration in `operator++()`
6. Verify final_output_mlvalue_ points correctly
7. Check per-iteration vs batch iteration (v8 vs v9)

