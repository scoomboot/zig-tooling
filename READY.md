# Ready to Work Issues - Library Conversion

**Current Focus**: Library conversion from CLI tools to pure Zig library package.

## 📊 Progress Summary
- **Completed**: 9/24 issues (LC001 ✅, LC002 ✅, LC003 ✅, LC004 ✅, LC005 ✅, LC006 ✅, LC007 ✅, LC008 ✅, LC009 ✅)
- **Ready to Start**: LC010, LC011, LC012, LC015, LC022, LC023, LC024 (7 issues)
- **In Progress**: None
- **Blocked**: 7 issues awaiting dependencies

## 🟢 No Dependencies - Start Immediately

- **#LC022**: Fix arena allocator tracking
  - **Component**: src/memory_analyzer.zig
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: Arena allocator variable tracking is broken
  - **Notes**: trackArenaAllocatorVars() never called, breaks arena detection

- **#LC023**: Document memory management for helper functions
  - **Component**: src/memory_analyzer.zig
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: Some helper functions return allocated memory without clear documentation
  - **Notes**: formatAllowedAllocators() returns owned memory that must be freed

- **#LC024**: Improve allocator type detection
  - **Component**: src/memory_analyzer.zig
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: Current allocator type detection is limited to known patterns
  - **Notes**: Custom allocators with non-standard names won't be detected

## 🟢 All Dependencies Completed - Ready to Start

- **#LC010**: Refactor testing analyzer  
  - **Component**: src/testing_analyzer.zig
  - **Status**: Ready
  - **Dependencies**: #LC008 ✅ (Completed 2025-07-26)
  - **Details**: Make test categories configurable, return structured results
  - **Notes**: 
    - TestCategory enum hardcoded (src/testing_analyzer.zig:43-63)
    - Remove legacy alias: `pub const TestingIssue = Issue;` (line 14)
    - Clean up duplicate type imports from LC008 work

- **#LC011**: Optimize scope tracker
  - **Component**: src/scope_tracker.zig
  - **Status**: Ready
  - **Dependencies**: #LC008 ✅ (Completed 2025-07-26)
  - **Details**: Expose as public API, add builder pattern

- **#LC012**: Simplify logging system
  - **Component**: src/app_logger.zig
  - **Status**: Ready
  - **Dependencies**: #LC008 ✅ (Completed 2025-07-26)
  - **Details**: Make logging optional with callback interface
  - **Notes**: app_logger.zig still has file rotation, not integrated with Config

- **#LC015**: Result formatting utilities
  - **Component**: src/formatters.zig (new)
  - **Status**: Ready
  - **Dependencies**: #LC008 ✅ (Completed 2025-07-26)
  - **Details**: Format analysis results for different outputs
  - **Notes**: AnalysisOptions fields unused (src/types.zig:147-154)

## 🔄 Next Wave (1 Dependency Away)

*Issues that become available after completing current work*






### After #LC010 (Testing analyzer refactored)
- **#LC013**: Build system integration helpers (depends on LC009 ✅ + LC010)
  - Note: PatternConfig not implemented (src/types.zig:140-145)
- **#LC014**: Common patterns library (depends on LC009 ✅ + LC010)

### After multiple dependencies complete
- **#LC016**: API documentation (needs #LC005-#LC015)
- **#LC017**: Integration examples (needs #LC013-#LC015)
- **#LC018**: Migration guide (needs #LC016)
- **#LC019**: Update test suite (needs #LC005-#LC012)
- **#LC020**: Integration testing (needs #LC019)
- **#LC021**: Documentation testing (needs #LC016-#LC018)

## 📊 Phase Execution Order

### Recommended Execution Path:

1. **Phase 1 (Sequential)**: #LC001 ✅ → #LC002 ✅ → #LC003 ✅ → #LC004 ✅
2. **Phase 2 Start**: #LC005 ✅ → #LC006 ✅ → #LC007 ✅ → #LC008 ✅
3. **Phase 3 (Parallel)**: #LC009, #LC010, #LC011, #LC012
4. **Phase 4 (After analyzers)**: #LC013, #LC014, #LC015
5. **Phase 5 (Documentation)**: #LC016 → #LC017, #LC018
6. **Phase 6 (Testing)**: #LC019 → #LC020, #LC021

### Critical Path:
```
#LC001 ✅ → #LC002 ✅ → #LC003 ✅ → #LC004 ✅ → #LC005 ✅ → #LC006 ✅ → #LC007 ✅ → #LC008 ✅ → #LC009/LC010
```

This path unlocks the most work and enables parallel development.

## 🎯 Quick Reference

- **Start Now**: #LC010, #LC011, #LC012, #LC015, #LC022, #LC023, #LC024 (7 issues ready)
- **Total Issues**: 24
- **Critical Issues**: 7
- **Estimated Time**: 11-16 hours total

---

*This file tracks library conversion issues from ISSUES.md. Updated: 2025-07-26 (LC009 completed, 3 new issues discovered)*