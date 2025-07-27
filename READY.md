# Ready to Work Issues - Library Conversion

**Current Focus**: Library conversion from CLI tools to pure Zig library package.

## 📊 Progress Summary
- **Completed**: 31/68 issues (LC001 ✅, LC002 ✅, LC003 ✅, LC004 ✅, LC005 ✅, LC006 ✅, LC007 ✅, LC008 ✅, LC009 ✅, LC010 ✅, LC011 ✅, LC012 ✅, LC013 ✅, LC014 ✅, LC015 ✅, LC016 ✅, LC017 ✅, LC019 ✅, LC020 ✅, LC021 ✅, LC022 ✅, LC023 ✅, LC024 ✅, LC025 ✅, LC026 ✅, LC027 ✅, LC028 ✅, LC050 ✅, LC056 ✅, LC057 ✅, LC062 ✅)
- **Ready to Start**: 36 issues (0 CRITICAL, 1 HIGH, 12 TIER 2, 24 TIER 3)
- **In Progress**: None
- **Blocked**: None

## 🟢 No Dependencies - Start Immediately

*No critical bugs currently - all segfaults have been resolved!*

## 🟢 All Dependencies Completed - Ready to Start

### 🎯 TIER 1: Critical v1.0 Blockers (Start These First!)

*All TIER 1 issues have been completed! The library now has all critical components for v1.0.*

### 🏆 TIER 2: Professional Polish (After TIER 1)

#### User-Reported Issues (Highest Priority)
- **#LC069**: Fix built-in pattern conflicts with std.testing.allocator (GitHub Issue #3) *[TIER 2 - HIGH PRIORITY]*
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: Persistent pattern name conflicts with std.testing.allocator across multiple files
  - **Notes**: Reported in GitHub issue #3, affects v0.1.2, makes tool analysis unreliable

- **#LC068**: Improve memory ownership transfer detection (GitHub Issue #2) *[TIER 2 - HIGH PRIORITY]*
  - **Component**: src/memory_analyzer.zig
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: False positive "missing defer" warnings for valid Zig memory ownership patterns
  - **Notes**: Reported in GitHub issue #2, affects v0.1.2, causes unnecessary code modifications

#### Security/Correctness
- **#LC052**: Add proper JSON/XML escape functions to formatters *[TIER 2 - HIGH PRIORITY]*
  - **Component**: src/formatters.zig, src/utils.zig
  - **Status**: Ready
  - **Dependencies**: #LC015 ✅ (Completed 2025-07-27)
  - **Details**: Current escape functions in examples are placeholders
  - **Notes**: Critical for correct output in CI/CD environments, could cause security issues

- **#LC066**: Add CI validation for integration test compilation *[TIER 2 - HIGH PRIORITY]*
  - **Component**: CI configuration, build.zig
  - **Status**: Ready
  - **Dependencies**: #LC060 (when completed)
  - **Details**: Integration tests had compilation failures that went unnoticed
  - **Notes**: Critical for maintaining test suite health

#### API Usability & Documentation
- **#LC064**: Add formatter support for ProjectAnalysisResult type *[TIER 2]*
  - **Component**: src/formatters.zig, src/patterns.zig
  - **Status**: Ready
  - **Dependencies**: #LC015 ✅ (Completed 2025-07-27)
  - **Details**: Formatters only accept AnalysisResult but patterns.checkProject returns ProjectAnalysisResult
  - **Notes**: Common user pain point when using patterns library with formatters

- **#LC063**: Improve API documentation coverage *[TIER 2]*
  - **Component**: All public modules, especially src/zig_tooling.zig
  - **Status**: Ready
  - **Dependencies**: #LC021 ✅ (Completed 2025-07-27)
  - **Details**: API documentation coverage is only 49% (82/166 public items)
  - **Notes**: Critical for user adoption and library usability

- **#LC051**: Create example quality check executable *[TIER 2]*
  - **Component**: examples/tools/quality_check.zig (new)
  - **Status**: Ready
  - **Dependencies**: #LC017 ✅ (Completed 2025-07-27)
  - **Details**: The build_integration.zig example references a quality check tool that doesn't exist
  - **Notes**: Would serve as a starting point for users creating their own tools

