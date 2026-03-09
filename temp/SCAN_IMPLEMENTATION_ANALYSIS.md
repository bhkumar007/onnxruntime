# ONNX Runtime Scan Op CPU Implementation Analysis

## Overview
This document provides a comprehensive analysis of the Scan operator CPU implementation, focusing on memory management, output shape handling, and the dynamic shape mechanism.

## File Locations

### Core Implementation Files
1. **Header Files:**
   - `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan.h` (Scan template class - lines 69-103)
   - `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan_utils.h` (Helper utilities - lines 1-213)
   - `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/loop.h` (Loop operator for comparison - lines 1-60)

2. **Implementation Files:**
   - `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan_8.cc` (Scan v8 impl - 451 lines)
   - `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan_9.cc` (Scan v9 impl - 574 lines)
   - `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/scan_utils.cc` (Shared utilities - 575 lines)
   - `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/loop.cc` (Loop operator - 675 lines)

---

## 1. Main Scan Op Kernel Implementation

### Scan Template Class (scan.h:69-103)
```cpp
template <int OpSet>
class Scan : public controlflow::IControlFlowKernel {
  // OpSet-specific initialization
  void Init(const OpKernelInfo& info);
  
  // Main computation entry point
  Status Compute(OpKernelContext* ctx) const override;
  
  // Setup subgraph execution
  Status SetupSubgraphExecutionInfo(...) override;

  // Private members for caching subgraph info
  std::unique_ptr<Info> info_;
  std::unique_ptr<FeedsFetchesManager> feeds_fetches_manager_;
  scan::detail::DeviceHelpers device_helpers_;
};
```

### Info Structure (scan.h:81-84, scan_utils.cc:34-60)
Holds static information about the Scan node and subgraph:
- Number of inputs/outputs
- Loop state variables count
- Scan inputs/outputs counts
- Subgraph input/output names

### Execution Flow

#### Scan v8 (scan_8.cc)
**Lines 191-442: Scan8Impl Class**

1. **Constructor (line 191-204)**
   - Takes OpKernelContextInternal, SessionState, Info, directions, and DeviceHelpers
   - Extracts optional sequence_lens_tensor

2. **Initialize() (lines 206-214)**
   - Calls ValidateInput() to set batch_size_ and max_sequence_len_
   - Calls AllocateOutputTensors() to allocate all outputs upfront

3. **ValidateInput() (lines 278-310)**
   - **Lines 282-287**: Validates loop state variables (must have batch dim)
   - **Lines 286-287**: Validates scan inputs (must have batch + sequence dims)
   - **Lines 289-307**: Handles optional sequence_lens input
   - Sets batch_size_ from first input's dimension 0
   - Sets max_sequence_len_ from first scan input's dimension 1

4. **AllocateOutputTensors() (lines 312-338)**
   - **Lines 323-328**: Allocates OutputIterators for loop state variables
     - Batch size = batch_size_, sequence_len = max_sequence_len_
   - **Lines 330-335**: Allocates OutputIterators for scan outputs
   - Uses OutputIterator::Create() which immediately allocates full output buffer

5. **Execute() (lines 387-442)**
   - **Lines 391-393**: Creates LoopStateVariables for each batch item
   - **Lines 395-439**: Loop through batch items:
     - **Lines 398-420**: Setup input OrtValue streams for forward/reverse scan
     - **Lines 423-427**: Call IterateSequence() (scan_utils.cc)
     - **Lines 430-435**: Zero out unused outputs for short sequences
   
#### Scan v9 (scan_9.cc)
**Lines 100-496: ScanImpl Class**

Differences from v8:
- No batch dimension handling (sequence_len_ is not per-batch)
- Handles optional axis specification (scan_input_axes, scan_output_axes)
- Supports output transpose
- Dynamic axis handling

1. **Initialize() (lines 257-268)**
   - ValidateInput() - validates axes and sets sequence_len_
   - SetupInputs() - transposes inputs if axis != 0
   - AllocateOutputTensors() - allocates output with transpose info

2. **AllocateOutputTensors() (lines 370-407)**
   - **Lines 382-386**: Loop state variables (batch_size=-1, sequence_len=sequence_len_)
   - **Lines 388-404**: Scan outputs with direction and temporary flags
   - **Line 396**: Sets temporary=true if output axis != 0 (needs transpose)

3. **Execute() (lines 427-460)**
   - Creates single LoopStateVariable (not per-batch)
   - Calls IterateSequence()
   - **Line 457**: Calls TransposeOutput() for any outputs with axis != 0

---

## 2. ScanImpl Class and Output Memory Management

### OutputIterator Class (scan_utils.h:79-163)

