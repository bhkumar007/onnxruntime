# Scan Op Implementation - Complete Documentation

This directory contains comprehensive documentation of the ONNX Runtime Scan operator CPU implementation, with focus on memory management, output handling, and dynamic shape support.

## Documents Overview

### 1. SCAN_IMPLEMENTATION_ANALYSIS.md (523 lines)
**Comprehensive technical analysis** - Read this first for complete understanding.

**Contents:**
- Overall architecture and design
- File locations with line numbers
- Scan<8> (v8) implementation details
- Scan<9> (v9) implementation details
- ScanImpl class and OutputIterator
- Memory allocation strategies (concrete vs dynamic shapes)
- Shape validation and requirements
- Custom allocator mechanism
- LoopStateVariable double-buffering
- Detailed comparison with Loop operator
- Key classes and functions to understand
- Implementation details for dynamic shape adaptation

**Best for:** Understanding the full system, implementation details, and code organization.

---

### 2. QUICK_REFERENCE.md (222 lines)
**Quick lookup guide** - Use this while reading code.

**Contents:**
- File locations table
- Core data structures (OutputIterator, LoopStateVariable)
- Execution flow diagrams for v8 and v9
- Dynamic shape handling mechanism explanation
- Memory management summary
- Key functions to modify for dynamic shapes
- Scan vs Loop comparison table
- Debugging checklist

**Best for:** Quick reference while implementing, debugging, or navigating the code.

---

### 3. CODE_FLOW_EXAMPLES.md (391 lines)
**Detailed code execution examples** - Use this to understand specific scenarios.

**Contents:**
- Example 1: Scan v8 with fixed shape (step-by-step)
- Example 2: Scan v9 with dynamic shape (step-by-step)
- Example 3: Loop operator with unknown iteration count
- Example 4: OutputIterator shape validation walkthrough
- Example 5: LoopStateVariable double-buffering detail
- Example 6: Custom allocator registration flow

**Best for:** Understanding how code executes in specific scenarios, memory layout, and data flow.

---

## Key Findings Summary

### The Critical Mechanism: Dynamic Shape Support

Scan v9 supports outputs with symbolic dimensions (per-iteration shape) through a clever two-phase allocation:

1. **Graph Construction Phase:**
   - Output shape can have symbolic dimensions (-1)
   - Sequence length dimension MUST be concrete
   - Final shape: [sequence_len, ...per_iteration_dims...]

2. **First Iteration Execution:**
   - OutputIterator detects shape is not concrete
   - Registers custom allocator for subgraph output
   - On subgraph output request, allocates full buffer upfront
   - Discovers actual shape from first iteration

3. **Subsequent Iterations:**
   - Buffer already allocated
   - Direct writes to slices
   - No allocation overhead
   - Must match first iteration shape exactly

### Critical Limitation

**All iterations MUST produce identical shapes.** 
- If iteration 0 produces [5, 20] but iteration 1 produces [3, 20], there is currently NO error.
- Data gets written to wrong positions, causing corruption.
- This is THE issue that needs fixing for dynamic per-iteration shapes.

### Key Data Structures

1. **OutputIterator** (scan_utils.h:79-163)
   - Manages output buffer and slicing
   - Tracks concrete_shape_ flag
   - Creates slicer iterators for each iteration

2. **LoopStateVariable** (scan_utils.h:34-68)
   - Double-buffers state variables
   - Uses only 2 temp buffers regardless of sequence length
   - Minimizes copies between iterations

3. **Info/Scan<OpSet>** (scan.h)
   - Template class for Scan operator
   - Caches subgraph metadata
   - Routes to Scan8Impl or ScanImpl

### Implementation Differences

**Scan v8:** Batch-based, handles batch processing with fixed shapes
**Scan v9:** Sequence-based, supports axes specification and transposes

Both share core logic in scan_utils.cc:
- OutputIterator (shape and buffer management)
- LoopStateVariable (state management)
- IterateSequence (main execution loop)
- Custom allocators (dynamic shape discovery)

### How to Use These Documents

1. **First Time Understanding:**
   - Start with SCAN_IMPLEMENTATION_ANALYSIS.md sections 1-5
   - Reference QUICK_REFERENCE.md for file locations
   - Jump to CODE_FLOW_EXAMPLES.md for specific scenarios