- **#LC039**: Complete output formatter implementations *[TIER 2]*
  - **Component**: src/build_integration.zig
  - **Status**: Ready
  - **Dependencies**: #LC013 ✅, #LC015 ✅ (Both completed 2025-07-27)
  - **Details**: JSON and GitHub Actions formatters are placeholder implementations
  - **Notes**: Should coordinate with formatters module

#### Performance/Infrastructure
- **#LC043**: Add parallel file analysis support *[TIER 2]*
  - **Component**: src/build_integration.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: #LC013 ✅, #LC015 ✅ (Both completed 2025-07-27)
  - **Details**: AnalysisOptions.parallel field exists but not implemented
  - **Notes**: Would improve analysis performance for large codebases

- **#LC060**: Add CI configuration for integration test execution *[TIER 2]*
  - **Component**: build.zig, CI configuration, tests/integration/
  - **Status**: Ready
  - **Dependencies**: #LC020 ✅ (Completed 2025-07-27)
  - **Details**: Integration tests need proper CI configuration with timeouts and resource limits
  - **Notes**: Comprehensive tests may be slow and require CI-specific configuration

- **#LC038**: Implement proper glob pattern library for build integration *[TIER 2]*
  - **Component**: src/build_integration.zig
  - **Status**: Ready
  - **Dependencies**: #LC013 ✅ (Completed 2025-07-27)
  - **Details**: Current glob pattern matching is basic and limited
  - **Notes**: Would improve pattern matching for complex file selection

### ✨ TIER 3: Future Enhancements (Defer Until Later)

#### Development Process & Quality (Higher Value)
- **#LC049**: Add static analysis for recursive function call detection *[TIER 3]*
  - **Component**: Static analysis tooling, CI/CD configuration
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: Critical recursive function call bugs not caught by static analysis or testing
  - **Notes**: Found recursive bugs in addIssue() methods during LC015 that would cause stack overflow

- **#LC048**: Enhance error boundary testing framework *[TIER 3]*
  - **Component**: tests/, src/patterns.zig
  - **Status**: Ready
  - **Dependencies**: #LC019 ✅ (Completed 2025-07-27)
  - **Details**: Error handling gaps found during implementation not systematically tested
  - **Notes**: Would catch error handling gaps before production

- **#LC037**: Document logger lifecycle and memory safety *[TIER 3]*
  - **Component**: src/app_logger.zig, CLAUDE.md
  - **Status**: Ready
  - **Dependencies**: #LC012 ✅ (Completed 2025-07-27)
  - **Details**: Logger holds reference to LoggingConfig but no lifetime guarantees
  - **Notes**: Could lead to use-after-free if misused

- **#LC058**: Add memory ownership tracking type system *[TIER 3]*
  - **Component**: src/types.zig, src/utils.zig
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: String fields can be either heap-allocated or literals, causing memory management bugs
  - **Notes**: Would prevent issues like LC056 and LC057 at compile time using ownership-aware types

- **#LC046**: Add systematic Zig version compatibility testing *[TIER 3]*
  - **Component**: build.zig, tests/, CI configuration
  - **Status**: Ready
  - **Dependencies**: #LC019 ✅ (Completed 2025-07-27)
  - **Details**: Compatibility issues with Zig versions not caught until runtime
  - **Notes**: Would prevent compatibility regressions in future

- **#LC047**: Add build configuration validation *[TIER 3]*
  - **Component**: build.zig, tests/
  - **Status**: Ready
  - **Dependencies**: #LC019 ✅ (Completed 2025-07-27)
  - **Details**: Missing test files in build configuration not automatically detected
  - **Notes**: Would prevent test files from being accidentally excluded

- **#LC067**: Create API migration detection tooling *[TIER 3]*
  - **Component**: Development tooling, tests/
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: API changes in library aren't automatically detected in test code
  - **Notes**: Would have prevented writeFile and enum field mismatch issues

