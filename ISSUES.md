# Issue Tracking

> **[← Back to Issue Index](00_index.md)**

## Active Issues



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

- [ ] #LC059: Fix example file references to non-existent sample projects
  - **Component**: examples/basic_usage.zig, examples/
  - **Priority**: High
  - **Created**: 2025-07-27
  - **Dependencies**: #LC020 ✅ (Completed 2025-07-27)
  - **Details**: Example files reference deleted sample project files that no longer exist
  - **Requirements**:
    - Fix references to "examples/sample_project/memory_issues.zig" and "examples/sample_project/test_examples.zig" in basic_usage.zig
    - Either create the referenced sample files or update examples to use integration test sample projects
    - Ensure all example code actually works as demonstrated
    - Add validation to prevent future broken example references
  - **Notes**:
    - Found during LC020 integration testing implementation
    - basic_usage.zig at [examples/basic_usage.zig:36-40](examples/basic_usage.zig#L36-L40) references non-existent files
    - Examples should use the new integration test sample projects or create new minimal examples
    - Critical for user onboarding experience
    - Discovered during LC020 implementation

---

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

