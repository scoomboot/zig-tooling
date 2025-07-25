# Issue Tracking - Library Conversion

## 🚨 Critical Issues

*Issues that block core functionality or development*

## 🔧 In Progress

*Currently being worked on*

## 📋 Backlog

*Library conversion work organized by phase*

### Phase 1: Project Restructuring

- [ ] #LC004: Update build.zig.zon metadata
  - **Component**: build.zig.zon
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Dependencies**: #LC003
  - **Details**: Update package metadata for library distribution
  - **Requirements**:
    - Change package type
    - Update semantic version
    - Update paths list
    - Add library metadata

### Phase 2: API Design and Refactoring

- [ ] #LC005: Design public API surface
  - **Component**: src/zig_tooling.zig (new)
  - **Priority**: Critical
  - **Created**: 2025-07-25
  - **Dependencies**: #LC004
  - **Details**: Create main library interface with clean public API
  - **Requirements**:
    - Export analyzer types
    - Add convenience functions
    - Define public types
    - Document API surface

- [ ] #LC006: Simplify configuration system
  - **Component**: src/config/config.zig, src/types.zig
  - **Priority**: High
  - **Created**: 2025-07-25
  - **Dependencies**: #LC005
  - **Details**: Remove file-based config, convert to programmatic only
  - **Requirements**:
    - Remove config file I/O
    - Simplify config structures
    - Provide defaults
    - Support inline config

- [ ] #LC007: Remove CLI dependencies
  - **Component**: All analyzers and core modules
  - **Priority**: Critical
  - **Created**: 2025-07-25
  - **Dependencies**: #LC005
  - **Details**: Remove all print statements and CLI-specific code
  - **Requirements**:
    - Remove print statements
    - Return structured data
    - Remove progress indicators
    - Convert errors to types

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
  - **Component**: src/logging/app_logger.zig
  - **Priority**: Low
  - **Created**: 2025-07-25
  - **Dependencies**: #LC008
  - **Details**: Make logging optional with callback interface
  - **Requirements**:
    - Optional logging
    - Callback interface
    - Remove file rotation
    - Structured events

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

## Issue Guidelines

1. **Issue Format**: `#LCXXX: Clear, action-oriented title` (LC = Library Conversion)
2. **Components**: Always specify affected files/modules
3. **Priority Levels**: Critical > High > Medium > Low
4. **Dependencies**: List prerequisite issues that must be completed first
5. **Status Flow**: Backlog → In Progress → Completed
6. **Updates**: Add notes/blockers as sub-items under issues

---

*Last Updated: 2025-07-25 (LC003 completed)*
*Focus: Library Conversion Project*