#### Library Usability & Examples
- **#LC059**: Fix example file references to non-existent sample projects *[TIER 3 - but was HIGH]*
  - **Component**: examples/basic_usage.zig, examples/
  - **Status**: Ready
  - **Dependencies**: #LC020 ✅ (Completed 2025-07-27)
  - **Details**: Example files reference deleted sample project files that no longer exist
  - **Notes**: Critical for user onboarding but moved to TIER 3 as workaround exists

- **#LC053**: Review and fix reserved keyword conflicts in public APIs *[TIER 3]*
  - **Component**: src/types.zig, all public modules
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: Some enum fields use reserved keywords requiring escape syntax
  - **Notes**: Found `error` field requiring `@"error"` escape in ide_integration.zig

- **#LC054**: Add string manipulation utilities *[TIER 3]*
  - **Component**: src/utils.zig
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: Common string operations needed for custom analyzers
  - **Notes**: Had to implement toCamelCase in custom_analyzer.zig example

- **#LC055**: Add additional issue types for custom analyzers *[TIER 3]*
  - **Component**: src/types.zig
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: Limited issue types for custom analysis rules
  - **Notes**: Custom analyzer example had to use generic types

- **#LC065**: Document thread array mutability patterns for concurrent tests *[TIER 3]*
  - **Component**: Documentation, tests/integration/
  - **Status**: Ready
  - **Dependencies**: None
  - **Details**: Zig's array mutability rules for concurrent code are confusing and caused multiple errors
  - **Notes**: Common source of confusion for developers writing concurrent tests

- **#LC061**: Clean up integration test runner unused imports *[TIER 3]*
  - **Component**: tests/integration/test_integration_runner.zig
  - **Status**: Ready
  - **Dependencies**: #LC020 ✅ (Completed 2025-07-27)
  - **Details**: Integration test runner imports sub-modules but doesn't use them
  - **Notes**: Minor technical debt from LC020 implementation

#### Allocator Pattern Enhancements
- **#LC030**: Add option to disable default allocator patterns *[TIER 3]*
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: #LC024 ✅ (Completed 2025-07-27)
  - **Details**: No way to use only custom patterns without defaults
  - **Notes**: Users might want complete control over pattern matching

- **#LC031**: Add pattern conflict detection *[TIER 3]*
  - **Component**: src/memory_analyzer.zig
  - **Status**: Ready
  - **Dependencies**: #LC028 ✅ (Completed 2025-07-27)
  - **Details**: Patterns that overlap can cause unexpected matches
  - **Notes**: Example: "alloc" would match before "allocator" in "my_allocator_var"

- **#LC033**: Add pattern testing utilities *[TIER 3]*
  - **Component**: src/memory_analyzer.zig
  - **Status**: Ready
  - **Dependencies**: #LC024 ✅ (Completed 2025-07-27)
  - **Details**: No way to test patterns before using them
  - **Notes**: Would help users debug pattern configuration

- **#LC029**: Implement regex support for allocator patterns *[TIER 3]*
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: #LC024 ✅ (Completed 2025-07-27)
  - **Details**: AllocatorPattern.is_regex field exists but is not implemented
  - **Notes**: Would enable precise pattern matching like "^my_.*_allocator$"

- **#LC032**: Add case-insensitive pattern matching option *[TIER 3]*
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: #LC024 ✅ (Completed 2025-07-27)
  - **Details**: Pattern matching is currently case-sensitive only
  - **Notes**: Some projects may have inconsistent allocator naming

#### Build Integration & Code Quality
- **#LC044**: Extract shared glob pattern matching utility *[TIER 3]*
  - **Component**: src/utils.zig, src/patterns.zig, src/build_integration.zig
  - **Status**: Ready
  - **Dependencies**: #LC014 ✅ (Completed 2025-07-27)
  - **Details**: Duplicate matchesPattern() functions need consolidation
  - **Notes**: Code duplication between patterns.zig and build_integration.zig

- **#LC045**: Add test utilities for temporary directory setup *[TIER 3]*
  - **Component**: tests/test_utils.zig (new), tests/
  - **Status**: Ready
  - **Dependencies**: #LC014 ✅ (Completed 2025-07-27)
  - **Details**: Test setup for temporary directories is verbose and duplicated
  - **Notes**: Would improve test maintainability and readability

