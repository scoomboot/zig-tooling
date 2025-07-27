//! Common types and structures for zig-tooling library
//!
//! This module defines the core data types used throughout the zig-tooling library,
//! including issue definitions, analysis results, and configuration structures.
//! All analyzers use these unified types to ensure consistency across the library.
//!
//! ## Key Types
//! - `Issue`: Represents a single analysis finding
//! - `AnalysisResult`: Contains the complete results of an analysis operation
//! - `Config`: Main configuration structure for customizing analysis behavior
//! - `AnalysisError`: Error types that can occur during analysis

const std = @import("std");
const app_logger = @import("app_logger.zig");

/// Severity levels for all analysis issues
///
/// Determines the importance and impact of detected issues.
/// Used to filter results and control build failures.
///
/// ## Values
/// - `err`: Critical issues that should fail builds (e.g., memory leaks)
/// - `warning`: Important issues that may need attention (e.g., missing test categories)
/// - `info`: Informational notices for best practices
pub const Severity = enum {
    err,
    warning,
    info,

    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .err => "error",
            .warning => "warning",
            .info => "info",
        };
    }
};

/// Types of issues that can be detected by the analyzers
///
/// This enum categorizes all possible issues that can be detected during analysis.
/// Issues are grouped into memory-related and testing-related categories.
///
/// ## Memory Issues
/// - `missing_defer`: Allocation without corresponding defer cleanup
/// - `memory_leak`: Potential memory leak detected
/// - `double_free`: Same memory freed multiple times
/// - `use_after_free`: Memory accessed after being freed
/// - `incorrect_allocator`: Using disallowed allocator type
/// - `arena_in_library`: Arena allocator used in library code
/// - `missing_errdefer`: Allocation in error path without errdefer
/// - `defer_in_loop`: Defer statement inside a loop (may accumulate)
/// - `ownership_transfer`: Function returns allocated memory (documentation needed)
/// - `allocator_mismatch`: Different allocators used for alloc/free
///
/// ## Testing Issues
/// - `missing_test_category`: Test without category prefix
/// - `invalid_test_naming`: Test name doesn't follow conventions
/// - `test_outside_file`: Test defined outside test file
/// - `missing_test_file`: Source file without corresponding tests
/// - `orphaned_test`: Test file without corresponding source
/// - `missing_source_file`: Test references non-existent source
/// - `source_without_tests`: Source file has no test coverage
/// - `invalid_test_location`: Test in wrong directory structure
/// - `duplicate_test_name`: Multiple tests with same name
pub const IssueType = enum {
    // Memory-related issues
    missing_defer,
    memory_leak,
    double_free,
    use_after_free,
    incorrect_allocator,
    arena_in_library,
    missing_errdefer,
    defer_in_loop,
    ownership_transfer,
    allocator_mismatch,
    
    // Testing-related issues
    missing_test_category,
    invalid_test_naming,
    test_outside_file,
    missing_test_file,
    orphaned_test,
    missing_source_file,
    source_without_tests,
    invalid_test_location,
    duplicate_test_name,

    pub fn toString(self: IssueType) []const u8 {
        return switch (self) {
            .missing_defer => "missing_defer",
            .memory_leak => "memory_leak",
            .double_free => "double_free",
            .use_after_free => "use_after_free",
            .incorrect_allocator => "incorrect_allocator",
            .arena_in_library => "arena_in_library",
            .missing_errdefer => "missing_errdefer",
            .defer_in_loop => "defer_in_loop",
            .ownership_transfer => "ownership_transfer",
            .allocator_mismatch => "allocator_mismatch",
            .missing_test_category => "missing_test_category",
            .invalid_test_naming => "invalid_test_naming",
            .test_outside_file => "test_outside_file",
            .missing_test_file => "missing_test_file",
            .orphaned_test => "orphaned_test",
            .missing_source_file => "missing_source_file",
            .source_without_tests => "source_without_tests",
            .invalid_test_location => "invalid_test_location",
            .duplicate_test_name => "duplicate_test_name",
        };
    }
};

