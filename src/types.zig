// Common types and structures for zig-tooling library

const std = @import("std");

/// Severity levels for all analysis issues
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

/// Types of issues that can be detected
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

/// Unified issue structure for all analyzers
pub const Issue = struct {
    file_path: []const u8,
    line: u32,
    column: u32,
    issue_type: IssueType,
    severity: Severity,
    message: []const u8,
    suggestion: ?[]const u8 = null,
    code_snippet: ?[]const u8 = null,
};

/// Result of an analysis operation
pub const AnalysisResult = struct {
    issues: []const Issue,
    files_analyzed: u32,
    issues_found: u32,
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

/// Configuration for analysis operations
pub const Config = struct {
    /// Memory analysis configuration
    memory: MemoryConfig = .{},
    
    /// Testing analysis configuration
    testing: TestingConfig = .{},
    
    /// File patterns to include/exclude
    patterns: PatternConfig = .{},
    
    /// General analysis options
    options: AnalysisOptions = .{},
};

/// Pattern definition for custom allocator detection
pub const AllocatorPattern = struct {
    /// Display name for the allocator type (e.g., "MyCustomAllocator")
    name: []const u8,
    
    /// Pattern to match in the allocator variable name (substring match)
    pattern: []const u8,
    
    /// Future extension: whether to use regex matching (not implemented yet)
    is_regex: bool = false,
};

/// Memory analysis specific configuration
pub const MemoryConfig = struct {
    check_defer: bool = true,
    check_arena_usage: bool = true,
    check_allocator_usage: bool = true,
    check_ownership_transfer: bool = true,
    track_test_allocations: bool = true,
    allowed_allocators: []const []const u8 = &.{},
    
    /// Custom allocator patterns for type detection
    /// These patterns are checked before the default built-in patterns
    allocator_patterns: []const AllocatorPattern = &.{},
};

/// Testing analysis specific configuration  
pub const TestingConfig = struct {
    enforce_categories: bool = true,
    enforce_naming: bool = true,
    enforce_test_files: bool = true,
    allowed_categories: []const []const u8 = &.{ "unit", "integration", "e2e", "performance", "stress" },
    test_file_suffix: []const u8 = "_test",
    test_directory: ?[]const u8 = null,
};

/// File pattern configuration
pub const PatternConfig = struct {
    include_patterns: []const []const u8 = &.{ "**/*.zig" },
    exclude_patterns: []const []const u8 = &.{ "**/zig-cache/**", "**/zig-out/**", "**/.zig-cache/**" },
    follow_symlinks: bool = false,
};

/// General analysis options
pub const AnalysisOptions = struct {
    max_issues: ?u32 = null,
    fail_on_warnings: bool = false,
    verbose: bool = false,
    parallel: bool = true,
    continue_on_error: bool = true,
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
};