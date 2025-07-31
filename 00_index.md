# Issue Index

> **Quick navigation for [ISSUES.md](ISSUES.md) - 136 tracked issues across zig-tooling library conversion**

## Active Issues

### Documentation & API
- 🟡 [#LC063](ISSUES.md#L9): Improve API documentation coverage
- 🟡 [#LC037](ISSUES.md#L212): Document logger lifecycle and memory safety
- 🟢 [#LC075](ISSUES.md#L84): Document dogfooding patterns for library developers
- 🟡 [#LC084](ISSUES.md#L774): Document test naming convention requirements
- 🟢 [#LC074](ISSUES.md#L506): Document GitHub codeload URL requirement for build.zig.zon

### Build & CI/CD
- 🟡 [#LC038](ISSUES.md#L66): Implement proper glob pattern library for build integration
- 🟢 [#LC047](ISSUES.md#L285): Add build configuration validation
- 🟢 [#LC079](ISSUES.md#L326): Make quality checks required in CI → [#LC078](00_completed_issues.md#L30)
- 🟢 [#LC041](ISSUES.md#L656): Implement incremental analysis for build integration
- 🟢 [#LC042](ISSUES.md#L674): Complete pre-commit hook implementations

### Testing Infrastructure
- 🟡 [#LC105](ISSUES.md#L45): Need comprehensive memory leak test suite for all public APIs
- 🟡 [#LC101](ISSUES.md#L1131): Audit documentation for Zig 0.14.1 command syntax changes
- 🟡 [#LC080](ISSUES.md#L629): Integration tests should respect resource constraint environment variables → [#LC060](00_completed_issues.md#L787)
- 🟢 [#LC098](ISSUES.md#L1040): Add dedicated test file for memory analyzer
- 🟢 [#LC048](ISSUES.md#L348): Enhance error boundary testing framework
- 🟢 [#LC046](ISSUES.md#L428): Add systematic Zig version compatibility testing
- 🟢 [#LC033](ISSUES.md#L686): Add pattern testing utilities
- 🟢 [#LC071](ISSUES.md#L705): Add ownership pattern testing utilities
- 🟢 [#LC045](ISSUES.md#L799): Add test utilities for temporary directory setup
- 🟢 [#LC083](ISSUES.md#L917): Add test fixture exclusion patterns for sample projects

### Memory & Performance
- 🔴 [#LC104](ISSUES.md#L27): Memory corruption or double-free in ScopeTracker.deinit() → [#LC102](00_completed_issues.md#L5)
- 🔴 [#LC106](ISSUES.md#L63): Memory leaks detected in patterns.checkProject function
- 🔴 [#LC107](ISSUES.md#L12): Memory leaks in analyzeFile() and analyzeSource() functions
- 🔴 [#LC081](ISSUES.md#L585): Fix false positives in quality analyzer allocator detection
- 🔴 [#LC087](ISSUES.md#L239): Implement ownership transfer detection for return values → [#LC081](ISSUES.md#L585)
- 🔴 [#LC088](ISSUES.md#L257): Add data flow analysis for structured returns → [#LC081](ISSUES.md#L585)
- 🟡 [#LC089](ISSUES.md#L179): Create allowed allocator pattern database → [#LC081](ISSUES.md#L489)
- 🟡 [#LC090](ISSUES.md#L197): Implement scope-aware defer analysis → [#LC081](ISSUES.md#L489)
- 🟡 [#LC091](ISSUES.md#L215): Add allocation intent inference → [#LC081](ISSUES.md#L489)
- 🟡 [#LC092](ISSUES.md#L233): Create configuration system for quality checks → [#LC081](ISSUES.md#L489)
- 🟡 [#LC093](ISSUES.md#L251): Implement incremental false positive reduction → [#LC081](ISSUES.md#L489)
- 🟡 [#LC049](ISSUES.md#L305): Add static analysis for recursive function call and use-after-free detection
- 🟢 [#LC097](ISSUES.md#L1016): Enhance function signature parsing for multi-line and complex signatures → [#LC086](00_completed_issues.md#L5)
- 🟢 [#LC094](ISSUES.md#L269): Add semantic analysis for build system patterns → [#LC081](ISSUES.md#L489)
- 🟢 [#LC095](ISSUES.md#L287): Create comprehensive test suite for false positive scenarios → [#LC081](ISSUES.md#L489)
- 🟢 [#LC058](ISSUES.md#L407): Add memory ownership tracking type system
- 🟢 [#LC070](ISSUES.md#L122): Add compile-time validation for default allocator patterns
- 🟢 [#LC031](ISSUES.md#L685): Add pattern conflict detection
- 🟢 [#LC029](ISSUES.md#L723): Implement regex support for allocator patterns
- 🟢 [#LC032](ISSUES.md#L742): Add case-insensitive pattern matching option

### Code Quality & Analysis
- 🟡 [#LC096](ISSUES.md#L998): Fix deprecated API usage throughout codebase
- 🟡 [#LC082](ISSUES.md#L896): Fix false positive missing test detection for inline tests
- 🟢 [#LC109](ISSUES.md#L219): Extract duplicate issue copying logic to helper function
- 🟢 [#LC110](ISSUES.md#L238): Improve error handling specificity in wrapper functions
- 🟢 [#LC077](ISSUES.md#L103): Systematically address self-analysis quality findings → [#LC075](ISSUES.md#L84)
- 🟢 [#LC055](ISSUES.md#L589): Add additional issue types for custom analyzers

### Developer Tools & Utilities
- 🟡 [#LC108](ISSUES.md#L43): Add public freeAnalysisResult() helper function
- 🟡 [#LC039](ISSUES.md#L28): Complete output formatter implementations → [#LC015](00_completed_issues.md#L227)
- 🟡 [#LC043](ISSUES.md#L46): Add parallel file analysis support → [#LC015](00_completed_issues.md#L227)
- 🟢 [#LC099](ISSUES.md#L1072): Improve quality check output handling for large results
- 🟢 [#LC067](ISSUES.md#L466): Create API migration detection tooling
- 🟢 [#LC053](ISSUES.md#L550): Review and fix reserved keyword conflicts in public APIs
- 🟢 [#LC054](ISSUES.md#L569): Add string manipulation utilities
- 🟢 [#LC044](ISSUES.md#L781): Extract shared glob pattern matching utility
- 🟢 [#LC034](ISSUES.md#L854): Improve logging callback pattern for stateful collectors
- 🟢 [#LC035](ISSUES.md#L873): Add log filtering by category
- 🟢 [#LC036](ISSUES.md#L893): Add structured logging format helpers

### Compatibility & Integration
- 🟢 [#LC065](ISSUES.md#L619): Document thread array mutability patterns for concurrent tests
- 🟢 [#LC061](ISSUES.md#L638): Clean up integration test runner unused imports
- 🟢 [#LC085](ISSUES.md#L954): Make example placeholder patterns configurable → [#LC059](00_completed_issues.md#L34)

### ✅ [Completed Issues](00_completed_issues.md) *(Summary)*
*75 issues completed including all core library conversion phases*

**Recently Completed (2025-07-31):**
- [#LC103](00_completed_issues.md#L6): Memory leaks in analyzeMemory() and analyzeTests() wrapper functions ✅
- [#LC103](00_completed_issues.md#L6): Memory leaks in analyzeMemory() and analyzeTests() wrapper functions ✅
- [#LC102](00_completed_issues.md#L29): Fix memory leak in ScopeTracker.openScope ✅ (Investigated but not resolved)
- [#LC100](00_completed_issues.md#L54): Fix multiple test failures in patterns.zig and api.zig test suites ✅

**Recently Completed (2025-07-30):**
- [#LC086](00_completed_issues.md#L30): Create context-aware allocator detection ✅
- [#LC059](00_completed_issues.md#L59): Fix example file references to non-existent sample projects ✅
- [#LC078](00_completed_issues.md#L84): Make zig build quality pass with no warnings or errors ✅

**Recently Completed (2025-07-29):**
- [#LC066](00_completed_issues.md#L25): Add CI validation for integration test compilation ✅
- [#LC060](00_completed_issues.md#L762): Add CI configuration for integration test execution ✅
- [#LC076](00_completed_issues.md#L31): Add build validation for tools/ directory compilation ✅
- [#LC052](00_completed_issues.md#L51): Proper JSON/XML escape functions ✅
- [#LC068](00_completed_issues.md#L72): Memory ownership transfer detection ✅  
- [#LC073](00_completed_issues.md#L174): Memory leak fixes ✅
- [#LC064](00_completed_issues.md#L720): ProjectAnalysisResult formatter support ✅

**Major Milestones:**
- **Phase 1-3**: Project restructuring, API design, core components ✅
- **Phase 4**: Integration helpers and build system support ✅
- **Phase 5**: Documentation and examples ✅
- **Phase 6**: Comprehensive testing infrastructure ✅

---

## Summary Stats

| Category | Count | Priority Breakdown |
|----------|-------|-------------------|
| Documentation & API | 5 | 🟡 Medium: 3, 🟢 Low: 2 |
| Build & CI/CD | 5 | 🟡 Medium: 1, 🟢 Low: 4 |
| Testing Infrastructure | 10 | 🟡 Medium: 3, 🟢 Low: 7 |
| Memory & Performance | 20 | 🔴 High: 6, 🟡 Medium: 6, 🟢 Low: 8 |
| Code Quality & Analysis | 6 | 🟡 Medium: 2, 🟢 Low: 4 |
| Developer Tools & Utilities | 11 | 🟡 Medium: 3, 🟢 Low: 8 |
| Compatibility & Integration | 3 | 🟢 Low: 3 |
| **Total Active** | **60** | **🔴 High: 6, 🟡 Medium: 18, 🟢 Low: 36** |
| ✅ Completed | 76 | Major conversion done |

> 💡 **Tip**: Use `Ctrl+F` to search for specific issue numbers (#LCXXX) or components