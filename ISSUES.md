# Issue Tracking - Library Conversion

## 🚨 Critical Issues

*Issues that block core functionality or development*

## 🔧 In Progress

*Currently being worked on*

## 🐛 Newly Discovered Issues

*Issues found during implementation that need to be addressed*


- [ ] #LC029: Implement regex support for allocator patterns
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC024
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

- [ ] #LC030: Add option to disable default allocator patterns
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC024
  - **Details**: No way to use only custom patterns without default patterns
  - **Requirements**:
    - Add use_default_patterns boolean to MemoryConfig
    - Skip default pattern matching when disabled
    - Document the behavior clearly
    - Add tests for pattern exclusivity
  - **Notes**:
    - default_allocator_patterns at src/memory_analyzer.zig:39-47
    - extractAllocatorType() always checks defaults at src/memory_analyzer.zig:684-688
    - Users might want complete control over pattern matching
    - Discovered during LC024 implementation

- [ ] #LC031: Add pattern conflict detection
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC028
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

- [ ] #LC032: Add case-insensitive pattern matching option
  - **Component**: src/memory_analyzer.zig, src/types.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC024
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

- [ ] #LC033: Add pattern testing utilities
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Dependencies**: #LC024
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

## 📋 Backlog

*Library conversion work organized by phase*

### Phase 1: Project Restructuring

### Phase 2: API Design and Refactoring


### Phase 3: Core Component Updates

- [ ] #LC011: Optimize scope tracker
  - **Component**: src/scope_tracker.zig
  - **Priority**: Medium
  - **Created**: 2025-07-25
  - **Dependencies**: #LC008
  - **Details**: Expose as public API, add builder pattern
  - **Requirements**:
    - Public API exposure
    - Builder pattern
    - Performance optimization
    - API documentation

- [ ] #LC012: Simplify logging system
  - **Component**: src/app_logger.zig
  - **Priority**: Low
  - **Created**: 2025-07-25
  - **Dependencies**: #LC008
  - **Details**: Make logging optional with callback interface
  - **Requirements**:
    - Optional logging
    - Callback interface
    - Remove file rotation
    - Structured events
  - **Notes**:
    - File is now at src/app_logger.zig (not src/logging/)
    - Exported via zig_tooling.zig but not integrated with Config
    - Still has file-based logging with rotation

### Phase 4: Integration Helpers

- [ ] #LC013: Build system integration helpers
  - **Component**: src/build_integration.zig (new)
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Dependencies**: #LC009, #LC010
  - **Details**: Create helpers for Zig build system integration
  - **Requirements**:
    - addMemoryCheckStep function
    - addTestComplianceStep function
    - Pre-commit hook generator
    - Build step examples
  - **Notes**:
    - PatternConfig (src/types.zig:140-145) not implemented in analyzers
    - Need to wire include_patterns/exclude_patterns for file filtering

- [ ] #LC014: Common patterns library
  - **Component**: src/patterns.zig (new)
  - **Priority**: Medium
  - **Created**: 2025-07-25
  - **Dependencies**: #LC009, #LC010
  - **Details**: High-level convenience functions for common use cases
  - **Requirements**:
    - checkProject function
    - checkFile function
    - checkSource function
    - Pattern documentation

- [ ] #LC015: Result formatting utilities
  - **Component**: src/formatters.zig (new)
  - **Priority**: Medium
  - **Created**: 2025-07-25
  - **Dependencies**: #LC008
  - **Details**: Format analysis results for different outputs
  - **Requirements**:
    - Text formatter
    - JSON formatter
    - GitHub Actions formatter
    - Custom formatter support
  - **Notes**:
    - AnalysisOptions (src/types.zig:147-154) fields not used yet
    - max_issues, verbose, parallel, continue_on_error need implementation

### Phase 5: Documentation and Examples

- [ ] #LC016: API documentation
  - **Component**: All public modules
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Dependencies**: #LC005-#LC015
  - **Details**: Add comprehensive documentation to all public APIs
  - **Requirements**:
    - Doc comments on all public items
    - API reference guide
    - Generated documentation
    - Usage examples in docs

- [ ] #LC017: Integration examples
  - **Component**: examples/
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Dependencies**: #LC013-#LC015
  - **Details**: Create example code for common integration scenarios
  - **Example files**:
    - basic_usage.zig
    - build_integration.zig
    - custom_analyzer.zig
    - ide_integration.zig
    - ci_integration.zig

- [ ] #LC018: Migration guide
  - **Component**: docs/migration-guide.md (new)
  - **Priority**: Medium
  - **Created**: 2025-07-25
  - **Dependencies**: #LC016
  - **Details**: Guide for migrating from CLI to library
  - **Requirements**:
    - CLI to API mappings
    - Before/after examples
    - Common patterns
    - Troubleshooting

