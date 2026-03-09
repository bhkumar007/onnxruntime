# ONNX Runtime Scan Op Implementation - START HERE

## What You'll Find Here

Four comprehensive documents totaling **1,384 lines** of detailed analysis covering the CPU implementation of the Scan operator in ONNX Runtime.

### Quick Navigation

- **First time?** → Start with this document, then read SCAN_IMPLEMENTATION_ANALYSIS.md
- **Need specific info?** → Use QUICK_REFERENCE.md
- **Want to see it in action?** → Read CODE_FLOW_EXAMPLES.md
- **Lost?** → Read README.md

---

## The Big Picture

The Scan operator iterates over a sequence dimension of inputs and outputs, executing a subgraph for each element.

### Key Challenge: Pre-allocation with Possible Dynamic Shapes

Scan MUST pre-allocate the output buffer because:
1. It needs to slice each iteration's output into the buffer
2. The output shape must be known before execution

But what if the per-iteration output shape is symbolic (unknown at graph construction time)?

### The Solution: Two-Phase Allocation

**Phase 1 (Graph Construction):**
- Create OutputIterator with expected shape (may have -1 for symbolic dims)
- Don't allocate anything yet if shape is not concrete

**Phase 2 (First Iteration):**
- Subgraph produces actual output with concrete shape
- Custom allocator intercepts the allocation request
- Now that we know the actual shape, allocate full buffer upfront
- Return a slice to the subgraph for this iteration

**Phase 3 (Remaining Iterations):**
- Buffer already allocated
- Direct writes to slices
- All iterations MUST produce same shape (or data corruption)

---

## Critical Code Location Summary

| What | Where | Lines |
|------|-------|-------|
| **OutputIterator** (Shape & Buffer Management) | scan_utils.h | 79-163 |
| **OutputIterator Implementation** | scan_utils.cc | 408-571 |
| **Key: AllocateFinalOutput()** | scan_utils.cc | 523-535 |
| **Key: MakeShapeConcrete()** | scan_utils.cc | 388-406 |
| **LoopStateVariable** (State Management) | scan_utils.h | 34-68 |
| **IterateSequence()** (Main Loop) | scan_utils.cc | 186-294 |
| **Scan v8 Implementation** | scan_8.cc | 191-442 |
| **Scan v9 Implementation** | scan_9.cc | 100-574 |
| **Loop (For Comparison)** | loop.cc | 508-674 |

---

## The Most Important Code Paths

### Dynamic Shape Discovery
```
OutputIterator::AllocateFinalOutput() [scan_utils.cc:523-535]
  ↓
  MakeShapeConcrete() [scan_utils.cc:388-406]
    ↓
    (Replace symbolic dims with actual values)
    (Verify concrete dims match actual)
    ↓
  AllocateFinalBuffer() [scan_utils.cc:468-521]
    ↓
    (Allocate full Scan output buffer)
    (Create slicers for each iteration)
```

### Execution Loop
```
IterateSequence() [scan_utils.cc:186-294]
  ↓
  For each iteration:
    - Check if output buffer allocated
    - If not: Register custom allocator
    - If yes: Use pre-allocated slice
    - Execute subgraph
    - Advance iterators
    - Clear allocators after iteration 0
```

### Key Check
```cpp
// In IterateSequence() line 235:
if (iterator.FinalOutputAllocated()) {
  // Use pre-allocated slice
} else {
  // Register custom allocator
  // Will be called by executor during subgraph execution
}
```

---

## The Critical Limitation (The Bug)

**Current Behavior:**
- Scan assumes all iterations produce identical shapes
- If shapes differ, data gets written to wrong positions → CORRUPTION
- There is NO validation that shapes match

**Example of the Bug:**
```
Expected per-iteration shape: [5, 20]
Iteration 0: produces [5, 20] ✓ OK
Iteration 1: produces [3, 20] ✗ WRONG - but no error!

Slice calculation:
  Iteration 0: offset = 0 * [5*20] = 0
  Iteration 1: offset = 1 * [5*20] = 100  ← WRONG!
               Actual data is only [3*20] = 60 bytes
               Writes beyond allocated space OR overwrites next iteration

Result: Silent data corruption or segfault
```