2. **Implementing Changes:**
   - Use QUICK_REFERENCE.md for file locations
   - Reference CODE_FLOW_EXAMPLES.md for affected code paths
   - Consult SCAN_IMPLEMENTATION_ANALYSIS.md for architectural impact

3. **Debugging Issues:**
   - Use QUICK_REFERENCE.md debugging checklist
   - Find similar scenario in CODE_FLOW_EXAMPLES.md
   - Check SCAN_IMPLEMENTATION_ANALYSIS.md for validation rules

4. **Adapting for Dynamic Shapes:**
   - Read section 8 in SCAN_IMPLEMENTATION_ANALYSIS.md
   - Key functions to modify (section 10)
   - CODE_FLOW_EXAMPLES.md shows current shape validation flow

---

## Critical Code Paths

### Memory Allocation Path
```
OutputIterator::Create()
  → Initialize()
    → is_concrete_shape check
      → AllocateFinalBuffer() [if concrete]
      
IterateSequence() iteration 0:
  → AllocateFinalOutput() [if not concrete]
    → MakeShapeConcrete()
    → AllocateFinalBuffer()
```

### Shape Validation Path
```
MakeShapeConcrete(per_iter_shape, final_shape)
  → For each dim in per_iter_shape:
    → If final_shape[i] == -1: set to actual value
    → If final_shape[i] > 0: verify matches actual
    → Return error if mismatch
```

### Execution Loop Path
```
IterateSequence()
  → For each iteration:
    → Check FinalOutputAllocated()
      → If false: register custom allocator
      → If true: use pre-allocated slice
    → Execute subgraph
    → Move state variables forward
    → Advance output iterators
    → Clear allocators after iteration 0
```

---

## File Map

```
/onnxruntime/core/providers/cpu/controlflow/
├── scan.h              [69-103]   Scan template class
├── scan_utils.h        [79-163]   OutputIterator class
│                       [34-68]    LoopStateVariable class
│                       [168-174]  AllocateOutput function
├── scan_8.cc           [191-442]  Scan8Impl implementation
├── scan_9.cc           [100-574]  ScanImpl implementation
├── scan_utils.cc       [408-571]  OutputIterator implementation
│                       [343-386]  LoopStateVariable implementation
│                       [186-294]  IterateSequence function
│                       [388-406]  MakeShapeConcrete function
├── loop.h              [14-60]    Loop operator class
└── loop.cc             [508-674]  Loop implementation
```

---

## Next Steps

### For Understanding:
1. Read sections 1-3 of SCAN_IMPLEMENTATION_ANALYSIS.md
2. Reference QUICK_REFERENCE.md for structure details
3. Walk through CODE_FLOW_EXAMPLES.md for execution flow

### For Implementation:
1. Identify which OpSet (8 or 9) you're modifying
2. Check QUICK_REFERENCE.md for affected functions
3. Review CODE_FLOW_EXAMPLES.md for similar scenario
4. Consult SCAN_IMPLEMENTATION_ANALYSIS.md for validation rules

### For Debugging:
1. Use QUICK_REFERENCE.md debugging checklist
2. Add breakpoints at OutputIterator methods
3. Check is_concrete_shape_ flag
4. Verify custom allocators in IterateSequence
5. Validate shapes in MakeShapeConcrete

---

## Document Statistics

| File | Lines | Focus |
|------|-------|-------|
| SCAN_IMPLEMENTATION_ANALYSIS.md | 523 | Complete technical analysis |
| QUICK_REFERENCE.md | 222 | Quick lookup and reference |
| CODE_FLOW_EXAMPLES.md | 391 | Step-by-step execution flows |
| **Total** | **1136** | **Comprehensive coverage** |

**Estimated Reading Time:**
- Complete read: 2-3 hours
- Quick overview: 30-45 minutes
- Reference lookups: 5-10 minutes per topic

---

Generated: 2024
Based on ONNX Runtime commit analysis of:
- /home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan.h
- /home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan_utils.h
- /home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan_8.cc
- /home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan_9.cc
- /home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan_utils.cc
- /home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/loop.cc
- /home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/loop.h

