# Scan Op Implementation - Code Flow Examples

## Example 1: Scan v8 with Fixed Shape (Concrete)

```
Input:
  batch_size = 2
  sequence_len = 5
  scan_input_shape = [2, 5, 10, 20]  (batch, seq, dim1, dim2)
  subgraph_output = [10, 20]          (same as per-iteration)

Execution:

1. Scan8Impl::Initialize()
   ├─ ValidateInput()
   │  ├─ batch_size_ = 2 (from dim 0 of any input)
   │  └─ max_sequence_len_ = 5 (from dim 1 of any scan input)
   │
   └─ AllocateOutputTensors()
      └─ For output 0 (scan output):
         ├─ graph_output_shape = [10, 20]
         ├─ final_scan_output_shape = [2, 5, 10, 20]
         │                            ^ batch ^ seq
         ├─ OutputIterator::Create()
         │  └─ is_concrete_shape_ = true (all dims > 0)
         │  └─ Initialize()
         │     └─ AllocateFinalBuffer()
         │        ├─ context_.Output(0, [2, 5, 10, 20])
         │        │  → Allocates full buffer immediately
         │        │
         │        └─ Create slicer iterators:
         │           For batch 0: slicer on dim 1 (seq)
         │           For batch 1: slicer on dim 1 (seq)

2. Scan8Impl::Execute()
   └─ For batch b = 0,1:
      ├─ CreateLoopStateVariables()
      │  └─ LoopStateVariable for each state var
      │     ├─ Use original_value for input
      │     ├─ Allocate a_ (if seq_len > 1)
      │     └─ Allocate b_ (if seq_len > 2)
      │
      └─ IterateSequence()
         └─ For seq_no = 0..4:
            ├─ Feeds:
            │  [0] loop_state_var.Input()
            │  [1] scan_input_slice (seq_no)
            │
            ├─ Fetches:
            │  [0] loop_state_var.Output()
            │  [1] output_iterator dereference
            │
            ├─ ExecuteSubgraph()
            │  └─ Subgraph writes to fetches[1]
            │     └─ Data goes directly to
            │        output_iterators[0][*cur_slicer_iterator_]
            │        which points to:
            │        final_output_buffer[batch*seq_stride + seq_no*elem_stride]
            │
            ├─ loop_state_var.Next()
            │  └─ Toggles between a_ and b_ for next iteration
            │
            └─ output_iterator++
               └─ Advances cur_slicer_iterator_ to next sequence slice

Final Output:
  Shape: [2, 5, 10, 20]
  Data: Concatenated per-iteration outputs
         buffer[0, 0, :, :] = iteration 0 for batch 0
         buffer[0, 1, :, :] = iteration 1 for batch 0
         ...
         buffer[1, 0, :, :] = iteration 0 for batch 1
         ...
```

## Example 2: Scan v9 with Dynamic Shape