**Key Members:**
```cpp
class OutputIterator {
  // Shape and allocation info
  TensorShape final_shape_;
  bool is_concrete_shape_;  // Tracks if shape has all concrete dims
  
  // Memory management
  std::vector<OrtValueTensorSlicer<OrtValue>::Iterator> slicer_iterators_;
  OrtValue temporary_final_output_mlvalue_;  // For temporary buffers
  OrtValue* final_output_mlvalue_;  // Points to actual output
  
  // Configuration
  bool temporary_;  // Whether to use temp buffer (for transpose)
  MLDataType data_type_;  // Data type (only used if temporary_)
  ScanDirection direction_;  // Forward or reverse
  
  // Iteration tracking
  int64_t num_iterations_;
  int64_t cur_iteration_;
};
```

### Memory Allocation Strategy

#### For Concrete Shapes (scan_utils.cc:468-521)

1. **AllocateFinalBuffer() (lines 468-521)** - Called when shape is known:
   
   **When temporary_ = false (direct output):**
   - **Line 473**: Allocates full Scan output using context_.Output()
   - **Line 480**: Gets output OrtValue from context
   - **Lines 492-518**: Creates OrtValueTensorSlicer iterators for each iteration/batch
   
   **When temporary_ = true (needs transpose):**
   - **Lines 483-488**: Allocates temporary buffer using temp allocator
   - Data written to temp, then transposed at end

2. **Slicing Strategy (lines 492-518):**
   
   **For v8 (has batch dimension):**
   - Loop state vars (lines 493-497): Slice on dimension 0 (batch)
   - Scan outputs (lines 498-506): Create slicer for each batch item, slicing on dimension 1 (sequence)
   
   **For v9 (no batch dimension):**
   - Loop state vars: No slicing needed
   - Scan outputs (lines 512-516): Single slicer on dimension 0 (sequence)

#### For Dynamic Shapes (scan_utils.cc:523-535)

**AllocateFinalOutput() - Called on first iteration when shape is discovered:**

1. **Line 524**: Enforces shape was initially unknown (is_concrete_shape_ = false)
2. **Lines 527-528**: Calls MakeShapeConcrete() to fill symbolic dimensions
3. **Line 531**: Calls AllocateFinalBuffer() now that shape is known
4. **Line 530**: Sets is_concrete_shape_ = true

### Shape Validation (scan_utils.cc:388-406)

**MakeShapeConcrete() (lines 388-406):**
```cpp
// Compare per-iteration shape from first execution with expected shape
// If expected has symbolic dims (-1), replace with actual values
// If expected has concrete dims, MUST match actual values
// Returns error if mismatch
```

**Key Requirement:**
- All iterations MUST produce outputs with same shape
- Symbolic dimensions are discovered from first iteration
- Concrete dimensions are validated against all iterations

---

## 3. How Iteration Works

### IterateSequence() (scan_utils.cc:186-294)

**Overview:** Core loop that executes subgraph for each element in sequence

**Key Steps:**

1. **Feed Setup (lines 213-224):**
   - Feeds[0..num_loop_state_vars]: From LoopStateVariable.Input()
   - Feeds[num_loop_state_vars..]: From scan input stream iterators
   - Feeds[num_variadic_inputs..]: Implicit inputs

2. **Fetch Setup (lines 228-269):**
   - **Lines 229-231**: Loop state variable outputs
   - **Lines 232-268**: Scan outputs:
     - If FinalOutputAllocated() = true: Use sliced iterator
     - If FinalOutputAllocated() = false: Use custom allocator (first iteration)

3. **Custom Allocator (lines 245-268):**
   - Used on first iteration to discover output shape
   - Called by executor when subgraph requests output allocation
   - Calls OutputIterator.AllocateFinalOutput() with discovered shape
   - Then allocates the full Scan output buffer upfront
   - Avoids temporary values for subsequent iterations

4. **Subgraph Execution (lines 273-275):**
   - Calls utils::ExecuteSubgraph()
   - Provides custom allocators for outputs with unknown shapes

5. **Post-Iteration (lines 279-285):**
   - Calls LoopStateVariable.Next() to cycle temporary buffers
   - Increments OutputIterator to next slice
   - Clears custom allocators after first iteration

### LoopStateVariable Class (scan_utils.cc:343-386)

**Purpose:** Manages temporary buffers for loop state variables to avoid copying

**Strategy:** Uses double-buffering to cycle between temporary buffers

```
Iteration   Input           Output      Memory Layout
0           original_value  a_          original -> a_
1           a_              b_          (a_ is now input, b_ is output)
2           b_              a_          (b_ becomes input, a_ becomes output)
...
seq_len-1   <previous>      final_value (final output)
```