/// Represents a single issue found during analysis
///
/// This structure contains all information needed to understand and locate
/// an issue in the source code. Issues are created by analyzers when they
/// detect problems or violations of configured rules.
///
/// ## Memory Management
/// The strings in this structure are owned by the analyzer that created them.
/// When freeing an AnalysisResult, remember to free all string fields:
/// ```zig
/// for (result.issues) |issue| {
///     allocator.free(issue.file_path);
///     allocator.free(issue.message);
///     if (issue.suggestion) |s| allocator.free(s);
///     // code_snippet is typically not owned by the issue
/// }
/// allocator.free(result.issues);
/// ```
pub const Issue = struct {
    /// Path to the file containing the issue
    file_path: []const u8,
    
    /// Line number where the issue starts (1-based)
    line: u32,
    
    /// Column number where the issue starts (1-based)
    column: u32,
    
    /// Type of issue detected
    issue_type: IssueType,
    
    /// Severity level of the issue
    severity: Severity,
    
    /// Human-readable description of the issue
    message: []const u8,
    
    /// Optional suggestion for fixing the issue
    suggestion: ?[]const u8 = null,
    
    /// Optional code snippet showing the problematic code
    code_snippet: ?[]const u8 = null,
};

/// Contains the complete results of an analysis operation
///
/// This structure is returned by all analysis functions and contains
/// both the detected issues and metadata about the analysis process.
///
/// ## Memory Management
/// The caller owns the memory and must free it properly:
/// ```zig
/// const result = try zig_tooling.analyzeFile(allocator, "main.zig", null);
/// defer {
///     for (result.issues) |issue| {
///         allocator.free(issue.file_path);
///         allocator.free(issue.message);
///         if (issue.suggestion) |s| allocator.free(s);
///     }
///     allocator.free(result.issues);
/// }
/// ```
pub const AnalysisResult = struct {
    /// Array of all issues found during analysis
    issues: []const Issue,
    
    /// Number of files that were analyzed
    files_analyzed: u32,
    
    /// Total count of issues found (same as issues.len)
    issues_found: u32,
    
    /// Time taken for analysis in milliseconds
    analysis_time_ms: u64,
    
    pub fn hasErrors(self: AnalysisResult) bool {
        for (self.issues) |issue| {
            if (issue.severity == .err) return true;
        }
        return false;
    }
    
    pub fn hasWarnings(self: AnalysisResult) bool {
        for (self.issues) |issue| {
            if (issue.severity == .warning) return true;
        }
        return false;
    }
};

/// Main configuration structure for all analysis operations
///
/// This structure allows customization of all aspects of the analysis process.
/// Each field represents a different aspect of configuration, with sensible
/// defaults provided for all options.
///
/// ## Example
/// ```zig
/// const config = Config{
///     .memory = .{
///         .check_defer = true,
///         .allowed_allocators = &.{"std.heap.GeneralPurposeAllocator"},
///     },
///     .testing = .{
///         .enforce_categories = true,
///         .allowed_categories = &.{"unit", "integration"},
///     },
///     .options = .{
///         .fail_on_warnings = true,
///     },
/// };
/// const result = try zig_tooling.analyzeFile(allocator, "main.zig", config);
/// ```
pub const Config = struct {
    /// Memory analysis configuration
    memory: MemoryConfig = .{},
    
    /// Testing analysis configuration
    testing: TestingConfig = .{},
    
    /// File patterns to include/exclude
    patterns: PatternConfig = .{},
    
    /// General analysis options
    options: AnalysisOptions = .{},
    
    /// Logging configuration
    logging: app_logger.LoggingConfig = .{},
};

