# Issue Tracking - Library Conversion

## 🚨 Critical Issues

*Issues that block core functionality or development*

## 🔧 In Progress

*Currently being worked on*

## 📋 Backlog

*Library conversion work organized by phase*

### Phase 1: Project Restructuring

### Phase 2: API Design and Refactoring

- [ ] #LC008: Improve error handling
  - **Component**: src/types.zig, all modules
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Dependencies**: #LC007
  - **Details**: Define proper error types and structured issues
  - **Requirements**:
    - Define AnalysisError enum
    - Create Issue struct
    - Update all error returns
    - Add error documentation

### Phase 3: Core Component Updates

- [ ] #LC009: Refactor memory analyzer
  - **Component**: src/memory_analyzer.zig
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Dependencies**: #LC008
  - **Details**: Remove CLI formatting, return structured data
  - **Requirements**:
    - Remove issue formatting
    - Return issue arrays
    - Simplify component detection
    - Flexible allocator handling
  - **Notes**:
    - MemoryConfig.allowed_allocators field exists but not checked (src/types.zig:126)
    - validateAllocatorChoice() at src/memory_analyzer.zig:628 needs update

- [ ] #LC010: Refactor testing analyzer
  - **Component**: src/testing_analyzer.zig
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Dependencies**: #LC008
  - **Details**: Make test categories configurable, return structured results
  - **Requirements**:
    - Remove hardcoded categories
    - Configurable naming rules
    - Return compliance data
    - Simplify validation logic
  - **Notes**:
    - TestCategory enum still hardcoded in src/testing_analyzer.zig:43-63
    - Config has allowed_categories field but analyzer doesn't use it yet
    - See determineTestCategory() at src/testing_analyzer.zig:618

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

## Issue Guidelines

1. **Issue Format**: `#LCXXX: Clear, action-oriented title` (LC = Library Conversion)
2. **Components**: Always specify affected files/modules
3. **Priority Levels**: Critical > High > Medium > Low
4. **Dependencies**: List prerequisite issues that must be completed first
5. **Status Flow**: Backlog → In Progress → Completed
6. **Updates**: Add notes/blockers as sub-items under issues

---

*Last Updated: 2025-07-26 (LC007 completed)*
*Focus: Library Conversion Project*