---

## Key Data Structures

### OutputIterator (scan_utils.h:79-163)
```
Purpose: Manage output buffer and slicing for Scan outputs

State:
  - final_shape_: Expected output shape
  - is_concrete_shape_: Is shape fully known? (tracking flag)
  - slicer_iterators_: Pointers to buffer slices for each iteration
  - final_output_mlvalue_: The actual output buffer

Key Methods:
  - AllocateFinalOutput(shape): Called on first iteration
  - AllocateFinalBuffer(): Allocates the full buffer
  - operator*(): Returns current iteration's slice
  - operator++(): Moves to next iteration's slice
  - FinalOutputAllocated(): Returns is_concrete_shape_
```

### LoopStateVariable (scan_utils.h:34-68)
```
Purpose: Double-buffer state variables to minimize copies

Strategy:
  Use only 2 temporary buffers (a_, b_) regardless of sequence length:
  
  Iteration 0: Input=original_value → Output=a_
  Iteration 1: Input=a_ → Output=b_
  Iteration 2: Input=b_ → Output=a_
  ...
  Final: Input=a_/b_ → Output=final_value

Result: O(1) temporary allocations instead of O(sequence_length)
```

---

## Understanding v8 vs v9

### Scan v8 (scan_8.cc)
- **Key Feature:** Handles batch dimension
- **Output Shape:** [batch_size, sequence_len, ...per_iteration...]
- **Implementation:** Per-batch-item processing loop
- **Limitation:** Batch dimension must be known upfront
- **Use Case:** Pre-batched data with known batch size

### Scan v9 (scan_9.cc)
- **Key Feature:** Flexible axis specification
- **Output Shape:** [sequence_len, ...per_iteration...]
- **Implementation:** Sequence-based (no batch dimension)
- **Advantage:** Supports scan_input_axes and scan_output_axes
- **Limitation:** Sequence length must still be known

Both share the core utilities from scan_utils.cc.

---

## Comparison: Scan vs Loop

### Scan Operator
```
Characteristics:
  ✓ Sequence length known upfront
  ✓ All iterations same output shape
  ✓ Pre-allocates full buffer
  ✗ Cannot handle unknown iteration count
  ✗ Cannot handle varying output shapes

Memory Model:
  Allocate: Full buffer upfront (or after first iteration)
  Execute:  Direct writes to slices
  Copy:     None at the end
  Total:    O(1) temporary buffers
```

### Loop Operator  
```
Characteristics:
  ✓ Unknown iteration count (dynamic loop)
  ✓ Loop carried variables can change shape
  ✗ Cannot pre-allocate
  ✗ Higher memory usage

Memory Model:
  Collect:  Store all iteration outputs in vector
  Execute:  Flexible, handles varying shapes
  Copy:     Final concatenation
  Total:    O(iterations) temporary storage
```

**Key Insight:** Loop uses collect-then-concatenate. Scan uses pre-allocate-then-slice.

---

## The Mechanism You Need to Understand

### Custom Allocators (scan_utils.cc:245-268)

The executor framework allows subgraphs to request memory allocation through custom allocators. Scan uses this for dynamic shapes:

1. **First Iteration:** OutputIterator is not concrete
   - Register lambda in fetch_allocators[output]
   - When subgraph requests output buffer, lambda is called
   - Lambda calls OutputIterator.AllocateFinalOutput(actual_shape)
   - This discovers the shape and allocates full buffer
   - Returns slice to subgraph

2. **Subsequent Iterations:** OutputIterator is concrete
   - fetch_allocators.clear() (no longer needed)
   - Use pre-allocated slices directly
   - No allocation overhead

---

## Where to Focus

### For Understanding the System:
1. Read SCAN_IMPLEMENTATION_ANALYSIS.md sections 1-5 (foundation)
2. Look at CODE_FLOW_EXAMPLES.md Example 2 (dynamic shapes in action)
3. Reference QUICK_REFERENCE.md for code locations