/// Pattern definition for custom allocator detection
///
/// Allows defining custom patterns to identify allocator types in code.
/// These patterns are used to detect when specific allocator types are used,
/// enabling project-specific allocator validation.
///
/// ## Example
/// ```zig
/// const patterns = &[_]AllocatorPattern{
///     .{ .name = "MyPoolAllocator", .pattern = "pool_alloc" },
///     .{ .name = "MyArenaAllocator", .pattern = "arena" },
/// };
/// const config = Config{
///     .memory = .{
///         .allocator_patterns = patterns,
///         .allowed_allocators = &.{"MyPoolAllocator"},
///     },
/// };
/// ```
pub const AllocatorPattern = struct {
    /// Display name for the allocator type (e.g., "MyCustomAllocator")
    /// This name is used in error messages and allowed_allocators matching
    name: []const u8,
    
    /// Pattern to match in the allocator variable name (substring match)
    /// If the variable name contains this pattern, it's identified as this allocator type
    pattern: []const u8,
    
    /// Future extension: whether to use regex matching (not implemented yet)
    /// When implemented, will allow patterns like "^my_.*_allocator$"
    is_regex: bool = false,
};

/// Pattern definition for ownership transfer detection
///
/// Allows defining custom patterns to identify functions that transfer memory
/// ownership to their callers. These patterns help reduce false positive
/// "missing defer" warnings for valid ownership transfer scenarios.
///
/// ## Example
/// ```zig
/// const patterns = &[_]OwnershipPattern{
///     .{ .function_pattern = "create", .return_type_pattern = null },
///     .{ .function_pattern = null, .return_type_pattern = "![]u8" },
///     .{ .function_pattern = "init", .return_type_pattern = "!*MyStruct" },
/// };
/// const config = Config{
///     .memory = .{
///         .ownership_patterns = patterns,
///     },
/// };
/// ```
pub const OwnershipPattern = struct {
    /// Pattern to match in function names (substring match)
    /// If null, only return_type_pattern is checked
    function_pattern: ?[]const u8 = null,
    
    /// Pattern to match in return types (substring match) 
    /// If null, only function_pattern is checked
    /// Examples: "[]u8", "![]u8", "*MyStruct", "?*T"
    return_type_pattern: ?[]const u8 = null,
    
    /// Description of this pattern for documentation/debugging
    description: ?[]const u8 = null,
    
    /// Future extension: whether to use regex matching (not implemented yet)
    is_regex: bool = false,
};

/// Configuration options for memory safety analysis
///
/// Controls which memory safety checks are performed and how they behave.
/// All options have sensible defaults for typical Zig projects.
///
/// ## Common Configurations
/// 
/// ### Strict library mode:
/// ```zig
/// .memory = .{
///     .check_arena_usage = true,  // No arenas in libraries
///     .allowed_allocators = &.{"std.heap.GeneralPurposeAllocator"},
/// }
/// ```
///
/// ### Test-friendly mode:
/// ```zig
/// .memory = .{
///     .track_test_allocations = true,
///     .allowed_allocators = &.{"std.testing.allocator", "std.heap.GeneralPurposeAllocator"},
/// }
/// ```
pub const MemoryConfig = struct {
    /// Check for missing defer statements after allocations
    check_defer: bool = true,
    
    /// Warn about arena allocator usage in library code
    check_arena_usage: bool = true,
    
    /// Validate allocator types against allowed_allocators list
    check_allocator_usage: bool = true,
    
    /// Detect ownership transfer patterns (functions returning allocated memory)
    check_ownership_transfer: bool = true,
    
    /// Track allocations in test code (usually more lenient)
    track_test_allocations: bool = true,
    
    /// List of allowed allocator type names (empty = allow all)
    /// Common values: "std.heap.GeneralPurposeAllocator", "std.testing.allocator"
    allowed_allocators: []const []const u8 = &.{},
    
    /// Custom allocator patterns for type detection
    /// These patterns are checked before the default built-in patterns
    allocator_patterns: []const AllocatorPattern = &.{},
    
    /// Whether to use default built-in allocator patterns
    /// Set to false to only use custom patterns defined in allocator_patterns
    use_default_patterns: bool = true,
    
    /// List of default pattern names to disable
    /// Useful for excluding specific built-in patterns that conflict with your project
    /// Example: &.{ "std.testing.allocator" } to disable the testing allocator pattern
    disabled_default_patterns: []const []const u8 = &.{},
    
    /// Custom ownership transfer patterns for detection
    /// These patterns help identify functions that transfer allocated memory ownership
    ownership_patterns: []const OwnershipPattern = &.{},
    
    /// Whether to use default built-in ownership patterns
    /// Set to false to only use custom patterns defined in ownership_patterns
    use_default_ownership_patterns: bool = true,
};

