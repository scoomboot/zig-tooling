# Ready to Work Issues - Library Conversion

**Current Focus**: Library conversion from CLI tools to pure Zig library package.

## 📊 Progress Summary
- **Completed**: 19/38 issues (LC001 ✅, LC002 ✅, LC003 ✅, LC004 ✅, LC005 ✅, LC006 ✅, LC007 ✅, LC008 ✅, LC009 ✅, LC010 ✅, LC011 ✅, LC012 ✅, LC022 ✅, LC023 ✅, LC024 ✅, LC025 ✅, LC026 ✅, LC027 ✅, LC028 ✅)
- **Ready to Start**: LC013, LC014, LC015, LC029, LC030, LC031, LC032, LC033, LC034, LC035, LC036, LC037 (12 issues)
- **In Progress**: None
- **Blocked**: 6 issues awaiting dependencies

## 🟢 No Dependencies - Start Immediately

*All no-dependency issues have been completed*

## 🟢 All Dependencies Completed - Ready to Start

- **#LC015**: Result formatting utilities
  - **Component**: src/formatters.zig (new)
  - **Status**: Ready
  - **Dependencies**: #LC008 ✅ (Completed 2025-07-26)
  - **Details**: Format analysis results for different outputs
  - **Notes**: AnalysisOptions fields unused (src/types.zig:147-154)

- **#LC029**: Implement regex support for allocator patterns
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: #LC024 ✅ (Completed 2025-07-27)
  - **Details**: AllocatorPattern.is_regex field exists but is not implemented
  - **Notes**: Would enable precise pattern matching like "^my_.*_allocator$"

- **#LC030**: Add option to disable default allocator patterns
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: #LC024 ✅ (Completed 2025-07-27)
  - **Details**: No way to use only custom patterns without defaults
  - **Notes**: Users might want complete control over pattern matching

- **#LC031**: Add pattern conflict detection
  - **Component**: src/memory_analyzer.zig
  - **Status**: Ready
  - **Dependencies**: #LC028 ✅ (Completed 2025-07-27)
  - **Details**: Patterns that overlap can cause unexpected matches
  - **Notes**: Example: "alloc" would match before "allocator" in "my_allocator_var"

- **#LC032**: Add case-insensitive pattern matching option
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: #LC024 ✅ (Completed 2025-07-27)
  - **Details**: Pattern matching is currently case-sensitive only
  - **Notes**: Some projects may have inconsistent allocator naming

- **#LC033**: Add pattern testing utilities
  - **Component**: src/memory_analyzer.zig
  - **Status**: Ready
  - **Dependencies**: #LC024 ✅ (Completed 2025-07-27)
  - **Details**: No way to test patterns before using them
  - **Notes**: Would help users debug pattern configuration

- **#LC034**: Improve logging callback pattern for stateful collectors
  - **Component**: src/app_logger.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: #LC012 ✅ (Completed 2025-07-27)
  - **Details**: Current callback pattern doesn't work well with stateful log collectors
  - **Notes**: Tests had to use global variables instead of proper closures

- **#LC035**: Add log filtering by category
  - **Component**: src/app_logger.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: #LC012 ✅ (Completed 2025-07-27)
  - **Details**: Can only filter by log level, not by category
  - **Notes**: Users might want only specific analyzer logs

- **#LC036**: Add structured logging format helpers
  - **Component**: src/app_logger.zig
  - **Status**: Ready
  - **Dependencies**: #LC012 ✅ (Completed 2025-07-27)
  - **Details**: No standardized format for structured log messages
  - **Notes**: Could provide JSON, logfmt, human-readable formatters

- **#LC037**: Document logger lifecycle and memory safety
  - **Component**: src/app_logger.zig, CLAUDE.md
  - **Status**: Ready
  - **Dependencies**: #LC012 ✅ (Completed 2025-07-27)
  - **Details**: Logger holds reference to LoggingConfig but no lifetime guarantees
  - **Notes**: Could lead to use-after-free if misused

## 🔄 Next Wave (1 Dependency Away)

*Issues that become available after completing current work*






### Ready Now (LC010 completed ✅)
- **#LC013**: Build system integration helpers (depends on LC009 ✅ + LC010 ✅)
  - Note: PatternConfig not implemented (src/types.zig:140-145)
- **#LC014**: Common patterns library (depends on LC009 ✅ + LC010 ✅)

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
3. **Phase 3 (Parallel)**: #LC009 ✅, #LC010 ✅, #LC011 ✅, #LC012 ✅
4. **Phase 4 (After analyzers)**: #LC013, #LC014, #LC015
5. **Phase 5 (Documentation)**: #LC016 → #LC017, #LC018
6. **Phase 6 (Testing)**: #LC019 → #LC020, #LC021

### Critical Path:
```
#LC001 ✅ → #LC002 ✅ → #LC003 ✅ → #LC004 ✅ → #LC005 ✅ → #LC006 ✅ → #LC007 ✅ → #LC008 ✅ → #LC009/LC010
```

This path unlocks the most work and enables parallel development.

## 🎯 Quick Reference

- **Start Now**: #LC013, #LC014, #LC015, #LC029, #LC030, #LC031, #LC032, #LC033, #LC034, #LC035, #LC036, #LC037 (12 issues ready)
- **Total Issues**: 38
- **Critical Issues**: 6
- **Estimated Time**: 14-20 hours total

---

*This file tracks library conversion issues from ISSUES.md. Updated: 2025-07-27 (LC012 completed, 4 new logging-related issues discovered)*