### Phase 6: Testing and Validation

- [ ] #LC019: Update test suite
  - **Component**: tests/
  - **Priority**: Critical
  - **Created**: 2025-07-25
  - **Dependencies**: #LC005-#LC012
  - **Details**: Remove CLI tests, add API usage tests
  - **Requirements**:
    - Remove CLI-specific tests
    - Add API tests
    - Error condition tests
    - Performance benchmarks

- [ ] #LC020: Integration testing
  - **Component**: tests/integration/
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Dependencies**: #LC019
  - **Details**: Test library with real projects
  - **Requirements**:
    - Sample project tests
    - Build integration tests
    - Memory usage validation
    - Thread safety tests

- [ ] #LC021: Documentation testing
  - **Component**: All documentation
  - **Priority**: Medium
  - **Created**: 2025-07-25
  - **Dependencies**: #LC016-#LC018
  - **Details**: Ensure all documentation code compiles and works
  - **Requirements**:
    - Example compilation
    - Code snippet validation
    - API completeness check
    - Link validation

## ✅ Completed

*Finished issues for reference*

- [x] #LC027: Add buffer size validation for category formatting
  - **Component**: src/testing_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Completed**: 2025-07-27
  - **Dependencies**: None
  - **Details**: Fixed-size buffers used for category string building could overflow
  - **Resolution**:
    - Replaced fixed 256-byte buffer in determineTestCategory() with dynamic allocation using allocPrint()
    - Replaced fixed 512-byte buffer in generateTestIssues() with ArrayList for building category lists
    - Both changes prevent buffer overflow when handling long category names or many categories
    - Added comprehensive test in test_api.zig with 300+ character category names to verify the fix
    - All tests pass successfully with no buffer overflow issues

- [x] #LC028: Add allocator pattern validation
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Completed**: 2025-07-27
  - **Dependencies**: None
  - **Details**: No validation of allocator patterns in configuration
  - **Resolution**:
    - Added validateAllocatorPatterns() function to check pattern configuration
    - Added new error types to AnalysisError enum: EmptyPatternName, EmptyPattern, DuplicatePatternName, PatternTooGeneric
    - Validation checks for empty pattern names and patterns (returns error)
    - Detects duplicate pattern names across custom and default patterns (returns error)
    - Warns about single-character patterns that may cause false matches (adds warning issue)
    - Warns when custom pattern names conflict with built-in pattern names
    - Added comprehensive tests covering all validation scenarios
    - All tests pass successfully

- [x] #LC026: Document getCategoryBreakdown memory ownership
  - **Component**: src/testing_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-27
  - **Completed**: 2025-07-27
  - **Dependencies**: None
  - **Details**: getCategoryBreakdown returns HashMap that caller must deinit
  - **Resolution**:
    - Added comprehensive doc comment explaining memory ownership (following LC023 pattern)
    - Documented that caller must call deinit() on the returned HashMap
    - Added example usage showing proper cleanup with defer statement
    - Included design note explaining why HashMap is returned instead of struct
    - Added unit test demonstrating proper HashMap cleanup pattern
    - All tests pass successfully

- [x] #LC025: Fix memory lifetime issues in TestPattern
  - **Component**: src/testing_analyzer.zig
  - **Priority**: Medium
  - **Created**: 2025-07-27
  - **Completed**: 2025-07-27
  - **Dependencies**: None
  - **Details**: TestPattern stores reference to category string from config, not a copy
  - **Resolution**:
    - Modified TestPattern creation to duplicate category strings using allocator.dupe()
    - Updated deinit() to free category strings along with test names
    - Updated reset() to free category strings when clearing tests
    - Added comprehensive test to verify category strings survive config deallocation
    - All tests pass successfully

- [x] #LC024: Improve allocator type detection
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-26
  - **Completed**: 2025-07-27
  - **Dependencies**: None
  - **Details**: Current allocator type detection was limited to known patterns
  - **Resolution**:
    - Added AllocatorPattern struct to types.zig for custom pattern definitions
    - Updated MemoryConfig to include allocator_patterns field
    - Refactored extractAllocatorType() to use pattern-based matching
    - Custom patterns are checked first, then default patterns
    - Added comprehensive tests for custom allocator pattern detection
    - Updated CLAUDE.md with configuration examples
    - All tests pass successfully