/// Configuration options for test compliance analysis
///
/// Controls how tests are validated for organization, naming, and structure.
/// Helps maintain consistent test practices across a codebase.
///
/// ## Example
/// ```zig
/// .testing = .{
///     .enforce_categories = true,
///     .allowed_categories = &.{ "unit", "integration", "api" },
///     .test_file_suffix = "_test",
///     .test_directory = "tests",
/// }
/// ```
pub const TestingConfig = struct {
    /// Require test names to start with a category prefix (e.g., "unit: ...")
    enforce_categories: bool = true,
    
    /// Enforce test naming conventions
    enforce_naming: bool = true,
    
    /// Require tests to be in dedicated test files
    enforce_test_files: bool = true,
    
    /// List of valid test category prefixes
    /// Tests must start with one of these followed by ": "
    allowed_categories: []const []const u8 = &.{ "unit", "integration", "e2e", "performance", "stress" },
    
    /// Required suffix for test files (e.g., "_test" for "foo_test.zig")
    test_file_suffix: []const u8 = "_test",
    
    /// Optional: specific directory where tests should be located
    /// If null, tests can be anywhere following naming conventions
    test_directory: ?[]const u8 = null,
};

/// Configuration for file discovery and filtering
///
/// Controls which files are analyzed during project-wide analysis.
/// Uses glob-style patterns for flexible file selection.
///
/// ## Pattern Syntax
/// - `*` matches any characters except path separator
/// - `**` matches any number of directories
/// - `?` matches single character
///
/// ## Example
/// ```zig
/// .patterns = .{
///     .include_patterns = &.{ "src/**/*.zig", "lib/**/*.zig" },
///     .exclude_patterns = &.{ "**/generated/**", "**/vendor/**" },
/// }
/// ```
pub const PatternConfig = struct {
    /// Glob patterns for files to include in analysis
    include_patterns: []const []const u8 = &.{ "**/*.zig" },
    
    /// Glob patterns for files/directories to exclude
    /// Default excludes build caches and output directories
    exclude_patterns: []const []const u8 = &.{ "**/zig-cache/**", "**/zig-out/**", "**/.zig-cache/**" },
    
    /// Whether to follow symbolic links during file discovery
    follow_symlinks: bool = false,
};

/// General options that control analysis behavior
///
/// These options affect how the analysis is performed and what happens
/// when issues are found.
///
/// ## Example
/// ```zig
/// .options = .{
///     .max_issues = 100,           // Stop after 100 issues
///     .fail_on_warnings = true,    // Treat warnings as errors
///     .verbose = true,             // Include detailed information
/// }
/// ```
pub const AnalysisOptions = struct {
    /// Maximum number of issues to report (null = unlimited)
    /// Analysis stops when this limit is reached
    max_issues: ?u32 = null,
    
    /// Whether warnings should be treated as errors
    /// Useful for strict CI/CD pipelines
    fail_on_warnings: bool = false,
    
    /// Enable verbose output with additional details
    /// Includes code snippets and detailed explanations
    verbose: bool = false,
    
    /// Enable parallel file analysis (not yet implemented)
    /// Will analyze multiple files concurrently when available
    parallel: bool = true,
    
    /// Continue analyzing after encountering errors
    /// If false, stops on first error
    continue_on_error: bool = true,
};

