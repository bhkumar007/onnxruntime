# Complete Index - Scan Op Implementation Documentation

**Total Documentation: 1,750 lines across 5 files (72 KB)**

---

## Document Overview

### 00_START_HERE.md (262 lines)
**Entry Point - Read This First**
- Big picture explanation
- Critical code locations table
- Most important code paths
- Key limitation (the bug)
- Understanding v8 vs v9
- Document roadmap
- Next steps

### SCAN_IMPLEMENTATION_ANALYSIS.md (523 lines)
**Complete Technical Analysis**
- Section 1: Overview & file locations
- Section 2: Main Scan op kernel implementation
- Section 3: ScanImpl class and output memory management
- Section 4: How iteration works
- Section 5: Loop op implementation (for comparison)
- Section 6: Custom allocators and fetch mechanism
- Section 7: Shape validation and concrete shape requirements
- Section 8: Dynamic shape handling mechanism
- Section 9: Comparison: How Loop op differs
- Section 10: Key implementation details to adapt
- File structure summary with line numbers

### QUICK_REFERENCE.md (222 lines)
**Quick Lookup Guide**
- File locations table
- Core data structures (OutputIterator, LoopStateVariable)
- Execution flow diagrams for v8 and v9
- Dynamic shape handling mechanism (bullet points)
- Memory management strategy summary
- Key functions to modify for dynamic shapes
- Scan vs Loop comparison table
- Loop op reference section
- Debugging checklist

### CODE_FLOW_EXAMPLES.md (391 lines)
**Detailed Step-by-Step Walkthroughs**
- Example 1: Scan v8 with fixed shape (70 lines)
- Example 2: Scan v9 with dynamic shape (80 lines)
- Example 3: Loop op with unknown iteration count (50 lines)
- Example 4: OutputIterator shape validation (60 lines)
- Example 5: LoopStateVariable double buffering (50 lines)
- Example 6: Custom allocator registration (40 lines)

### README.md (248 lines)
**Navigation and Context**
- Document overview with contents
- Key findings summary
- How to use these documents
- Critical code paths
- File map with line numbers
- Next steps by use case
- Document statistics

---

## How to Use This Index

### Finding Specific Information

#### About OutputIterator?
- START_HERE.md: Key data structures section
- QUICK_REFERENCE.md: Core data structures table (line 20)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 3 (lines 80-180)
- CODE_FLOW_EXAMPLES.md: Examples 2, 4 (lines 98-170, 260-300)

#### About Dynamic Shapes?
- START_HERE.md: "The Solution" section (lines 30-45)
- QUICK_REFERENCE.md: Dynamic shape handling section
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 8 (lines 380-420)
- CODE_FLOW_EXAMPLES.md: Example 2 (lines 98-170)

#### About Shape Validation?
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 7 (lines 330-360)
- CODE_FLOW_EXAMPLES.md: Example 4 (lines 260-310)
- QUICK_REFERENCE.md: Debugging checklist (line 200)

#### About Loop Op Comparison?
- START_HERE.md: "Comparison" section
- QUICK_REFERENCE.md: "Scan vs Loop" table (line 150)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 9 (lines 410-430)
- CODE_FLOW_EXAMPLES.md: Example 3 (lines 165-215)

#### About Code Modification?
- QUICK_REFERENCE.md: "Key functions to modify" section
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 10 (lines 435-460)
- CODE_FLOW_EXAMPLES.md: Example 6 (lines 310-350)

#### About Debugging?
- QUICK_REFERENCE.md: Debugging checklist (lines 195-210)
- CODE_FLOW_EXAMPLES.md: Any example showing memory layout
- START_HERE.md: Critical limitation section

---

## File Location Quick Reference

| Component | File | Lines | Search Term |
|-----------|------|-------|------------|
| Scan class template | scan.h | 69-103 | `template <int OpSet> class Scan` |
| OutputIterator | scan_utils.h | 79-163 | `class OutputIterator` |
| LoopStateVariable | scan_utils.h | 34-68 | `class LoopStateVariable` |
| Scan v8 impl | scan_8.cc | 191-442 | `class Scan8Impl` |
| Scan v9 impl | scan_9.cc | 100-574 | `class ScanImpl` |
| AllocateFinalOutput | scan_utils.cc | 523-535 | `Status OutputIterator::AllocateFinalOutput` |
| MakeShapeConcrete | scan_utils.cc | 388-406 | `static Status MakeShapeConcrete` |
| IterateSequence | scan_utils.cc | 186-294 | `Status IterateSequence` |
| Loop impl | loop.cc | 508-674 | `class LoopImpl` |