- [x] #LC023: Document memory management for helper functions
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Low
  - **Created**: 2025-07-26
  - **Completed**: 2025-07-27
  - **Dependencies**: None
  - **Details**: Some helper functions return allocated memory without clear documentation
  - **Resolution**:
    - Added comprehensive doc comment to formatAllowedAllocators() explaining memory ownership
    - Fixed memory leak in validateAllocatorChoice() by storing result and using defer to free
    - Added note explaining design decision to keep allocation-based approach
    - All callers now properly manage memory returned by formatAllowedAllocators()
    - Tests pass successfully

- [x] #LC022: Fix arena allocator tracking
  - **Component**: src/memory_analyzer.zig
  - **Priority**: Medium
  - **Created**: 2025-07-26
  - **Completed**: 2025-07-27
  - **Dependencies**: None
  - **Details**: Arena allocator variable tracking was broken
  - **Resolution**:
    - Added call to trackArenaAllocatorVars() in analyzeSourceCode() loop at line 180
    - Arena-derived allocators (e.g., `const allocator = arena.allocator();`) are now properly tracked
    - Added comprehensive test in test_api.zig to verify arena allocator tracking
    - Verified that allocations using arena-derived allocators no longer generate false positive missing defer warnings
    - All tests pass successfully

- [x] #LC001: Clean up file structure
  - **Component**: All CLI files, scripts, docs
  - **Priority**: Critical
  - **Created**: 2025-07-25
  - **Completed**: 2025-07-25
  - **Dependencies**: None
  - **Details**: Delete all CLI-related files, shell scripts, and CLI documentation
  - **Resolution**:
    - Deleted 18 files: 3 CLI executables, config loader, 3 shell scripts, user guide, 5 config examples, 3 CLI tests
    - Removed 4 directories: src/cli/, scripts/, docs/user-guide/, examples/configs/
    - Updated build.zig to remove CLI targets and run steps
    - Updated README.md to reflect library conversion status
    - Fixed src/root.zig to remove config_loader import
    - All tests pass, build succeeds

- [x] #LC002: Restructure source tree
  - **Component**: src/
  - **Priority**: Critical
  - **Created**: 2025-07-25
  - **Completed**: 2025-07-25
  - **Dependencies**: #LC001
  - **Details**: Flatten directory structure and rename files for library usage
  - **Resolution**:
    - Renamed root.zig to zig_tooling.zig
    - Moved all analyzers from src/analyzers/ to root src/
    - Moved all core modules from src/core/ to root src/
    - Moved logging and config modules to root src/
    - Created types.zig and utils.zig placeholder files
    - Updated all import paths in affected files
    - Updated build.zig to reference new zig_tooling.zig
    - Removed empty directories (analyzers/, core/, logging/, config/, tools/)
    - All tests pass, build succeeds

- [x] #LC003: Update build.zig for library
  - **Component**: build.zig
  - **Priority**: Critical
  - **Created**: 2025-07-25
  - **Completed**: 2025-07-25
  - **Dependencies**: #LC002
  - **Details**: Remove all executable targets and configure as pure library
  - **Resolution**:
    - Added static library artifact with proper name and configuration
    - Configured library installation with b.installArtifact
    - Created module for internal use and testing
    - Added unit tests for the library itself
    - Maintained existing integration test configuration
    - Library builds successfully to zig-out/lib/libzig_tooling.a
    - All tests pass

- [x] #LC004: Update build.zig.zon metadata
  - **Component**: build.zig.zon
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Completed**: 2025-07-25
  - **Dependencies**: #LC003
  - **Details**: Update package metadata for library distribution
  - **Resolution**:
    - Added description field with comprehensive library description
    - Updated paths list: removed "docs", added "tests" for user verification
    - Kept version as 1.0.0 (appropriate for first library release)
    - Kept minimum Zig version as 0.15.0-dev.847+850655f06
    - Library builds successfully with updated metadata
    - All tests pass

- [x] #LC005: Design public API surface
  - **Component**: src/zig_tooling.zig, src/types.zig
  - **Priority**: Critical
  - **Created**: 2025-07-25
  - **Completed**: 2025-07-26
  - **Dependencies**: #LC004
  - **Details**: Create main library interface with clean public API
  - **Resolution**:
    - Created comprehensive types.zig with unified issue types, severity levels, and configuration structures
    - Implemented clean public API in zig_tooling.zig with analyzer exports and convenience functions
    - Added analyzeMemory, analyzeTests, analyzeFile, and analyzeSource convenience functions
    - Exported all core types and analyzers for advanced usage
    - Added comprehensive documentation with examples for all public APIs
    - Created test_api.zig with unit tests for the new public API
    - Fixed enum naming conflicts (err vs error) and updated type conversions
    - All tests pass, library builds successfully