```
Input:
  scan_input_shape = [10, 100, 5]      (seq=10, batch=100, feature=5)
  subgraph_output = [?, 128]           (unknown first dim!, fixed second)

Execution:

1. ScanImpl::Initialize()
   ├─ ValidateInput()
   │  └─ sequence_len_ = 10 (from dim 0)
   │
   └─ AllocateOutputTensors()
      └─ For output 0 (scan output):
         ├─ graph_output_shape = [?, 128] (? = -1)
         ├─ final_scan_output_shape = [10, -1, 128]
         │                            ^ seq ^ symbolic
         │
         ├─ OutputIterator::Create()
         │  └─ is_concrete_shape_ = false
         │     (because final_shape.Size() < 0)
         │
         └─ Initialize()
            └─ AllocateFinalBuffer() NOT called yet
               (waiting for first iteration to discover shape)

2. ScanImpl::Execute()
   └─ IterateSequence()
      │
      └─ Iteration seq_no = 0:
         ├─ output_iterators[0]->FinalOutputAllocated() returns false
         │  (is_concrete_shape_ = false)
         │
         ├─ Register custom allocator:
         │  fetch_allocators[0] = lambda that calls
         │    iterator.AllocateFinalOutput(shape)
         │
         ├─ ExecuteSubgraph()
         │  └─ Subgraph produces output with shape [32, 128]
         │     (the actual value for the symbolic dim)
         │  └─ Executor calls custom allocator
         │     allocator_lambda([32, 128], ...)
         │       │
         │       └─ iterator.AllocateFinalOutput([32, 128])
         │          ├─ MakeShapeConcrete(
         │          │    per_iter_shape = [32, 128]
         │          │    final_shape = [10, -1, 128]
         │          │  )
         │          │  └─ final_shape[1] is -1, set to 32
         │          │  └─ final_shape[2] is 128, verify 128==128 ✓
         │          │  └─ Result: final_shape = [10, 32, 128]
         │          │
         │          ├─ AllocateFinalBuffer()
         │          │  ├─ context_.Output(0, [10, 32, 128])
         │          │  │  → NOW allocates full buffer
         │          │  │
         │          │  └─ Create slicer on dim 0 (sequence)
         │          │     → slicer.begin() points to [0, :, :]
         │          │
         │          └─ is_concrete_shape_ = true
         │
         │  └─ Return ort_value = *iterator (slice [0, :, :])
         │     → Subgraph writes output to this slice
         │
         ├─ loop_state_var.Next()
         │
         └─ output_iterator++
            └─ Advances slicer to next sequence ([1, :, :])

      └─ Iteration seq_no = 1..9:
         ├─ output_iterators[0]->FinalOutputAllocated() returns true
         │  (is_concrete_shape_ = true now)
         │
         ├─ NO custom allocator needed
         │  (fetch_allocators.clear() after iteration 0)
         │
         ├─ ExecuteSubgraph()
         │  └─ Subgraph produces output with shape [32, 128]
         │  └─ No allocation needed
         │  └─ Direct write to output_iterator slice
         │     which points to final_output_buffer[seq_no, :, :]
         │
         ├─ Verify shape is still [32, 128]
         │  (if different, no error in current implementation!)
         │
         ├─ loop_state_var.Next()
         │
         └─ output_iterator++
            └─ Advances slicer to next sequence

Final Output:
  Shape: [10, 32, 128]
  Data: Direct writes to buffer slices
         buffer[0, :, :] = iteration 0 output
         buffer[1, :, :] = iteration 1 output
         ...
         buffer[9, :, :] = iteration 9 output
```

## Example 3: Loop Op with Unknown Iteration Count

```
Input:
  max_trip_count = 100
  condition = varies each iteration
  loop_state_var = [10, 20]

Execution:

1. LoopImpl::Initialize()
   └─ No output pre-allocation

2. LoopImpl::Execute()
   └─ Loop:
      ├─ iter_num = 0
      ├─ condition = true (from input)
      │
      ├─ Iteration 0:
      │  ├─ CreateInitialFeeds()
      │  │  └─ feeds = [iter_num=0, cond=true, loop_state_var=[10,20]]
      │  │
      │  ├─ ExecuteSubgraph()
      │  │  └─ Produces:
      │  │     fetches = [cond=false, loop_state_var=[10,20], output=[5,30]]
      │  │
      │  ├─ SaveOutputsAndUpdateFeeds()
      │  │  ├─ loop_output_tensors_[0].push_back(output=[5,30])
      │  │  │  (stored in memory)
      │  │  │
      │  │  └─ feeds = [iter_num=1, cond=false, loop_state_var=[10,20]]
      │  │
      │  └─ condition = false, exit loop
      │
      └─ After loop:
         ├─ ConcatenateLoopOutput(loop_output_tensors_[0])
         │  ├─ first_output = [5, 30]
         │  ├─ num_iterations = 1
         │  ├─ output_shape = [1, 5, 30]
         │  │  (prepend iteration count)
         │  │
         │  ├─ Allocate output buffer [1, 5, 30]
         │  ├─ Copy from loop_output_tensors_[0][0]
         │  │  to output_buffer[0, :, :]
         │  │
         │  └─ Return output [1, 5, 30]

Key Difference from Scan:
  - Stores outputs: O(iterations)
  - No pre-allocation possible
  - Final copy/concatenation
  - Can handle variable iteration count
  - Can handle different shapes per iteration (if carefully implemented)
```

## Example 4: OutputIterator Shape Validation