- **#LC041**: Implement incremental analysis for build integration *[TIER 3]*
  - **Component**: src/build_integration.zig
  - **Status**: Ready
  - **Dependencies**: #LC013 ✅ (Completed 2025-07-27)
  - **Details**: Build steps always analyze all files, no incremental support
  - **Notes**: Would significantly improve build performance for large projects

- **#LC042**: Complete pre-commit hook implementations *[TIER 3]*
  - **Component**: src/build_integration.zig
  - **Status**: Ready
  - **Dependencies**: #LC013 ✅ (Completed 2025-07-27)
  - **Details**: Only bash pre-commit hooks are fully implemented
  - **Notes**: Fish and PowerShell hooks are placeholder implementations

#### Logging Enhancements
- **#LC034**: Improve logging callback pattern for stateful collectors *[TIER 3]*
  - **Component**: src/app_logger.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: #LC012 ✅ (Completed 2025-07-27)
  - **Details**: Current callback pattern doesn't work well with stateful log collectors
  - **Notes**: Tests had to use global variables instead of proper closures

- **#LC035**: Add log filtering by category *[TIER 3]*
  - **Component**: src/app_logger.zig, src/types.zig
  - **Status**: Ready
  - **Dependencies**: #LC012 ✅ (Completed 2025-07-27)
  - **Details**: Can only filter by log level, not by category
  - **Notes**: Users might want only specific analyzer logs

- **#LC036**: Add structured logging format helpers *[TIER 3]*
  - **Component**: src/app_logger.zig
  - **Status**: Ready
  - **Dependencies**: #LC012 ✅ (Completed 2025-07-27)
  - **Details**: No standardized format for structured log messages
  - **Notes**: Could provide JSON, logfmt, human-readable formatters


## 🔄 Next Wave (1 Dependency Away)

*Issues that become available after completing current work*






### Now Available (LC016 ✅ Completed 2025-07-27)

All previously blocked Tier 1 and Tier 2 issues have been moved to their respective sections above.


## 📊 Phase Execution Order

### Recommended Execution Path:

1. **Phase 1 (Sequential)**: #LC001 ✅ → #LC002 ✅ → #LC003 ✅ → #LC004 ✅
2. **Phase 2 Start**: #LC005 ✅ → #LC006 ✅ → #LC007 ✅ → #LC008 ✅
3. **Phase 3 (Parallel)**: #LC009 ✅, #LC010 ✅, #LC011 ✅, #LC012 ✅
4. **Phase 4 (After analyzers)**: #LC013, #LC014, #LC015
5. **Phase 5 (Documentation)**: #LC016 → #LC017
6. **Phase 6 (Testing)**: #LC019 ✅ → #LC020 ✅, #LC021

### Critical Path:
```
#LC001 ✅ → #LC002 ✅ → #LC003 ✅ → #LC004 ✅ → #LC005 ✅ → #LC006 ✅ → #LC007 ✅ → #LC008 ✅ → #LC009/LC010
```

This path unlocks the most work and enables parallel development.

## 🎯 Quick Reference

### Recommended Work Order for v1.0:
1. **🎯 TIER 1 Complete**: All critical v1.0 blockers are done! ✅
2. **🏆 TIER 2 Polish** (in priority order):
   - User-Reported: #LC069, #LC068 (GitHub issues)
   - Security/Correctness: #LC052, #LC066
   - API Usability: #LC064, #LC063, #LC051, #LC039
   - Performance/Infrastructure: #LC043, #LC060, #LC038
3. **✨ TIER 3 Later**: 25 future enhancement issues (defer until v1.1+)

### Current Status:
- **Ready to Start**: 36 issues total (0 CRITICAL, 0 TIER 1, 11 TIER 2, 25 TIER 3)
- **Total Project**: 67 issues (31 completed, 0 blocked, 36 ready)
- **v1.0 Progress**: All critical issues resolved! Ready for TIER 2 polish work.

### Focus Strategy:
**TIER 2 for v1.0 polish → defer TIER 3 to v1.1+**

---

*This file tracks library conversion issues from ISSUES.md. Updated: 2025-07-27 (Added LC068 and LC069 from GitHub issues #2 and #3)*