---

## Reading Paths

### Path 1: Complete Understanding (2-3 hours)
```
1. Read 00_START_HERE.md (15 min)
2. Read SCAN_IMPLEMENTATION_ANALYSIS.md sections 1-5 (45 min)
3. Study CODE_FLOW_EXAMPLES.md Examples 1-3 (30 min)
4. Read SCAN_IMPLEMENTATION_ANALYSIS.md sections 6-10 (45 min)
5. Study CODE_FLOW_EXAMPLES.md Examples 4-6 (15 min)
6. Reference QUICK_REFERENCE.md as needed (ongoing)
```

### Path 2: Quick Overview (30-45 minutes)
```
1. Read 00_START_HERE.md (20 min)
2. Skim QUICK_REFERENCE.md (15 min)
3. Look at one CODE_FLOW_EXAMPLES.md (10 min)
```

### Path 3: Implementation Focus (1-2 hours)
```
1. Read 00_START_HERE.md (15 min)
2. Read SCAN_IMPLEMENTATION_ANALYSIS.md sections 1-3, 10 (30 min)
3. Study CODE_FLOW_EXAMPLES.md related to your task (20 min)
4. Use QUICK_REFERENCE.md for navigation (ongoing)
5. Reference source files with line numbers (ongoing)
```

### Path 4: Debugging Focus (30 minutes)
```
1. Read 00_START_HERE.md critical limitation section (5 min)
2. Reference QUICK_REFERENCE.md debugging checklist (5 min)
3. Study CODE_FLOW_EXAMPLES.md Example 4 (10 min)
4. Check relevant SCAN_IMPLEMENTATION_ANALYSIS.md section (10 min)
```

---

## Key Concepts Cross-Reference

### Double-Buffering Strategy
- START_HERE.md: Key data structures section
- QUICK_REFERENCE.md: LoopStateVariable definition
- CODE_FLOW_EXAMPLES.md: Example 5 (complete walkthrough)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 3, lines 155-172

### Custom Allocators
- START_HERE.md: "The Mechanism" section
- QUICK_REFERENCE.md: Key functions section
- CODE_FLOW_EXAMPLES.md: Example 6 (complete walkthrough)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 6, lines 305-330

### Shape Validation
- START_HERE.md: "Critical Limitation" section
- QUICK_REFERENCE.md: Shape validation mechanism
- CODE_FLOW_EXAMPLES.md: Example 4 (complete walkthrough)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 7, lines 330-365

### Batch Processing (v8)
- START_HERE.md: "Understanding v8 vs v9" section
- QUICK_REFERENCE.md: Execution flow for v8
- CODE_FLOW_EXAMPLES.md: Example 1 (complete walkthrough)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 2, lines 85-127

### Sequence Processing (v9)
- START_HERE.md: "Understanding v8 vs v9" section
- QUICK_REFERENCE.md: Execution flow for v9
- CODE_FLOW_EXAMPLES.md: Example 2 (complete walkthrough)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 2, lines 128-160

---

## Code Path Index

### Allocation Path
- START_HERE.md: "Most Important Code Paths" section
- QUICK_REFERENCE.md: Memory management section
- CODE_FLOW_EXAMPLES.md: Examples 1, 2 (iterations 0)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 3, lines 160-185

### Execution Loop Path
- START_HERE.md: "Most Important Code Paths" section
- QUICK_REFERENCE.md: Execution flow diagrams
- CODE_FLOW_EXAMPLES.md: All examples (main loops)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 4, lines 185-250

### Shape Validation Path
- START_HERE.md: "Most Important Code Paths" section
- CODE_FLOW_EXAMPLES.md: Example 4 (complete flow)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 7, lines 330-365

### Iteration Advancement
- CODE_FLOW_EXAMPLES.md: All examples (end of iterations)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 4, lines 270-285

---

## Frequently Needed Information

### "What is is_concrete_shape_?"
- START_HERE.md: Key data structures section
- QUICK_REFERENCE.md: OutputIterator definition
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 3, lines 100-105
- CODE_FLOW_EXAMPLES.md: Examples 2 (iteration 0)

### "What's the custom allocator for?"
- START_HERE.md: "The Mechanism" section
- QUICK_REFERENCE.md: Key functions section
- CODE_FLOW_EXAMPLES.md: Example 6
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 6

### "What happens in iteration 0?"
- CODE_FLOW_EXAMPLES.md: Example 2, iteration 0 section
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 4, lines 215-240
- START_HERE.md: Phase 2