### For Modifying Code:
1. Use QUICK_REFERENCE.md to find file locations
2. Read relevant section in SCAN_IMPLEMENTATION_ANALYSIS.md
3. Study CODE_FLOW_EXAMPLES.md for similar scenario
4. Check QUICK_REFERENCE.md debugging checklist before testing

### For Fixing Dynamic Shape Issues:
1. Start with SCAN_IMPLEMENTATION_ANALYSIS.md section 8
2. Read CODE_FLOW_EXAMPLES.md Example 4 (shape validation)
3. Key functions to modify:
   - OutputIterator::AllocateFinalBuffer()
   - MakeShapeConcrete()
   - OutputIterator::operator++()
   - IterateSequence() allocation logic

---

## Document Roadmap

```
00_START_HERE.md (You are here)
├─ README.md (Overview and navigation)
│
├─ SCAN_IMPLEMENTATION_ANALYSIS.md (Complete analysis)
│  ├─ Section 1-3: Overall architecture
│  ├─ Section 4-5: Key classes
│  ├─ Section 6-7: Shape validation
│  ├─ Section 8-10: Dynamic shapes & modifications
│  └─ Section 11+: Summary
│
├─ QUICK_REFERENCE.md (Lookup table)
│  ├─ File locations
│  ├─ Data structures
│  ├─ Execution flows
│  ├─ Key functions
│  └─ Debugging checklist
│
└─ CODE_FLOW_EXAMPLES.md (Detailed walkthroughs)
   ├─ Example 1: v8 fixed shape
   ├─ Example 2: v9 dynamic shape
   ├─ Example 3: Loop comparison
   ├─ Example 4: Shape validation
   ├─ Example 5: State variable buffering
   └─ Example 6: Custom allocators
```

---

## Next Steps

### 1. Understanding (30-45 minutes)
- Read this document entirely
- Skim SCAN_IMPLEMENTATION_ANALYSIS.md sections 1-3
- Look at file locations in QUICK_REFERENCE.md

### 2. Deep Dive (1-2 hours)
- Read SCAN_IMPLEMENTATION_ANALYSIS.md completely
- Walk through relevant CODE_FLOW_EXAMPLES.md
- Open source files and verify line numbers

### 3. Hands-On (As needed)
- Modify code as required
- Use QUICK_REFERENCE.md debugging checklist
- Reference CODE_FLOW_EXAMPLES.md for affected code paths

---

## Key Takeaways

1. **OutputIterator is the heart** - Manages allocation, slicing, and iteration
2. **is_concrete_shape_ is the gate** - Controls when buffer gets allocated
3. **AllocateFinalOutput() is the trigger** - Called on first iteration to allocate
4. **Custom allocators are the mechanism** - How dynamic shapes are discovered
5. **Shape validation is weak** - Currently allows corruption, needs fixing
6. **v8 vs v9 differ only in batch handling** - Core logic is shared
7. **Loop is the comparison point** - Shows alternative approach for unknown iteration count

---

## Files to Reference While Reading

Keep these files open:
- `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan_utils.h`
- `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan_utils.cc`
- `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan_9.cc` (if v9)
- `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/loop.cc` (for comparison)

---

## Questions This Documentation Answers

- ✓ How does Scan allocate output memory?
- ✓ How does it handle symbolic dimensions?
- ✓ What's the difference between v8 and v9?
- ✓ How do custom allocators work?
- ✓ What is double-buffering in LoopStateVariable?
- ✓ How does shape validation work?
- ✓ What's the bug with changing shapes?
- ✓ How does Loop differ from Scan?
- ✓ Which functions should I modify?
- ✓ How is data laid out in memory?

---

## Start Reading

**1. Next: Read SCAN_IMPLEMENTATION_ANALYSIS.md** (sections 1-3 first)

Then:
- **2. Reference QUICK_REFERENCE.md** while reading code
- **3. Study CODE_FLOW_EXAMPLES.md** for your specific scenario
- **4. Check README.md** if you get lost

Good luck!

