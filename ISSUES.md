# Issue Tracking

> **[← Back to Issue Index](00_index.md)**

## Active Issues

---

---

- [ ] #LC104: Memory corruption or double-free in ScopeTracker.deinit()
  - **Component**: src/scope_tracker.zig
  - **Priority**: High
  - **Created**: 2025-07-31
  - **Dependencies**: #LC102 (related)
  - **Details**: Memory corruption or double-free in ScopeTracker.deinit() - crashes when trying to free scope names
  - **Requirements**:
    - Investigate root cause of the crash (double-free vs corruption)
    - Fix the memory management architecture in ScopeTracker
    - Ensure proper ownership tracking of scope names
    - Add defensive programming checks
  - **Notes**:
    - Discovered during LC102 investigation
    - GPA assertion failure at debug_allocator.zig:951 when calling [src/scope_tracker.zig:365](src/scope_tracker.zig#L365)
    - Suggests deeper architectural issues beyond just memory leaks
    - May require redesigning how scope names are managed

---

- [ ] #LC105: Need comprehensive memory leak test suite for all public APIs
  - **Component**: tests/
  - **Priority**: Medium
  - **Created**: 2025-07-31
  - **Dependencies**: None
  - **Details**: Need comprehensive memory leak test suite for all public APIs
  - **Requirements**:
    - Create systematic GPA-based tests for all public APIs
    - Test analyzeFile, analyzeSource, checkProject, checkFile functions
    - Test all formatter functions with GPA
    - Add tests for error paths and edge cases
    - Create helper utilities for memory leak testing
  - **Notes**:
    - Currently only have memory leak tests for specific components
    - Would catch issues like LC103 automatically
    - Should be part of standard test suite
    - Could prevent memory leaks from reaching production

---

- [ ] #LC106: Memory leaks detected in patterns.checkProject function
  - **Component**: src/patterns.zig
  - **Priority**: High
  - **Created**: 2025-07-31
  - **Dependencies**: None
  - **Details**: Memory leaks detected in patterns.checkProject function
  - **Requirements**:
    - Fix memory leaks in checkProject implementation
    - Review all allocation/deallocation pairs
    - Check for leaks in error paths
    - Verify freeProjectResult properly cleans up all allocations
  - **Notes**:
    - Found during LC102 investigation in test_scope_tracker_memory.zig test "LC073: patterns.checkProject memory leak"
    - Multiple leaked allocations followed by crash in freeProjectResult
    - Test shows leaks at [src/patterns.zig:167](src/patterns.zig#L167), [src/patterns.zig:172](src/patterns.zig#L172), [src/patterns.zig:173](src/patterns.zig#L173)
    - May be related to how issues are duplicated and aggregated

---

- [ ] #LC107: Memory leaks in analyzeFile() and analyzeSource() functions
  - **Component**: src/zig_tooling.zig
  - **Priority**: High
  - **Created**: 2025-07-31
  - **Dependencies**: None (but related to #LC103)
  - **Details**: Memory leaks in analyzeFile() and analyzeSource() wrapper functions - they free the issue arrays but not the string fields inside each issue
  - **Requirements**:
    - Fix analyzeFile() to properly free strings in memory_result.issues before freeing the array
    - Fix analyzeFile() to properly free strings in testing_result.issues before freeing the array
    - Fix analyzeSource() with the same pattern
    - Add memory leak tests for these functions
    - Consider using the freeResult helper from patterns.zig
  - **Notes**:
    - Found during LC103 fix session when reviewing similar code patterns
    - Lines 291 and 294 in analyzeFile() only do `allocator.free(memory_result.issues)` without freeing the strings
    - Lines 334 and 337 in analyzeSource() have the same issue
    - The strings (file_path, message, suggestion) were duplicated in analyzeMemory/analyzeTests and need to be freed

---

- [ ] #LC108: Add public freeAnalysisResult() helper function
  - **Component**: src/zig_tooling.zig, src/utils.zig
  - **Priority**: Medium
  - **Created**: 2025-07-31
  - **Dependencies**: None
  - **Details**: Library lacks a public helper function to properly free AnalysisResult structures
  - **Requirements**:
    - Create public freeAnalysisResult() function that frees all issue strings and the issues array
    - Add to main zig_tooling.zig exports or utils.zig
    - Document memory ownership clearly
    - Update examples to use this helper
    - Consider also adding freeIssue() for single issues
  - **Notes**:
    - Currently users must manually iterate and free each field
    - test_memory_leaks.zig has a private version at line 144 that could be adapted
    - patterns.zig has freeResult() at line 263 that could be moved to main library
    - Would prevent memory leaks and improve API usability

---

- [ ] #LC063: Improve API documentation coverage
  - **Component**: All public modules, especially src/zig_tooling.zig
  - **Priority**: Medium
  - **Created**: 2025-07-27
  - **Dependencies**: #LC021 ✅ (Completed 2025-07-27)
  - **Details**: API documentation coverage is only 49% (82/166 public items)
  - **Requirements**:
    - Add documentation to missing public APIs in src/zig_tooling.zig (4/35 documented)
    - Improve coverage in src/types.zig (12/16 documented) 
    - Add missing documentation in other modules with gaps
    - Target minimum 90% documentation coverage
    - Focus on main entry point APIs first
  - **Notes**:
    - Discovered during LC021 API completeness audit
    - Current coverage by file: zig_tooling.zig (11%), types.zig (75%), memory_analyzer.zig (54%), testing_analyzer.zig (21%), scope_tracker.zig (73%), patterns.zig (44%), formatters.zig (58%), build_integration.zig (80%)
    - Critical for user adoption and library usability

---

- [ ] #LC039: Complete output formatter implementations
  - **Component**: src/build_integration.zig
  - **Priority**: Medium
  - **Created**: 2025-07-27
  - **Dependencies**: #LC013 ✅, #LC015 (when completed)
  - **Details**: JSON and GitHub Actions formatters are placeholder implementations
  - **Requirements**:
    - Implement printJsonResults() function for structured JSON output
    - Implement printGitHubActionsResults() for GitHub annotations format
    - Add tests for all output formats
    - Document format specifications
  - **Notes**:
    - Functions at [src/build_integration.zig:694-700](src/build_integration.zig#L694-L700) are placeholders
    - Should coordinate with LC015 formatter work to avoid duplication
    - Discovered during LC013 implementation

---

- [ ] #LC043: Add parallel file analysis support
  - **Component**: src/build_integration.zig, src/types.zig
  - **Priority**: Medium
  - **Created**: 2025-07-27
  - **Dependencies**: #LC013 ✅, #LC015 (AnalysisOptions implementation)
  - **Details**: AnalysisOptions.parallel field exists but not implemented
  - **Requirements**:
    - Implement concurrent file analysis in analyzePattern functions
    - Add thread pool for file processing
    - Ensure thread-safe result aggregation
    - Add configuration for thread count
  - **Notes**:
    - AnalysisOptions.parallel at [src/types.zig:171](src/types.zig#L171) is defined but unused
    - Would improve analysis performance for large codebases
    - Need to consider memory usage with parallel processing
    - Discovered during LC013 implementation

---


- [ ] #LC038: Implement proper glob pattern library for build integration
  - **Component**: src/build_integration.zig
  - **Priority**: Medium
  - **Created**: 2025-07-27
  - **Dependencies**: #LC013 ✅ (Completed 2025-07-27)
  - **Details**: Current glob pattern matching is basic and limited
  - **Requirements**:
    - Replace basic pattern matching with proper glob library
    - Support complex patterns like "src/**/test_*.zig" 
    - Add pattern validation and error handling
    - Add tests for glob pattern edge cases
  - **Notes**:
    - Current matchesPattern() at [src/build_integration.zig:634-652](src/build_integration.zig#L634-L652) only handles simple cases
    - Could use std.glob when available or implement more complete matching
    - Discovered during LC013 implementation

---

- [ ] #LC075: Document dogfooding patterns for library developers
  - **Component**: Documentation, CLAUDE.md, examples/advanced/
  - **Priority**: Low
  - **Created**: 2025-07-29
  - **Dependencies**: None
  - **Details**: Document the dogfooding pattern implemented for using zig-tooling on itself
  - **Requirements**:
    - Document the `zig build dogfood` pattern for non-blocking quality checks
    - Add example of .gitignore entries for local development artifacts
    - Document the workflow: develop → dogfood → fix critical issues → release
    - Add section to CLAUDE.md about self-analysis patterns
  - **Notes**:
    - Successfully implemented dogfooding with quality check tool during LC064
    - Pattern: `zig build dogfood > dogfood-$(date +%Y%m%d).txt 2>&1`
    - Keeps development artifacts separate from git commits
    - Would help other library developers adopt similar patterns

---

- [ ] #LC077: Systematically address self-analysis quality findings
  - **Component**: All source files
  - **Priority**: Low
  - **Created**: 2025-07-29
  - **Dependencies**: #LC075 (dogfooding documentation)
  - **Details**: Self-analysis found 71 errors and 176 warnings that could be systematically addressed
  - **Requirements**:
    - Create systematic approach to address memory safety warnings
    - Fix test naming convention issues (found 40+ non-compliant tests)
    - Address missing test coverage warnings
    - Document decision criteria for which issues to fix vs. accept
  - **Notes**:
    - Found via `zig build dogfood` - tool analyzed 47 files in 2.4s
    - Most issues are legitimate and fixable
    - Would improve library code quality and demonstrate tool effectiveness
    - Not critical for users but good for library maintenance

---

- [ ] #LC109: Extract duplicate issue copying logic to helper function
  - **Component**: src/zig_tooling.zig
  - **Priority**: Low
  - **Created**: 2025-07-31
  - **Dependencies**: None
  - **Details**: Code duplication in analyzeMemory() and analyzeTests() for copying issues from analyzer results
  - **Requirements**:
    - Create helper function like `copyIssues(allocator: Allocator, analyzer_issues: []const Issue) ![]Issue`
    - Replace duplicate code in analyzeMemory() (lines 140-150)
    - Replace duplicate code in analyzeTests() (lines 216-227)
    - Add proper error handling with errdefer cleanup
    - Consider making it public if useful for users
  - **Notes**:
    - Both functions have identical logic for duplicating issue strings
    - Would reduce code duplication and potential for bugs
    - Makes maintenance easier if issue copying logic needs to change

---

- [ ] #LC110: Improve error handling specificity in wrapper functions
  - **Component**: src/zig_tooling.zig
  - **Priority**: Low
  - **Created**: 2025-07-31
  - **Dependencies**: None
  - **Details**: Wrapper functions lose error information by converting specific errors to generic ones
  - **Requirements**:
    - Review error conversions in analyzeMemory, analyzeTests, analyzeFile
    - Add more specific error types to AnalysisError enum if needed
    - Preserve original error information where possible
    - Consider adding error context or wrapping errors
    - Document which specific errors can occur for each function
  - **Notes**:
    - analyzeMemory/analyzeTests convert all non-OutOfMemory errors to ParseError (lines 122-124, 200-202)
    - analyzeFile converts many file errors to generic FileReadError
    - Makes debugging harder when specific error information is lost
    - Consider pattern like `error.InvalidSyntax => return AnalysisError.InvalidSyntax`

---

- [ ] #LC070: Add compile-time validation for default allocator patterns
  - **Component**: src/memory_analyzer.zig, build.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: None
  - **Details**: Default patterns are validated at runtime but could have compile-time checks
  - **Requirements**:
    - Add build-time validation to ensure no duplicate names in default_allocator_patterns
    - Consider using comptime validation in Zig
    - Ensure patterns are non-empty and valid
    - Fail build if default patterns have issues
  - **Notes**:
    - Discovered during LC069 when we added runtime validation
    - Runtime check at [src/memory_analyzer.zig:879-917](src/memory_analyzer.zig#L879-L917)
    - Would catch library bugs during development rather than at runtime
    - Could use comptime asserts or build script validation

---

---

- [ ] #LC087: Implement ownership transfer detection for return values
  - **Component**: src/memory_analyzer.zig
  - **Priority**: High
  - **Created**: 2025-07-30
  - **Dependencies**: #LC081 (parent task)
  - **Details**: Detect when allocated memory is returned to caller, indicating ownership transfer
  - **Requirements**:
    - Analyze function return statements to detect returned allocations
    - Track data flow from allocation to return statement
    - Mark allocations that are returned as "ownership transferred"
    - Skip defer requirement checks for transferred allocations
  - **Notes**:
    - Would fix false positives like src/zig_tooling.zig:125
    - Should handle both direct returns and values stored in returned structures
    - Consider return type analysis to understand ownership semantics

---

- [ ] #LC088: Add data flow analysis for structured returns
  - **Component**: src/memory_analyzer.zig
  - **Priority**: High
  - **Created**: 2025-07-30
  - **Dependencies**: #LC081 (parent task), #LC087
  - **Details**: Track allocations that are stored in structures that are then returned
  - **Requirements**:
    - Implement field assignment tracking for struct types
    - Detect when allocated values are assigned to struct fields
    - Track when those structs are returned from functions
    - Mark contained allocations as transferred ownership
  - **Notes**:
    - Handles complex cases like returning Result structs with allocated fields
    - Should work with nested structures and arrays
    - Critical for reducing false positives in real-world code

---

- [ ] #LC089: Create allowed allocator pattern database
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Priority**: Medium
  - **Created**: 2025-07-30
  - **Dependencies**: #LC081 (parent task)
  - **Details**: Build comprehensive database of common allocator patterns and parameter names
  - **Requirements**:
    - Research common allocator parameter naming patterns in Zig ecosystem
    - Create configurable database of allowed patterns
    - Include patterns like "allocator", "alloc", "arena", "gpa", etc.
    - Support wildcards and regex patterns for flexibility
  - **Notes**:
    - Should include build system allocator patterns
    - Consider per-project customization options
    - Default patterns should cover 90%+ of valid use cases

---

- [ ] #LC090: Implement scope-aware defer analysis
  - **Component**: src/memory_analyzer.zig, src/scope_tracker.zig
  - **Priority**: Medium
  - **Created**: 2025-07-30
  - **Dependencies**: #LC081 (parent task)
  - **Details**: Improve defer requirement detection based on allocation scope and lifetime
  - **Requirements**:
    - Integrate with ScopeTracker for better scope understanding
    - Detect allocations that escape their creation scope
    - Only require defer for allocations consumed within same scope
    - Handle loop scopes and conditional scopes correctly
  - **Notes**:
    - Should reduce false positives for allocations with complex lifetimes
    - Consider errdefer patterns and cleanup requirements
    - Must handle nested scopes and early returns

---

- [ ] #LC091: Add allocation intent inference
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Medium
  - **Created**: 2025-07-30
  - **Dependencies**: #LC081 (parent task)
  - **Details**: Infer allocation intent from usage patterns to reduce false positives
  - **Requirements**:
    - Analyze how allocated memory is used after creation
    - Detect patterns like "create and return" vs "temporary usage"
    - Infer ownership model from surrounding code patterns
    - Use inference to guide defer requirement decisions
  - **Notes**:
    - Could use heuristics like "allocated in init() = long-lived"
    - Should handle factory patterns and builder patterns
    - Balance between accuracy and analysis performance

---

- [ ] #LC092: Create configuration system for quality checks
  - **Component**: tools/quality_check.zig, src/types.zig
  - **Priority**: Medium
  - **Created**: 2025-07-30
  - **Dependencies**: #LC081 (parent task)
  - **Details**: Add configuration file support for customizing quality check behavior
  - **Requirements**:
    - Design configuration file format (JSON or custom)
    - Add config loading to quality_check tool
    - Support disabling specific check categories
    - Allow project-specific allocator patterns and rules
  - **Notes**:
    - Could use .zig-tooling.json or similar
    - Should support inheritance from default config
    - Enable teams to customize for their coding standards

---

- [ ] #LC093: Implement incremental false positive reduction
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Medium
  - **Created**: 2025-07-30
  - **Dependencies**: #LC081 (parent task)
  - **Details**: Add machine learning or pattern-based system to learn from false positive reports
  - **Requirements**:
    - Create feedback mechanism for marking false positives
    - Build pattern database from reported false positives
    - Use patterns to refine future analysis
    - Provide reporting mechanism for users
  - **Notes**:
    - Could start with simple pattern matching
    - Consider storing patterns in project metadata
    - Long-term: could use ML for pattern recognition

---

- [ ] #LC094: Add semantic analysis for build system patterns
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-30
  - **Dependencies**: #LC081 (parent task)
  - **Details**: Special handling for Zig build system allocation patterns
  - **Requirements**:
    - Detect when code is part of build.zig or build system
    - Apply different rules for build-time allocations
    - Understand build.zig allocation lifecycle
    - Handle build step allocations appropriately
  - **Notes**:
    - Build system has different allocation patterns than runtime code
    - Should fix false positives like src/build_integration.zig:356
    - Consider build-specific allocator types

---

- [ ] #LC095: Create comprehensive test suite for false positive scenarios
  - **Component**: tests/test_memory_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-30
  - **Dependencies**: #LC081 (parent task), #LC086-#LC094
  - **Details**: Build extensive test suite covering all false positive scenarios
  - **Requirements**:
    - Create test cases for each type of false positive
    - Test parameter allocators, ownership transfers, build patterns
    - Include regression tests for fixed issues
    - Measure false positive rate improvements
  - **Notes**:
    - Should have before/after metrics for each improvement
    - Include real-world code examples from reported issues
    - Use as validation for all analyzer improvements

---

- [ ] #LC049: Add static analysis for recursive function call and use-after-free detection
  - **Component**: Static analysis tooling, CI/CD configuration
  - **Priority**: Medium
  - **Created**: 2025-07-27
  - **Updated**: 2025-07-28 (added use-after-free patterns from LC073)
  - **Dependencies**: None
  - **Details**: Critical bugs not caught by static analysis or testing including recursive calls and use-after-free
  - **Requirements**:
    - Implement static analysis rules to detect recursive function calls within the same method
    - Add use-after-free pattern detection for HashMap ownership issues
    - Add CI/CD step to run pattern detection
    - Create custom linter rules or use existing tools (rg, ast-grep, etc.)
    - Add tests to verify pattern detection works correctly
  - **Notes**:
    - **Critical Bug Found**: During LC015 implementation, discovered recursive bugs in both analyzers' `addIssue()` methods
    - **Location**: [src/memory_analyzer.zig:1407](src/memory_analyzer.zig#L1407) and [src/testing_analyzer.zig:780](src/testing_analyzer.zig#L780)
    - **Bug Pattern**: Methods calling `try self.addIssue(issue);` instead of `try self.issues.append(enhanced_issue);`
    - **Impact**: Would cause stack overflow crashes in production with infinite recursion
    - **Prevention**: Static analysis could catch patterns like `self.methodName()` within the same method definition
    - **Tools**: Could use `rg "fn (\w+).*self\.\1\("` or similar patterns to detect
    - Discovered during LC015 implementation - represents critical gap in our quality assurance
    - **Additional Pattern from LC056**: Should also detect inconsistent memory management patterns:
      - Mixing string literals with heap-allocated strings in the same field type
      - Pattern to detect: fields that are sometimes assigned literals (`= "..."`) and sometimes allocPrint
      - Example regex: `\.(field_name)\s*=\s*"[^"]*"` vs `\.(field_name)\s*=\s*try.*allocPrint`
      - Would have caught the LC056 segfault issue before production
    - **Use-After-Free Pattern from LC073**: Should detect HashMap ownership issues:
      - **Bug Found**: During LC073, discovered use-after-free bug in validateAllocatorChoice()
      - **Location**: [src/memory_analyzer.zig:794](src/memory_analyzer.zig#L794)
      - **Bug Pattern**: String freed with `defer` while still referenced in HashMap - caused segfaults with GPA
      - **Detection Patterns Needed**:
        - Variables freed with `defer` inside loops but used after the defer
        - HashMap put() calls where the key is freed in the same scope
        - Pattern: `defer allocator.free(var); ... map.put(var, ...)`
        - Specific regex: `defer\s+\w+\.free\((\w+)\).*\.put\(\1,`
      - **Example Anti-Pattern**:
        ```zig
        const key = try allocator.dupe(u8, some_string);
        defer allocator.free(key);  // BUG: key freed while still in HashMap
        try hashmap.put(key, value);
        ```
      - Would have prevented segfaults reported in GitHub Issue #4

---

- [ ] #LC048: Enhance error boundary testing framework
  - **Component**: tests/, src/patterns.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC019 ✅
  - **Details**: Error handling gaps found during implementation not systematically tested
  - **Requirements**:
    - Add comprehensive error injection testing framework
    - Create systematic error boundary test cases
    - Add filesystem error simulation utilities
    - Implement error path coverage validation
  - **Notes**:
    - Discovered during LC019 when walkProjectDirectory() error handling was incomplete
    - Fixed at [src/patterns.zig:132-137](src/patterns.zig#L132-L137) with proper error conversion
    - Would catch error handling gaps before production
    - Discovered during LC019 implementation
    - **Memory Management Testing from LC056**: Should include specific tests for:
      - Consistent memory allocation patterns (all heap or all stack for same field type)
      - Proper cleanup in deinit() functions with various allocation patterns
      - Test pattern: Create analyzer → Add issues with mixed allocation types → Call deinit()
      - Test case from LC056: [src/memory_analyzer.zig:1557-1583](src/memory_analyzer.zig#L1557-L1583)
      - Edge cases: optional fields with null, empty strings, very long strings
      - Would have caught the segfault during testing phase

---

- [ ] #LC037: Document logger lifecycle and memory safety
  - **Component**: src/app_logger.zig, CLAUDE.md
  - **Priority**: Medium
  - **Created**: 2025-07-27
  - **Dependencies**: #LC012 ✅
  - **Details**: Logger holds reference to LoggingConfig but no lifetime guarantees
  - **Requirements**:
    - Document that LoggingConfig must outlive Logger instances
    - Add warning about callback lifetime requirements
    - Consider adding config ownership option
    - Add examples showing proper lifecycle management
  - **Notes**:
    - Logger stores config reference at src/app_logger.zig:105
    - No mechanism to ensure config outlives logger
    - Could lead to use-after-free if misused
    - Discovered during LC012 implementation
    - **String Lifetime Lessons from LC056**: Documentation should explicitly cover:
      - String field ownership patterns: "All string fields must be either all heap-allocated or all literals"
      - Never mix allocation strategies for the same field across different code paths
      - Example anti-pattern from LC056: `.suggestion` was sometimes literal, sometimes allocPrint
      - Document in Issue struct: "All optional string fields MUST be heap-allocated if non-null"
      - Add code example showing correct pattern:
        ```zig
        // WRONG: Mixing allocation types
        .suggestion = if (simple) "Use defer" else try allocPrint(...);
        
        // RIGHT: Consistent allocation
        .suggestion = try allocPrint(allocator, "{s}", .{
            if (simple) "Use defer" else complex_message
        });
        ```
      - Critical for preventing segfaults in cleanup code

---

- [ ] #LC058: Add memory ownership tracking type system
  - **Component**: src/types.zig, src/utils.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: None
  - **Details**: String fields can be either heap-allocated or literals, causing memory management bugs
  - **Requirements**:
    - Create a tagged union type that tracks whether a string is owned or borrowed
    - Add helper functions for safe string assignment and cleanup
    - Update Issue struct to use ownership-aware string type
    - Provide migration path for existing code
  - **Notes**:
    - Would prevent issues like LC056 and LC057 at compile time
    - Could use something like: `const OwnedString = union(enum) { owned: []const u8, borrowed: []const u8 };`
    - Would make memory ownership explicit in the type system
    - Discovered during LC057 resolution - pattern of mixing literals with heap strings is error-prone

---

- [ ] #LC046: Add systematic Zig version compatibility testing
  - **Component**: build.zig, tests/, CI configuration
  - **Priority**: Low
  - **Created**: 2025-07-27  
  - **Dependencies**: #LC019 ✅
  - **Details**: Compatibility issues with Zig versions not caught until runtime
  - **Requirements**:
    - Add automated testing against multiple Zig versions
    - Create compatibility test matrix for CI
    - Add version-specific compatibility documentation
    - Implement early detection of breaking API changes
  - **Notes**:
    - Discovered during LC019 when tmpDir const qualifier failed with Zig 0.14.1
    - Fixed at [tests/test_patterns.zig:103](tests/test_patterns.zig#L103) - changed const to var
    - Would prevent compatibility regressions in future
    - Discovered during LC019 implementation

---

- [ ] #LC047: Add build configuration validation
  - **Component**: build.zig, tests/
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC019 ✅
  - **Details**: Missing test files in build configuration not automatically detected
  - **Requirements**:
    - Add build step to validate all test files are included
    - Create script to detect orphaned test files
    - Add build configuration completeness check
    - Integrate validation into CI pipeline
  - **Notes**:
    - Discovered during LC019 when test_patterns.zig was missing from build.zig
    - Fixed at [build.zig:39-45](build.zig#L39-L45) by adding missing test configuration
    - Would prevent test files from being accidentally excluded
    - Discovered during LC019 implementation

---

- [ ] #LC067: Create API migration detection tooling
  - **Component**: Development tooling, tests/
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: None
  - **Details**: API changes in library aren't automatically detected in test code
  - **Requirements**:
    - Create tool to detect API drift between src/ and tests/
    - Check for deprecated function signatures (like writeFile changes)
    - Verify enum field references match actual definitions
    - Generate migration guide for API changes
  - **Notes**:
    - Would have prevented issues like writeFile(path, content) → writeFile(.{.sub_path=, .data=})
    - Would catch enum field renames (.allocator_usage → .allocator_mismatch)
    - Could be integrated into build process or CI
    - Discovered during LC062 when fixing numerous API mismatches


---

- [ ] #LC079: Make quality checks required in CI
  - **Component**: .github/workflows/ci.yml
  - **Priority**: Low
  - **Created**: 2025-07-29
  - **Dependencies**: #LC078 (must be completed first)
  - **Details**: Quality check job in CI currently has continue-on-error: true, making it non-blocking
  - **Requirements**:
    - Remove continue-on-error: true from quality-check job in CI workflow
    - Ensure quality checks block PR merges when they fail
    - Update all-checks job to include quality-check in required checks
    - Consider adding quality check status badge to README
  - **Notes**:
    - Currently the quality-check job at [.github/workflows/ci.yml:75-88](/.github/workflows/ci.yml#L75-L88) is informational only
    - Should only be made required after LC078 is resolved (fixing all quality issues)
    - Will enforce code quality standards on all contributions
    - Discovered during LC076 implementation

---

- [ ] #LC081: Fix false positives in quality analyzer allocator detection
  - **Component**: src/memory_analyzer.zig, tools/quality_check.zig
  - **Priority**: High
  - **Created**: 2025-07-30
  - **Dependencies**: #LC078 (related)
  - **Implementation subtasks**: #LC086-#LC095 (10 subtasks)
  - **Details**: The quality analyzer reports many false positives for allocator usage and memory management patterns
  - **Requirements**:
    - Fix "parameter_allocator" false positives - allocator parameters in functions are perfectly valid
    - Fix false positives for allocations returned to caller (ownership transfer)
    - Fix false positives for allocations stored in returned structures
    - Consider context when detecting missing defer statements
    - Update default allowed allocators to include common parameter patterns
  - **Notes**:
    - Currently reports warnings for valid code like: "Allocator type 'parameter_allocator' is not in the allowed list"
    - Example false positives:
      - src/zig_tooling.zig:125 - Issues array is returned to caller, no defer needed
      - src/patterns.zig:158 - String duplicated for failed_files array, freed later
      - src/build_integration.zig:356 - Build system allocator usage is valid
    - These false positives make it harder to identify real issues
    - Should differentiate between function parameters and actual allocator types
    - File links for reference:
      - Quality check configuration: [tools/quality_check.zig:71-76](tools/quality_check.zig#L71-L76)
      - Memory analyzer patterns: [src/memory_analyzer.zig:59-67](src/memory_analyzer.zig#L59-L67)
      - Example false positive: [src/zig_tooling.zig:125-149](src/zig_tooling.zig#L125-L149)

---

- [ ] #LC080: Integration tests should respect resource constraint environment variables
  - **Component**: tests/integration/, CI configuration
  - **Priority**: Medium
  - **Created**: 2025-07-29
  - **Dependencies**: #LC060 ✅ (Completed 2025-07-29)
  - **Details**: Environment variables defined in CI are not used by integration tests
  - **Requirements**:
    - Update test_memory_performance.zig to read and respect ZTOOL_TEST_MAX_MEMORY_MB
    - Update test_thread_safety.zig to read and respect ZTOOL_TEST_MAX_THREADS
    - Add helper functions in test_integration_runner.zig to parse environment variables
    - Provide sensible defaults when environment variables are not set
  - **Notes**:
    - CI defines ZTOOL_TEST_MAX_MEMORY_MB=3072 and ZTOOL_TEST_MAX_THREADS=4
    - Tests currently hardcode their resource usage instead of respecting these limits
    - Would make tests more predictable and prevent exceeding container limits
    - Example locations: [tests/integration/test_memory_performance.zig:254-259](tests/integration/test_memory_performance.zig#L254-L259) allocates 10MB buffers without checking limits
    - Thread safety tests at [tests/integration/test_thread_safety.zig:319](tests/integration/test_thread_safety.zig#L319) hardcode 4 threads
    - Discovered during LC060 implementation

---

- [ ] #LC053: Review and fix reserved keyword conflicts in public APIs
  - **Component**: src/types.zig, all public modules
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: None
  - **Details**: Some enum fields use reserved keywords requiring escape syntax
  - **Requirements**:
    - Audit all public types for reserved keyword usage
    - Rename conflicting fields to avoid escape syntax
    - Maintain backward compatibility or provide migration path
    - Document any breaking changes
  - **Notes**:
    - Found `error` field requiring `@"error"` escape in [examples/ide_integration.zig:48](examples/ide_integration.zig#L48)
    - Makes API less ergonomic for users
    - Could affect other language bindings
    - Discovered during LC017 implementation

---

- [ ] #LC054: Add string manipulation utilities
  - **Component**: src/utils.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: None
  - **Details**: Common string operations needed for custom analyzers
  - **Requirements**:
    - Add case conversion functions (snake_case, camelCase, PascalCase)
    - Add string escaping utilities
    - Add pattern matching helpers
    - Make them public APIs in utils module
    - Add comprehensive tests
  - **Notes**:
    - Had to implement `toCamelCase` in [examples/custom_analyzer.zig:295-310](examples/custom_analyzer.zig#L295-L310)
    - Common need when building custom analyzers
    - Would improve library usability
    - Discovered during LC017 implementation

---

- [ ] #LC055: Add additional issue types for custom analyzers
  - **Component**: src/types.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: None
  - **Details**: Limited issue types for custom analysis rules
  - **Requirements**:
    - Add .complexity issue type for cyclomatic complexity
    - Add .style issue type for style violations
    - Add .documentation issue type for missing docs
    - Add .performance issue type for performance concerns
    - Consider making issue types extensible
  - **Notes**:
    - Custom analyzer example had to use generic types
    - See usage in [examples/custom_analyzer.zig](examples/custom_analyzer.zig)
    - Would better categorize custom analysis results
    - Discovered during LC017 implementation

---

- [ ] #LC065: Document thread array mutability patterns for concurrent tests
  - **Component**: Documentation, tests/integration/
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: None
  - **Details**: Zig's array mutability rules for concurrent code are confusing and caused multiple errors
  - **Requirements**:
    - Add documentation explaining when to use `var` vs `const` for thread arrays
    - Document the pattern: `var threads: [N]std.Thread` even though array isn't reassigned
    - Add examples showing proper concurrent test patterns
    - Consider adding helper functions to simplify thread management
  - **Notes**:
    - Discovered during LC062 - had to fix this pattern in 6 different test files
    - Zig requires `var` for arrays where elements will be mutated via `thread.* = spawn()`
    - Common source of confusion for developers writing concurrent tests
    - See fixes in [tests/integration/test_thread_safety.zig](tests/integration/test_thread_safety.zig)

---

- [ ] #LC061: Clean up integration test runner unused imports
  - **Component**: tests/integration/test_integration_runner.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC020 ✅ (Completed 2025-07-27)
  - **Details**: Integration test runner imports sub-modules but doesn't use them
  - **Requirements**:
    - Remove unused imports from test_integration_runner.zig
    - Or implement proper orchestration of sub-test modules
    - Clean up test runner organization
    - Ensure consistent test execution patterns
  - **Notes**:
    - test_integration_runner.zig at [tests/integration/test_integration_runner.zig:10-14](tests/integration/test_integration_runner.zig#L10-L14) imports modules but doesn't use them
    - Current design has each test module run independently
    - Could either remove imports or implement proper test orchestration
    - Minor technical debt from LC020 implementation
    - Discovered during LC020 implementation

---

- [ ] #LC074: Document GitHub codeload URL requirement for build.zig.zon
  - **Component**: Documentation, README.md, CLAUDE.md
  - **Priority**: Low
  - **Created**: 2025-07-29
  - **Dependencies**: None
  - **Details**: Users encounter 503 errors with standard GitHub archive URLs and must use codeload.github.com
  - **Requirements**:
    - Add documentation explaining when to use codeload.github.com URLs
    - Provide example showing the URL format difference
    - Explain that this is due to GitHub's infrastructure, not the library
    - Add troubleshooting section for common integration issues
  - **Notes**:
    - Standard format: `https://github.com/user/repo/archive/refs/tags/v1.0.0.tar.gz`
    - Working format: `https://codeload.github.com/user/repo/tar.gz/refs/tags/v1.0.0`
    - This affects users trying to add the library as a dependency
    - Discovered during user integration attempts

---

- [ ] #LC031: Add pattern conflict detection
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC028 ✅
  - **Details**: Patterns that overlap can cause unexpected matches
  - **Requirements**:
    - Detect when patterns could match the same string (e.g., "alloc" and "allocator")
    - Warn about overlapping patterns during validation
    - Consider pattern specificity ordering
    - Add tests for conflict scenarios
  - **Notes**:
    - validateAllocatorPatterns() at src/memory_analyzer.zig:733-799
    - Currently only checks for duplicate names, not pattern overlap
    - Example: pattern "alloc" would match before "allocator" in "my_allocator_var"
    - Discovered during LC028 implementation

---

- [ ] #LC033: Add pattern testing utilities
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC024 ✅
  - **Details**: No way to test patterns before using them
  - **Requirements**:
    - Add public testPattern() function to test a pattern against sample strings
    - Add public testAllPatterns() to test all configured patterns
    - Return which pattern matched and the extracted allocator type
    - Useful for debugging pattern configuration
  - **Notes**:
    - Would help users debug why patterns aren't matching as expected
    - Could be exposed as MemoryAnalyzer.testPattern(pattern, test_string)
    - extractAllocatorType() logic at src/memory_analyzer.zig:675-697
    - Discovered during LC028 implementation

---

- [ ] #LC071: Add ownership pattern testing utilities
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC068 ✅
  - **Details**: No way to test ownership patterns before using them (similar to LC033 for allocator patterns)
  - **Requirements**:
    - Add public testOwnershipPattern() function to test patterns against sample function signatures
    - Test both function name and return type patterns
    - Show which pattern matched and why
    - Useful for debugging ownership transfer detection
  - **Notes**:
    - Would help users understand why functions are/aren't detected as ownership transfers
    - Similar need as allocator pattern testing (LC033)
    - Discovered during LC068 implementation

---

- [ ] #LC029: Implement regex support for allocator patterns
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC024 ✅
  - **Details**: AllocatorPattern.is_regex field exists but is not implemented
  - **Requirements**:
    - Implement regex matching when is_regex is true
    - Add regex compilation and caching
    - Handle regex errors gracefully
    - Add tests for regex patterns
  - **Notes**:
    - AllocatorPattern struct at src/types.zig:119-129 has is_regex field
    - extractAllocatorType() at src/memory_analyzer.zig:670-692 only does substring matching
    - Would allow more precise pattern matching (e.g., "^my_.*_allocator$")
    - Discovered during LC024 implementation

---

- [ ] #LC032: Add case-insensitive pattern matching option
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC024 ✅
  - **Details**: Pattern matching is currently case-sensitive only
  - **Requirements**:
    - Add case_sensitive boolean to AllocatorPattern struct (default true)
    - Use case-insensitive matching when flag is false
    - Update extractAllocatorType() to handle case sensitivity
    - Add tests for case-insensitive patterns
  - **Notes**:
    - extractAllocatorType() at src/memory_analyzer.zig:675-697 uses std.mem.indexOf
    - Would need to use std.ascii.indexOfIgnoreCase or similar
    - Some projects may have inconsistent allocator naming conventions
    - Discovered during LC028 implementation

---

- [ ] #LC044: Extract shared glob pattern matching utility
  - **Component**: src/utils.zig, src/patterns.zig, src/build_integration.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC014 ✅
  - **Details**: Duplicate matchesPattern() functions in patterns.zig and build_integration.zig
  - **Requirements**:
    - Create shared pattern matching utility in src/utils.zig
    - Update both patterns.zig and build_integration.zig to use shared function
    - Consolidate pattern matching logic to avoid code duplication
    - Add tests for shared utility
  - **Notes**:
    - matchesPattern() at [src/patterns.zig:350-370](src/patterns.zig#L350-L370) duplicates [src/build_integration.zig:647-665](src/build_integration.zig#L647-L665)
    - Both functions implement the same basic glob pattern matching
    - Discovered during LC014 implementation

---

- [ ] #LC045: Add test utilities for temporary directory setup
  - **Component**: tests/test_utils.zig (new), tests/
  - **Priority**: Low  
  - **Created**: 2025-07-27
  - **Dependencies**: #LC014 ✅
  - **Details**: Test setup for temporary directories is verbose and duplicated
  - **Requirements**:
    - Create test utilities for easier temporary directory and file setup
    - Add helpers for creating test project structures
    - Simplify test code in test_patterns.zig and other test files
    - Add cleanup utilities for consistent test isolation
  - **Notes**:
    - Test setup in [tests/test_patterns.zig:82-109](tests/test_patterns.zig#L82-L109) is verbose and repeated
    - Similar patterns in other test files could benefit from shared utilities
    - Would improve test maintainability and readability
    - Discovered during LC014 implementation

---

- [ ] #LC041: Implement incremental analysis for build integration
  - **Component**: src/build_integration.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC013 ✅
  - **Details**: Build steps always analyze all files, no incremental support
  - **Requirements**:
    - Add option to analyze only modified files since last run
    - Integrate with git to detect changed files
    - Add timestamp-based file change detection
    - Cache analysis results for unchanged files
  - **Notes**:
    - Would significantly improve build performance for large projects
    - Could integrate with Zig's build cache system
    - Discovered during LC013 implementation

---

- [ ] #LC042: Complete pre-commit hook implementations
  - **Component**: src/build_integration.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC013 ✅
  - **Details**: Only bash pre-commit hooks are fully implemented
  - **Requirements**:
    - Implement createFishPreCommitHook() with proper Fish shell syntax
    - Implement createPowerShellPreCommitHook() for Windows environments
    - Add tests for all hook types
    - Document hook installation procedures
  - **Notes**:
    - Functions at [src/build_integration.zig:762-769](src/build_integration.zig#L762-L769) are placeholders
    - Should follow shell-specific best practices
    - Discovered during LC013 implementation

---

- [ ] #LC034: Improve logging callback pattern for stateful collectors
  - **Component**: src/app_logger.zig, src/types.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC012 ✅
  - **Details**: Current callback pattern doesn't work well with stateful log collectors
  - **Requirements**:
    - Consider alternative callback patterns that support closures or context pointers
    - Update LogCallback type definition to support context parameter
    - Maintain backward compatibility or provide migration path
    - Add examples of stateful collectors
  - **Notes**:
    - Current pattern: `*const fn (event: LogEvent) void`
    - Tests had to use global variables instead of proper closures (test_api.zig:1104-1157)
    - MemoryLogCollector example has incomplete implementation
    - Discovered during LC012 implementation

---

- [ ] #LC035: Add log filtering by category
  - **Component**: src/app_logger.zig, src/types.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC012 ✅
  - **Details**: Can only filter by log level, not by category
  - **Requirements**:
    - Add category_filter field to LoggingConfig (optional string array)
    - Update Logger.shouldLog() to check category filter
    - Support include/exclude patterns
    - Add tests for category filtering
  - **Notes**:
    - Users might want only "memory_analyzer" logs, not "testing_analyzer"
    - Current filtering at src/app_logger.zig:122-125
    - Could use simple string matching or pattern matching
    - Discovered during LC012 implementation

---

- [ ] #LC036: Add structured logging format helpers
  - **Component**: src/app_logger.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC012 ✅
  - **Details**: No standardized format for structured log messages
  - **Requirements**:
    - Add format templates for common log patterns
    - Support key-value pair formatting
    - Add JSON formatter for LogEvent
    - Provide format customization options
  - **Notes**:
    - Current stderrLogCallback is basic (src/app_logger.zig:212-246)
    - Users implementing callbacks must handle all formatting
    - Could provide formatters: JSON, logfmt, human-readable
    - Discovered during LC012 implementation

---

- [ ] #LC082: Fix false positive missing test detection for inline tests
  - **Component**: src/testing_analyzer.zig, tools/quality_check.zig
  - **Priority**: Medium
  - **Created**: 2025-07-30
  - **Dependencies**: #LC078 ✅ (discovered during implementation)
  - **Details**: TestingAnalyzer incorrectly reports missing tests for files that have inline tests
  - **Requirements**:
    - Fix detection logic to properly find inline test blocks
    - Ensure analyzer recognizes tests added at the end of source files
    - Update test detection to check entire file, not just beginning
    - Add test cases to verify inline test detection works correctly
  - **Notes**:
    - Discovered during LC078 when quality check reported missing tests for:
      - [src/source_context.zig:671](src/source_context.zig#L671) - has inline test
      - [src/memory_analyzer.zig:1951](src/memory_analyzer.zig#L1951) - has inline test  
      - [src/build_integration.zig:889](src/build_integration.zig#L889) - has inline test
    - All three files have valid inline tests but are still flagged as missing tests
    - Causes confusion and reduces trust in the analyzer

---

- [ ] #LC083: Add test fixture exclusion patterns for sample projects
  - **Component**: tools/quality_check.zig, src/testing_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-30
  - **Dependencies**: None
  - **Details**: Integration test sample projects contain intentionally bad test names that show up in quality checks
  - **Requirements**:
    - Add configuration option to exclude test fixture directories
    - Default exclude pattern for `**/sample_projects/**` in quality checks
    - Document how to exclude test fixtures from analysis
    - Ensure fixtures can still be analyzed when explicitly requested
  - **Notes**:
    - Found during LC078: [tests/integration/sample_projects/complex_multi_file/tests/test_utils.zig](tests/integration/sample_projects/complex_multi_file/tests/test_utils.zig)
    - Contains intentionally bad test names like "BadTestName" to test the analyzer
    - These show up as real issues when running `zig build quality`
    - Should not count against project quality metrics

---

- [ ] #LC084: Document test naming convention requirements
  - **Component**: docs/, README.md, CLAUDE.md
  - **Priority**: Medium
  - **Created**: 2025-07-30
  - **Dependencies**: None
  - **Details**: Test naming convention requirements are not clearly documented for users
  - **Requirements**:
    - Add section to documentation explaining test naming pattern: `test "category: module: description"`
    - List allowed categories: unit, integration, e2e, performance
    - Provide examples of good and bad test names
    - Add to getting-started guide and API reference
    - Consider adding to error messages from testing analyzer
  - **Notes**:
    - During LC078, had to fix 21 test names without clear documentation
    - Pattern is enforced by quality checks but not explained to users
    - Would reduce confusion and help adoption
    - Should be prominently featured in documentation

---

- [ ] #LC096: Fix deprecated API usage throughout codebase
  - **Component**: All source files
  - **Priority**: Medium
  - **Created**: 2025-07-30
  - **Details**: During LC086, found deprecated std.mem.tokenize usage. Need systematic check for all deprecated APIs
  - **Requirements**:
    - Search for all uses of deprecated APIs (tokenize, etc.)
    - Update to use modern equivalents (tokenizeAny, tokenizeScalar, tokenizeSequence)
    - Add CI check to prevent new deprecated API usage
    - Document migration patterns for common deprecations
  - **Notes**:
    - Found at src/memory_analyzer.zig:1650 during LC086 implementation
    - Zig 0.14+ deprecated several commonly used APIs
    - Should be done before next Zig version update

---

- [ ] #LC097: Enhance function signature parsing for multi-line and complex signatures
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-30
  - **Dependencies**: #LC086 ✅ (Completed 2025-07-30)
  - **Details**: Current parseFunctionSignature is simplified and doesn't handle all cases
  - **Requirements**:
    - Support multi-line function signatures
    - Handle nested parentheses in generic parameters
    - Parse complex parameter types with nested structures
    - Handle function signatures with comptime parameters
  - **Notes**:
    - Current implementation at src/memory_analyzer.zig:1556-1672
    - Comment acknowledges limitation: "simplified - doesn't handle nested parentheses/generics"
    - Would improve accuracy of context-aware analysis

---

- [ ] #LC098: Add dedicated test file for memory analyzer
  - **Component**: tests/test_memory_analyzer.zig (new)
  - **Priority**: Low
  - **Created**: 2025-07-30
  - **Details**: Memory analyzer tests are scattered across test_api.zig making it hard to maintain
  - **Requirements**:
    - Create tests/test_memory_analyzer.zig
    - Move memory-specific tests from test_api.zig
    - Organize tests by feature (context awareness, ownership, patterns, etc.)
    - Add to build.zig test configuration
  - **Notes**:
    - test_api.zig is over 2600 lines and growing
    - LC086 added 5 more test cases to already large file
    - Better organization would improve maintainability

---


---

- [ ] #LC101: Audit documentation for Zig 0.14.1 command syntax changes
  - **Component**: CLAUDE.md, examples/README.md, docs/
  - **Priority**: Medium
  - **Created**: 2025-07-30
  - **Dependencies**: None
  - **Details**: Zig 0.14.1 changed test command syntax requiring --dep and -M flags instead of --mod
  - **Requirements**:
    - Audit all documentation files for outdated Zig test command syntax
    - Update any remaining references to old `--mod zig_tooling::src/zig_tooling.zig` syntax
    - Ensure all examples use new `--dep zig_tooling -Mroot=<test_file> -Mzig_tooling=src/zig_tooling.zig` syntax
    - Add version compatibility notes where appropriate
    - Consider documenting both old and new syntax with version requirements
  - **Notes**:
    - Already fixed in CLAUDE.md and examples/README.md during session
    - Need systematic check to ensure no other documentation has outdated syntax
    - Important for user onboarding and preventing confusion
    - Could add to getting-started documentation to prevent future issues

---


- [ ] #LC099: Improve quality check output handling for large results
  - **Component**: tools/quality_check.zig
  - **Priority**: Low
  - **Created**: 2025-07-30
  - **Details**: Quality check output gets truncated making it hard to see all issues
  - **Requirements**:
    - Add --output-file option to save full results
    - Implement pagination for terminal output
    - Add summary-only mode that shows counts by category
    - Consider JSON output for programmatic processing
  - **Notes**:
    - Current output shows "... [19490 characters truncated] ..."
    - Makes it difficult to review all issues systematically
    - Important for dogfooding and quality improvement efforts

---

- [ ] #LC085: Make example placeholder patterns configurable
  - **Component**: tests/test_example_validation.zig, examples/
  - **Priority**: Low
  - **Created**: 2025-07-30
  - **Dependencies**: #LC059 ✅ (discovered during implementation)
  - **Details**: The validation test has a hardcoded list of placeholder filenames that shouldn't be validated
  - **Requirements**:
    - Create a configuration file (e.g., `.example-placeholders`) listing valid placeholder patterns
    - Update test_example_validation.zig to read patterns from the config file
    - Document the placeholder pattern convention for example authors
    - Consider using pattern matching (e.g., "example*.zig") instead of exact matches
  - **Notes**:
    - The test at [tests/test_example_validation.zig:37-50] contains hardcoded placeholders
    - Current placeholders include: "inline_code.zig", "custom_patterns.zig", "file.zig", etc.
    - Would make it easier to maintain when adding new examples
    - Example authors would have clear documentation of allowed placeholder patterns