---

## 4. Loop Op Implementation (For Comparison)

**File:** `/home/grama/onnxruntime/onnxruntime/core/providers/cpu/controlflow/loop.cc`

### Key Differences from Scan:

#### Loop Outputs NOT Pre-allocated

**LoopImpl::Execute() (lines 528-674):**

1. **Lines 531-542:** Iterates until termination condition
2. **Lines 629-634:** For scan outputs:
   - Collects per-iteration outputs in loop_output_tensors_ vector
   - **Line 634**: Only after loop ends, calls ConcatenateLoopOutput()

#### Dynamic Shape Handling in Loop

**ConcatenateLoopOutput() (lines 508-526):**
```cpp
// Takes collection of per-iteration outputs
// Gets first output shape (all must be same)
// Creates final output with new first dimension = num_iterations
// Copies all iteration data into final output
```

**Key Insight:** Loop handles unknown iteration count, so can't pre-allocate.
- Collects outputs during execution
- Only concatenates after loop terminates
- Works with dynamic number of iterations

#### Loop Carried Variables with Dynamic Shapes

**Lines 557-620: copy_mlvalue_to_output lambda:**
- Handles loop-carried vars that may change shape across iterations
- **Line 577**: Allocates output with final shape from last iteration
- **Lines 584-586**: Copies data from last iteration to output

---

## 5. Custom Allocators and Fetch Mechanism

### Custom Allocator Pattern (scan_utils.cc:245-268)

**Purpose:** Allow subgraph to allocate output with just per-iteration shape, while Scan adds sequence dimension

```cpp
fetch_allocators[output] = [&iterator, &fetches](
    const TensorShape& shape,      // Per-iteration shape from subgraph
    const OrtDevice& location,
    OrtValue& ort_value,
    bool& allocated) {
  
  // Call OutputIterator with per-iteration shape
  iterator.AllocateFinalOutput(shape);  // Allocates full buffer
  
  // Return the allocated slice for this iteration
  ort_value = *iterator;
  allocated = true;
};
```

**Flow:**
1. Executor encounters an output with no pre-allocated buffer
2. Calls custom allocator with per-iteration shape
3. Allocator adds sequence dimension and allocates full buffer
4. Returns sliced portion for current iteration
5. Executor writes subgraph output into that slice

---

## 6. Shape Validation and Concrete Shape Requirements

### Scan Output Shape Rules

**scan_utils.cc:79-133: AllocateOutput()**

1. **Line 86-94**: Subgraph output shape MUST be specified
   - No NULL shapes allowed
   - Must have all dimensions defined at graph level

2. **Lines 96-113**: Final shape construction:
   ```
   v8: [batch_size, sequence_len, ...per_iteration_dims...]
   v9: [sequence_len, ...per_iteration_dims...]
   ```

3. **Line 115-119**: Create OutputIterator with final shape
   - Checks if shape is concrete (all dims > 0)
   - Sets is_concrete_shape_ flag

### Validation During Execution

**scan_utils.cc:388-406: MakeShapeConcrete()**

On first iteration:
1. Get actual output shape from subgraph execution
2. Compare with expected shape:
   - Symbolic dims (-1) → replace with actual
   - Concrete dims → MUST match actual
3. Error if mismatch

**Error Condition:** If per-iteration shape changes, error is raised

---

## 7. Key Classes and Functions to Understand

### Essential Classes:
1. **OutputIterator** (scan_utils.h:79-163, scan_utils.cc:408-571)
   - Manages output buffer allocation and slicing
   - Handles both concrete and dynamic shapes
   - Tracks iteration count

2. **LoopStateVariable** (scan_utils.h:34-68, scan_utils.cc:343-386)
   - Manages loop state temporary buffers
   - Implements double-buffering strategy

3. **Scan<8>::Info & Scan<9>::Info** (scan.h:81-84)
   - Static metadata about Scan node and subgraph

4. **Scan8Impl & ScanImpl** (scan_8.cc:86-129, scan_9.cc:100-153)
   - Runtime state management
   - Handles batch processing (v8) or sequence processing (v9)

### Critical Functions:

1. **OutputIterator::AllocateFinalOutput()** (scan_utils.cc:523-535)
   - Called on first iteration to allocate when shape is discovered
   - The KEY function for dynamic shapes

2. **OutputIterator::AllocateFinalBuffer()** (scan_utils.cc:468-521)
   - Allocates the full output buffer upfront or via custom allocator
   - Creates slicers for iterating