- [x] #LC006: Simplify configuration system
  - **Component**: src/config/config.zig, src/types.zig
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Completed**: 2025-07-26
  - **Dependencies**: #LC005
  - **Details**: Remove file-based config, convert to programmatic only
  - **Resolution**:
    - Deleted unused src/config/config.zig file (198 lines removed)
    - Updated MemoryAnalyzer to accept and use MemoryConfig from types.zig
    - Updated TestingAnalyzer to accept and use TestingConfig from types.zig
    - Added configuration checks before creating issues (check_defer, check_arena_usage, etc.)
    - Wired configuration through public API functions analyzeMemory() and analyzeTests()
    - Added comprehensive tests for configuration usage in test_api.zig
    - Configuration is now purely programmatic with sensible defaults
    - All tests pass, configuration system fully functional

- [x] #LC007: Remove CLI dependencies
  - **Component**: All analyzers and core modules
  - **Priority**: Critical
  - **Created**: 2025-07-25
  - **Completed**: 2025-07-26
  - **Dependencies**: #LC005
  - **Details**: Remove all print statements and CLI-specific code
  - **Resolution**:
    - Removed printReport() methods from both analyzers (42 lines removed from each)
    - Removed print imports from memory_analyzer.zig and testing_analyzer.zig
    - Removed debug print statements from both analyzers
    - Converted debug.print in app_logger.zig to proper error handling with TODO note
    - Removed print import from app_logger.zig
    - All tests pass, library builds successfully
    - Analyzers now return structured data only, no console output

- [x] #LC008: Improve error handling
  - **Component**: src/types.zig, all modules
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Completed**: 2025-07-26
  - **Dependencies**: #LC007
  - **Details**: Define proper error types and structured issues
  - **Resolution**:
    - AnalysisError enum already existed in types.zig with proper error types
    - Issue struct already existed in types.zig
    - Removed duplicate AnalyzerError enums from both memory_analyzer.zig and testing_analyzer.zig
    - Updated all error returns to use unified AnalysisError from types.zig
    - Fixed field name mismatches (description → message) in issue creation
    - Added comprehensive error documentation with examples
    - Removed unnecessary type conversion functions from zig_tooling.zig
    - Both analyzers now use unified Issue type directly
    - All tests pass, library builds successfully
  - **Cleanup needed in LC009/LC010**:
    - Remove legacy type aliases (MemoryIssue, TestingIssue) added for backward compatibility
    - Clean up duplicate type imports (IssueType, Severity) to use types.* directly
    - Watch for similar field name patterns in other modules

- [x] #LC009: Refactor memory analyzer
  - **Component**: src/memory_analyzer.zig
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Completed**: 2025-07-26
  - **Dependencies**: #LC008
  - **Details**: Remove CLI formatting, return structured data
  - **Resolution**:
    - Removed legacy type alias `pub const MemoryIssue = Issue;` and duplicate imports
    - Implemented allowed_allocators configuration check in validateAllocatorChoice()
    - Enhanced allocator tracking with extractAllocatorType() to identify allocator types
    - Removed NFL-specific ComponentType enum and determineComponentType() function
    - Added formatAllowedAllocators() helper for better error messages
    - Added comprehensive tests for allowed_allocators configuration
    - All allocator usage is now validated against the configured allowed list
    - Library is now fully generic and suitable for any Zig project

- [x] #LC010: Refactor testing analyzer
  - **Component**: src/testing_analyzer.zig
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Completed**: 2025-07-27
  - **Dependencies**: #LC008
  - **Details**: Make test categories configurable, return structured results
  - **Resolution**:
    - Removed hardcoded TestCategory enum and replaced with dynamic string-based categories
    - Updated TestPattern to use optional string category instead of enum
    - Rewrote determineTestCategory() to use config.allowed_categories
    - Updated all category-related functions to work with configurable categories
    - Removed legacy TestingIssue type alias and duplicate imports
    - Added structured compliance data methods (getComplianceReport, getCategoryBreakdown, etc.)
    - Added TestComplianceReport struct for detailed analysis results
    - All tests pass, library builds successfully

## Issue Guidelines

1. **Issue Format**: `#LCXXX: Clear, action-oriented title` (LC = Library Conversion)
2. **Components**: Always specify affected files/modules
3. **Priority Levels**: Critical > High > Medium > Low
4. **Dependencies**: List prerequisite issues that must be completed first
5. **Status Flow**: Backlog → In Progress → Completed
6. **Updates**: Add notes/blockers as sub-items under issues

---

*Last Updated: 2025-07-27 (LC028 completed; added 3 new pattern-related issues LC031-LC033)*
*Focus: Library Conversion Project*