/// Configuration for the scope tracking system
///
/// Controls how the scope tracker analyzes code structure and tracks
/// various program elements. Used internally by analyzers but can be
/// configured for custom analysis needs.
///
/// ## Performance Tuning
/// ```zig
/// .scope_config = .{
///     .lazy_parsing = true,               // Enable for large files
///     .lazy_parsing_threshold = 5000,     // Files over 5k lines
///     .max_scope_depth = 10,              // Limit nesting depth
/// }
/// ```
///
/// ## Custom Ownership Patterns
/// ```zig
/// .scope_config = .{
///     .ownership_patterns = &.{ "alloc", "new", "clone" },
/// }
/// ```
pub const ScopeConfig = struct {
    /// Custom patterns to identify ownership transfer functions
    /// Functions containing these patterns likely return allocated memory
    /// Default includes common patterns like "create", "generate", "build", etc.
    ownership_patterns: []const []const u8 = &.{},
    
    /// Whether to track arena allocator usage
    /// Enables detection of arena lifecycle issues
    track_arena_allocators: bool = true,
    
    /// Whether to analyze variable lifecycles
    /// Tracks variable definitions and usage patterns
    track_variable_lifecycles: bool = true,
    
    /// Whether to track defer statements
    /// Required for defer validation in memory analysis
    track_defer_statements: bool = true,
    
    /// Maximum depth of scope nesting to track (0 = unlimited)
    /// Limits analysis depth for deeply nested code
    max_scope_depth: u32 = 0,
    
    /// Whether to use lazy parsing for large files
    /// Improves performance by parsing only what's needed
    lazy_parsing: bool = false,
    
    /// Minimum line count to trigger lazy parsing
    /// Files smaller than this are always fully parsed
    lazy_parsing_threshold: u32 = 10000,
};

/// Analysis errors that can occur during code analysis operations
/// 
/// These errors represent various failure conditions that may occur when
/// analyzing Zig source code files. Proper error handling ensures graceful
/// degradation and meaningful error messages to users.
/// 
/// Example usage:
/// ```zig
/// const result = zig_tooling.analyzeFile(allocator, "src/main.zig", null) catch |err| switch (err) {
///     AnalysisError.FileNotFound => {
///         std.debug.print("File not found: src/main.zig\n", .{});
///         return;
///     },
///     AnalysisError.AccessDenied => {
///         std.debug.print("Permission denied accessing file\n", .{});
///         return;
///     },
///     else => return err,
/// };
/// ```
pub const AnalysisError = error{
    /// Failed to read file contents due to I/O error
    /// Occurs when file exists but cannot be read (disk error, etc.)
    FileReadError,
    
    /// Failed to parse source code
    /// Indicates malformed or invalid Zig syntax that prevents analysis
    ParseError,
    
    /// Configuration validation failed
    /// The provided Config struct contains invalid or conflicting settings
    InvalidConfiguration,
    
    /// Memory allocation failed
    /// System is out of memory or allocation limit reached
    OutOfMemory,
    
    /// File or directory access denied
    /// Insufficient permissions to read the requested file
    AccessDenied,
    
    /// Requested file does not exist
    /// The specified file path could not be found in the filesystem
    FileNotFound,
    
    /// Invalid file path provided
    /// Path contains invalid characters or format
    InvalidPath,
    
    /// Analysis stopped due to too many issues
    /// Exceeded the configured maximum issue limit (AnalysisOptions.max_issues)
    TooManyIssues,
    
    /// Allocator pattern name is empty
    /// Pattern definitions must have a non-empty name for identification
    EmptyPatternName,
    
    /// Allocator pattern string is empty
    /// Pattern definitions must have a non-empty pattern for matching
    EmptyPattern,
    
    /// Duplicate allocator pattern name found
    /// Each pattern name must be unique across all configured patterns
    DuplicatePatternName,
    
    /// Allocator pattern is too generic (e.g., single character)
    /// Overly generic patterns may cause false positive matches
    PatternTooGeneric,
    
    /// Pattern conflict detected between custom and built-in patterns
    /// Custom patterns should use unique names to avoid confusion
    PatternConflict,
};