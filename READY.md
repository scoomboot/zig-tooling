# Ready to Work Issues - Library Conversion

**Current Focus**: Library conversion from CLI tools to pure Zig library package.

## 🟢 No Dependencies - Start Immediately

### Critical Priority

- **#LC001**: Clean up file structure
  - **Component**: All CLI files, scripts, docs
  - **Status**: Backlog
  - **Dependencies**: None
  - **Details**: Delete all CLI-related files, shell scripts, and CLI documentation
  - **Action**: Start with this to clear the codebase

## 🟢 All Dependencies Completed - Ready to Start

*Issues will appear here as their dependencies are completed*

## 🔄 Next Wave (1 Dependency Away)

*Issues that become available after completing current work*

### After #LC001 (Clean up file structure)
- **#LC002**: Restructure source tree
  - **Details**: Flatten directory structure and rename files for library usage
  - **Unlocks**: #LC003

### After #LC002 (Restructure source tree)
- **#LC003**: Update build.zig for library
  - **Details**: Remove all executable targets and configure as pure library
  - **Unlocks**: #LC004

### After #LC003 (Update build.zig)
- **#LC004**: Update build.zig.zon metadata
  - **Details**: Update package metadata for library distribution
  - **Unlocks**: #LC005

### After #LC004 (Update metadata)
- **#LC005**: Design public API surface
  - **Details**: Create main library interface with clean public API
  - **Unlocks**: #LC006, #LC007

### After #LC005 (Design API)
- **#LC006**: Simplify configuration system
- **#LC007**: Remove CLI dependencies
  - **Unlocks**: #LC008

### After #LC007 (Remove CLI deps)
- **#LC008**: Improve error handling
  - **Unlocks**: #LC009, #LC010, #LC011, #LC012, #LC015

### After #LC008 (Error handling)
- **#LC009**: Refactor memory analyzer
- **#LC010**: Refactor testing analyzer
- **#LC011**: Optimize scope tracker
- **#LC012**: Simplify logging system
- **#LC015**: Result formatting utilities

### After #LC009 + #LC010 (Analyzers refactored)
- **#LC013**: Build system integration helpers
- **#LC014**: Common patterns library

### After multiple dependencies complete
- **#LC016**: API documentation (needs #LC005-#LC015)
- **#LC017**: Integration examples (needs #LC013-#LC015)
- **#LC018**: Migration guide (needs #LC016)
- **#LC019**: Update test suite (needs #LC005-#LC012)
- **#LC020**: Integration testing (needs #LC019)
- **#LC021**: Documentation testing (needs #LC016-#LC018)

## 📊 Phase Execution Order

### Recommended Execution Path:

1. **Phase 1 (Sequential)**: #LC001 → #LC002 → #LC003 → #LC004
2. **Phase 2 Start**: #LC005 → (#LC006, #LC007 parallel) → #LC008
3. **Phase 3 (Parallel)**: #LC009, #LC010, #LC011, #LC012
4. **Phase 4 (After analyzers)**: #LC013, #LC014, #LC015
5. **Phase 5 (Documentation)**: #LC016 → #LC017, #LC018
6. **Phase 6 (Testing)**: #LC019 → #LC020, #LC021

### Critical Path:
```
#LC001 → #LC002 → #LC003 → #LC004 → #LC005 → #LC007 → #LC008 → #LC009/LC010
```

This path unlocks the most work and enables parallel development.

## 🎯 Quick Reference

- **Start Now**: #LC001 (Clean up file structure)
- **Total Issues**: 21
- **Critical Issues**: 7
- **Estimated Time**: 10-15 hours total

---

*This file tracks library conversion issues from ISSUES.md. Updated: 2025-07-25*