### "How does the buffer get allocated?"
- CODE_FLOW_EXAMPLES.md: Examples 1, 2 (AllocateOutputTensors sections)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 3, lines 160-185
- START_HERE.md: Phase 1

### "What's the memory layout?"
- CODE_FLOW_EXAMPLES.md: Final output sections in examples
- START_HERE.md: "Final Output" sections

### "How are outputs sliced?"
- CODE_FLOW_EXAMPLES.md: Examples 1, 2 (slicer creation sections)
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 3, lines 170-180

### "What's the bug with changing shapes?"
- START_HERE.md: "Critical Limitation" section
- CODE_FLOW_EXAMPLES.md: Example 4, scenario section
- SCAN_IMPLEMENTATION_ANALYSIS.md: Section 7, lines 350-365

---

## Implementation Checklist

Before modifying code:
- [ ] Read START_HERE.md completely
- [ ] Read SCAN_IMPLEMENTATION_ANALYSIS.md section 1-3
- [ ] Find your function in QUICK_REFERENCE.md
- [ ] Study relevant CODE_FLOW_EXAMPLES.md
- [ ] Open source files and verify line numbers
- [ ] Check QUICK_REFERENCE.md debugging checklist
- [ ] Design changes using section 10 of SCAN_IMPLEMENTATION_ANALYSIS.md
- [ ] Implement with reference to CODE_FLOW_EXAMPLES.md
- [ ] Test using debugging checklist

---

## Document Statistics

| Document | Lines | Size | Focus |
|----------|-------|------|-------|
| 00_START_HERE.md | 262 | 13K | Entry point, big picture |
| SCAN_IMPLEMENTATION_ANALYSIS.md | 523 | 18K | Complete analysis |
| QUICK_REFERENCE.md | 222 | 7K | Quick lookup |
| CODE_FLOW_EXAMPLES.md | 391 | 13K | Detailed examples |
| README.md | 248 | 8K | Navigation |
| **TOTAL** | **1,746** | **59K** | **Comprehensive** |
| This INDEX.md | ~350 | ~14K | Cross-reference |

---

## Quick Links

### Most Important Files in ONNX Runtime
```
/onnxruntime/core/providers/cpu/controlflow/
├── scan.h              # Scan class
├── scan_utils.h        # OutputIterator, LoopStateVariable
├── scan_8.cc           # Scan v8 implementation
├── scan_9.cc           # Scan v9 implementation
├── scan_utils.cc       # Implementations
├── loop.h              # Loop class (comparison)
└── loop.cc             # Loop implementation (comparison)
```

### Most Important Functions
```
OutputIterator::AllocateFinalOutput() [scan_utils.cc:523-535]
  └─ The trigger for dynamic shape allocation

MakeShapeConcrete() [scan_utils.cc:388-406]
  └─ Validates and fills symbolic dimensions

IterateSequence() [scan_utils.cc:186-294]
  └─ The main execution loop

OutputIterator::AllocateFinalBuffer() [scan_utils.cc:468-521]
  └─ Allocates the actual output buffer

LoopStateVariable::Next() [scan_utils.cc:383-386]
  └─ Cycles temporary buffers
```

---

## Navigation Tips

1. **Use Ctrl+F** to search for specific function names
2. **Use line numbers** to jump directly to code in your IDE
3. **Cross-reference** using the tables in this INDEX
4. **Start small** with Example 1 in CODE_FLOW_EXAMPLES.md
5. **Gradually increase** complexity (Examples 2-6)
6. **Use QUICK_REFERENCE.md** for ongoing lookup during implementation

---

## Got a Specific Question?

### "How does [X] work?"
→ Search this INDEX for [X], find relevant section, read it.

### "Where is [function]?"
→ Check QUICK_REFERENCE.md "File Location Quick Reference" table.

### "What do I modify for [task]?"
→ Read SCAN_IMPLEMENTATION_ANALYSIS.md section 10.

### "I'm lost!"
→ Read START_HERE.md again, especially "Document Roadmap" section.

### "Show me an example of [scenario]"
→ Find matching example in CODE_FLOW_EXAMPLES.md, read it completely.

---

## Last But Not Least

**This documentation is comprehensive, but code is the source of truth.**

Always verify:
1. Line numbers match your code version
2. Function signatures are current
3. Expected behavior matches actual code

When in doubt, read the actual source code!

---

Generated: 2024
Based on: ONNX Runtime CPU implementation of Scan operator
Total Lines: 1,746 across all documents
Confidence Level: High (direct code analysis)