```
Scenario:
  Scan says output should be [seq_len, -1, 10]
  Iteration 0 produces [5, 20]
  Iteration 1 produces [5, 20]  ✓ OK
  Iteration 2 produces [3, 20]  ✗ Different!

Code Path:

Iteration 0:
  Custom allocator called with shape [5, 20]
  │
  └─ AllocateFinalOutput([5, 20])
     │
     └─ MakeShapeConcrete(per_iter=[5,20], final=[seq_len,-1,10])
        ├─ i=0: final[0]=-1, set to 5
        │        Result: final=[seq_len,5,10]
        │
        ├─ i=1: final[1]=-1 (wait, there's no second param)
        │       Actually:
        │       per_iter_shape has 2 dims: [5, 20]
        │       final_shape has 3 dims: [seq_len, -1, 10]
        │       offset = 3 - 2 = 1
        │
        │       So compare:
        │       final[1] = -1 with per_iter[0] = 5 → set final[1] = 5
        │       final[2] = 10 with per_iter[1] = 20 → ERROR!
        │
        └─ Returns error:
           "Mismatch between expected shape [seq_len,-1,10] 
            and shape from first output [5,20]"

Actually, let me recalculate that example:
  Scan output shape should have sequence dim prepended (v9):
  If subgraph outputs [5, 20], Scan output becomes [seq_len, 5, 20]
  So the -1 would be in the subgraph output, not the Scan output
  
  If subgraph can output [?, 20] (unknown first dim, known second)
  Then Scan output is [seq_len, ?, 20]
  
  Iteration 0:
    subgraph outputs [5, 20]
    MakeShapeConcrete([5,20], [seq_len,-1,20])
    → Replace -1 with 5
    → Result: [seq_len, 5, 20]
    → Allocate buffer [seq_len, 5, 20]

  Iteration 1:
    subgraph outputs [5, 20] ✓ OK
    
  Iteration 2:
    subgraph outputs [3, 20] ✗ SHOULD ERROR
    → But current code just writes to existing buffer!
    → Writes [3,20] to iterator expecting [5,20] slice
    → Data corruption!
    
    This is the BUG that needs fixing:
    Need to re-validate shape against expected [5,20]
```

## Example 5: LoopStateVariable Double Buffering

```
Input: loop_state_var shape [10, 20], sequence_len = 5

Allocation:
  LoopStateVariable(original_value=[10,20], final_value, seq_len=5, alloc)
  │
  └─ Since seq_len > 1:
     └─ a_ = AllocateTensorInMLValue(..., [10,20], alloc)
        └─ New buffer allocated on allocator's device
  
  └─ Since seq_len > 2:
     └─ b_ = AllocateTensorInMLValue(..., [10,20], alloc)
        └─ Another buffer allocated

  Total temp buffers = 2
  (regardless of sequence_len, only a_ and b_ needed)

Iteration 0:
  Input() = original_value          (input param)
  Output() = a_                     (temp buffer)
  Next()
  iteration_num_ = 1

Iteration 1:
  Input() = iteration_num_=1 → odd → a_   (from previous iteration)
  Output() = iteration_num_=1 → odd → b_  (other temp buffer)
  Next()
  iteration_num_ = 2

Iteration 2:
  Input() = iteration_num_=2 → even → b_  (from previous iteration)
  Output() = iteration_num_=2 → even → a_ (other temp buffer)
  Next()
  iteration_num_ = 3

Iteration 3:
  Input() = iteration_num_=3 → odd → a_   (from previous iteration)
  Output() = iteration_num_=3 → odd → b_  (other temp buffer)
  Next()
  iteration_num_ = 4

Iteration 4 (final):
  Input() = iteration_num_=4 → even → b_  (from previous iteration)
  Output() = iteration_num_+1=5==seq_len → final_value (output param)
  
Final state:
  final_value contains result from iteration 4
  a_ and b_ are garbage (no longer needed)
  Freed when LoopStateVariable destroyed
```

## Example 6: Custom Allocator Registration

```
File: scan_utils.cc:245-268

Scenario: First iteration with dynamic output shape

Code:
  for (int output = 0, end = num_variadic_outputs; output < end; ++output) {
    if (output >= num_loop_state_variables) {  // Only for scan outputs
      auto& iterator = *output_iterators[output];
      
      if (iterator.FinalOutputAllocated()) {
        // Concrete shape, use regular iterator
        fetches.push_back(*iterator);
      } else {
        // Dynamic shape, register custom allocator
        size_t i = fetches.size();
        fetches.emplace_back();  // Placeholder
        
        fetch_allocators[output] = [i, &iterator, &fetches](...) {
          // Called when executor needs to allocate subgraph output
          
          auto status = iterator.AllocateFinalOutput(shape);
          // This will:
          // 1. Call MakeShapeConcrete(shape, final_shape_)
          // 2. Call AllocateFinalBuffer()
          // 3. Allocate the full Scan output buffer
          
          const OrtValue& value = *iterator;
          // value now points to a slice of the allocated buffer
          
          ort_value = value;
          allocated = true;
          
          return Status::OK();
        };
      }
    }
  }

After iteration 0:
  fetch_allocators.clear();
  // Never used again - subsequent iterations use pre-allocated buffer
```