3. **IterateSequence()** (scan_utils.cc:186-294)
   - Main loop execution
   - Manages custom allocators for dynamic shapes

4. **MakeShapeConcrete()** (scan_utils.cc:388-406)
   - Validates shape consistency
   - Fills symbolic dimensions

5. **Scan8Impl::Execute()** (scan_8.cc:387-442)
   - Manages batch processing loop
   - Zero-fills unused outputs

6. **ScanImpl::Execute()** (scan_9.cc:427-460)
   - Manages sequence processing
   - Handles transpose for output axes

---

## 8. Dynamic Shape Handling Mechanism

### The Two-Phase Allocation Strategy:

**Phase 1: Graph Construction**
- Output shapes obtained from subgraph GraphProto
- Can have symbolic dimensions (-1) in per-iteration shape
- Final Scan output shape = [seq_len, ...per_iter_shape...]

**Phase 2: First Iteration Execution**
- Subgraph executes, produces actual output
- Custom allocator called with actual per-iteration shape
- OutputIterator::AllocateFinalOutput() called (scan_utils.cc:523-535)
- Fills symbolic dims with actual values
- Allocates full Scan output buffer
- Returns slice for current iteration

**Phase 3: Subsequent Iterations**
- Output buffer already allocated
- Just writes to appropriate slice
- No custom allocators needed

### Key Insight:
The per-iteration shape can have symbolic dimensions (e.g., [10, -1, 5] for 10x?x5 outputs), but:
1. The sequence length dimension must be known (no -1 allowed)
2. Symbolic dims are resolved from first execution
3. All iterations MUST match the resolved shape

---

## 9. Comparison: How Loop Op Differs

### Loop Op Advantages:
- Can handle unknown iteration count
- Loop carried variables can change shape
- Uses simpler collect-then-concatenate approach
- But requires storing all outputs in memory

### Loop Op Disadvantages:
- Memory usage = O(iterations × output_size)
- Cannot pre-allocate output buffer
- Must copy data at end during concatenation

### Scan Op Advantages:
- Pre-allocates output buffer
- Direct writes to output via slicing
- No final copy needed
- More memory efficient for large sequences
- Sequence length must be known

### Scan Op Disadvantages:
- Sequence length must be known
- All iterations must produce same shape
- Cannot handle varying output dimensions

---

## 10. Key Implementation Details to Adapt

If adapting Scan to support dynamic per-iteration shapes:

1. **Modify OutputIterator:**
   - Store multiple shape variants
   - Track shape changes across iterations
   - Adjust slicing per iteration

2. **Modify MakeShapeConcrete():**
   - Allow shape changes
   - Validate shape compatibility (same rank?)
   - Track per-iteration offsets

3. **Modify IterateSequence():**
   - May need separate slicers per iteration
   - Update offset calculations for variable sizes

4. **Modify AllocateFinalBuffer():**
   - Possibly use ragged/variable-size allocations
   - Or allocate as max_size with padding

5. **Modify Scan*Impl::Execute():**
   - Handle variable shape logic
   - Adjust zero-fill logic for v8

---

## File Structure Summary

```
/onnxruntime/core/providers/cpu/controlflow/
├── scan.h              # Template class definition
├── scan.h              # Info struct for Scan
├── scan_utils.h        # OutputIterator, LoopStateVariable, helpers
├── scan_8.cc           # Scan v8 implementation
├── scan_9.cc           # Scan v9 implementation  
├── scan_utils.cc       # Implementation of utilities
├── loop.h              # Loop operator (for comparison)
└── loop.cc             # Loop implementation

Key line numbers by function:
scan.h:
  - Scan class: 69-103
  - Scan::Info struct: 81-84
  
scan_utils.h:
  - OutputIterator: 79-163
  - LoopStateVariable: 34-68
  - AllocateOutput: 168-174
  
scan_utils.cc:
  - OutputIterator impl: 408-571
  - OutputIterator::AllocateFinalOutput: 523-535
  - OutputIterator::AllocateFinalBuffer: 468-521
  - MakeShapeConcrete: 388-406
  - LoopStateVariable impl: 343-386
  - IterateSequence: 186-294
  
scan_8.cc:
  - Scan8Impl: 86-129
  - Scan8Impl::Execute: 387-442
  - Scan8Impl::AllocateOutputTensors: 312-338
  
scan_9.cc:
  - ScanImpl: 100-153
  - ScanImpl::Execute: 427-460
  - ScanImpl::AllocateOutputTensors: 370-407
  - ScanImpl::TransposeOutput: 462-496

loop.cc:
  - LoopImpl::ConcatenateLoopOutput: 508-526
  - LoopImpl::Execute: 528-674
```

