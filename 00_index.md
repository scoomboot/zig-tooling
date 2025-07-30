# Issue Index

> **Quick navigation for [ISSUES.md](ISSUES.md) - 111 tracked issues across zig-tooling library conversion**

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
- 🟡 [#LC080](ISSUES.md#L391): Integration tests should respect resource constraint environment variables → [#LC060](00_completed_issues.md#L787)
- 🟢 [#LC048](ISSUES.md#L186): Enhance error boundary testing framework
- 🟢 [#LC046](ISSUES.md#L266): Add systematic Zig version compatibility testing
- 🟢 [#LC033](ISSUES.md#L544): Add pattern testing utilities
- 🟢 [#LC071](ISSUES.md#L563): Add ownership pattern testing utilities
- 🟢 [#LC045](ISSUES.md#L637): Add test utilities for temporary directory setup
- 🟢 [#LC083](ISSUES.md#L755): Add test fixture exclusion patterns for sample projects

### Memory & Performance
- 🔴 [#LC081](ISSUES.md#L345): Fix false positives in quality analyzer allocator detection
- 🟡 [#LC049](ISSUES.md#L141): Add static analysis for recursive function call and use-after-free detection
- 🟢 [#LC058](ISSUES.md#L247): Add memory ownership tracking type system
- 🟢 [#LC070](ISSUES.md#L122): Add compile-time validation for default allocator patterns
- 🟢 [#LC031](ISSUES.md#L525): Add pattern conflict detection
- 🟢 [#LC029](ISSUES.md#L581): Implement regex support for allocator patterns
- 🟢 [#LC032](ISSUES.md#L600): Add case-insensitive pattern matching option

### Code Quality & Analysis
- 🟡 [#LC082](ISSUES.md#L734): Fix false positive missing test detection for inline tests
- 🟢 [#LC077](ISSUES.md#L103): Systematically address self-analysis quality findings → [#LC075](ISSUES.md#L84)
- 🟢 [#LC055](ISSUES.md#L447): Add additional issue types for custom analyzers

### Developer Tools & Utilities
- 🟡 [#LC039](ISSUES.md#L28): Complete output formatter implementations → [#LC015](00_completed_issues.md#L227)
- 🟡 [#LC043](ISSUES.md#L46): Add parallel file analysis support → [#LC015](00_completed_issues.md#L227)
- 🟢 [#LC067](ISSUES.md#L304): Create API migration detection tooling
- 🟢 [#LC053](ISSUES.md#L408): Review and fix reserved keyword conflicts in public APIs
- 🟢 [#LC054](ISSUES.md#L427): Add string manipulation utilities
- 🟢 [#LC044](ISSUES.md#L619): Extract shared glob pattern matching utility
- 🟢 [#LC034](ISSUES.md#L692): Improve logging callback pattern for stateful collectors
- 🟢 [#LC035](ISSUES.md#L711): Add log filtering by category
- 🟢 [#LC036](ISSUES.md#L731): Add structured logging format helpers

### Compatibility & Integration
- 🟢 [#LC065](ISSUES.md#L467): Document thread array mutability patterns for concurrent tests
- 🟢 [#LC061](ISSUES.md#L486): Clean up integration test runner unused imports
- 🟢 [#LC085](ISSUES.md#L792): Make example placeholder patterns configurable → [#LC059](00_completed_issues.md#L5)

### ✅ [Completed Issues](00_completed_issues.md) *(Summary)*
*72 issues completed including all core library conversion phases*

**Recently Completed (2025-07-30):**
- [#LC059](00_completed_issues.md#L5): Fix example file references to non-existent sample projects ✅
- [#LC078](00_completed_issues.md#L30): Make zig build quality pass with no warnings or errors ✅

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
| Testing Infrastructure | 7 | 🟡 Medium: 1, 🟢 Low: 6 |
| Memory & Performance | 7 | 🔴 High: 1, 🟡 Medium: 1, 🟢 Low: 5 |
| Code Quality & Analysis | 3 | 🟡 Medium: 1, 🟢 Low: 2 |
| Developer Tools & Utilities | 9 | 🟡 Medium: 2, 🟢 Low: 7 |
| Compatibility & Integration | 3 | 🟢 Low: 3 |
| **Total Active** | **39** | **🔴 High: 1, 🟡 Medium: 9, 🟢 Low: 29** |
| ✅ Completed | 72 | Major conversion done |

> 💡 **Tip**: Use `Ctrl+F` to search for specific issue numbers (#LCXXX) or components