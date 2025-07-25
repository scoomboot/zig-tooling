const std = @import("std");

/// Global configuration shared across all tools
pub const GlobalConfig = struct {
    /// Path to log file, can be overridden by ZIG_TOOLING_LOG_PATH env var
    log_path: ?[]const u8 = null,
    
    /// Output format: "text" or "json"
    output_format: []const u8 = "text",
    
    /// Enable colored output for terminal
    color_output: bool = true,
    
    /// Verbosity level: 0 = quiet, 1 = normal, 2 = verbose
    verbosity: u8 = 1,
};

/// Memory checker specific configuration
pub const MemoryCheckerConfig = struct {
    /// Patterns to skip when scanning files
    skip_patterns: []const []const u8 = &[_][]const u8{
        "test_",
        ".test.zig",
        "generated_",
        "zig-cache/",
        "zig-out/",
    },
    
    /// Severity levels for different issue types
    severity_levels: struct {
        missing_defer: []const u8 = "error",
        missing_errdefer: []const u8 = "warning",
        allocation_no_free: []const u8 = "error",
        ownership_transfer: []const u8 = "info",
    } = .{},
    
    /// Whether to analyze test files
    analyze_tests: bool = false,
    
    /// Maximum file size to analyze (in bytes)
    max_file_size: usize = 10 * 1024 * 1024, // 10MB
};

/// Testing compliance specific configuration
pub const TestingComplianceConfig = struct {
    /// Patterns to skip when scanning files
    skip_patterns: []const []const u8 = &[_][]const u8{
        "build_runner.zig",
        "generated_",
        "zig-cache/",
        "zig-out/",
    },
    
    /// Enforce strict test naming conventions
    test_naming_strict: bool = true,
    
    /// Required test file prefix
    test_file_prefix: []const u8 = "test_",
    
    /// Allowed test categories
    allowed_test_categories: []const []const u8 = &[_][]const u8{
        "unit",
        "integration",
        "e2e",
        "performance",
    },
    
    /// Require test category in test names
    require_test_category: bool = true,
};

/// Logger specific configuration
pub const LoggerConfig = struct {
    /// Maximum log file size in MB before rotation
    max_log_size_mb: u32 = 10,
    
    /// Number of archive files to keep
    max_archives: u32 = 5,
    
    /// Performance warning threshold in milliseconds
    performance_warn_threshold_ms: u64 = 1000,
    
    /// Log level: "debug", "info", "warn", "error"
    log_level: []const u8 = "info",
    
    /// Include timestamps in log entries
    include_timestamps: bool = true,
    
    /// Archive compression: "none", "gzip"
    archive_compression: []const u8 = "none",
};

/// Combined configuration for all tools
pub const ToolConfig = struct {
    global: GlobalConfig = .{},
    memory_checker: MemoryCheckerConfig = .{},
    testing_compliance: TestingComplianceConfig = .{},
    logger: LoggerConfig = .{},
    
    /// Allocator for dynamic allocations in config
    allocator: std.mem.Allocator,
    
    /// Create a new ToolConfig with default values
    pub fn init(allocator: std.mem.Allocator) ToolConfig {
        return .{
            .allocator = allocator,
        };
    }
    
    /// Free any allocated memory
    pub fn deinit(self: *ToolConfig) void {
        // Free allocated strings if needed
        if (self.global.log_path) |path| {
            if (path.len > 0) {
                self.allocator.free(path);
            }
        }
        
        // Free skip patterns if dynamically allocated
        // Note: In a real implementation, we'd track which strings
        // were allocated vs static and free accordingly
    }
    
    /// Clone configuration with allocator
    pub fn clone(self: *const ToolConfig, allocator: std.mem.Allocator) !ToolConfig {
        var new_config = ToolConfig.init(allocator);
        
        // Deep copy global config
        new_config.global = self.global;
        if (self.global.log_path) |path| {
            new_config.global.log_path = try allocator.dupe(u8, path);
        }
        
        // Copy other configs (they use static defaults for now)
        new_config.memory_checker = self.memory_checker;
        new_config.testing_compliance = self.testing_compliance;
        new_config.logger = self.logger;
        
        return new_config;
    }
    
    /// Get config value with fallback to environment variable
    pub fn getLogPath(self: *const ToolConfig) ?[]const u8 {
        if (self.global.log_path) |path| {
            return path;
        }
        return std.process.getEnvVarOwned(
            self.allocator,
            "ZIG_TOOLING_LOG_PATH"
        ) catch null;
    }
    
    /// Check if output should be JSON
    pub fn isJsonOutput(self: *const ToolConfig) bool {
        return std.mem.eql(u8, self.global.output_format, "json");
    }
    
    /// Check if a file should be skipped for memory checker
    pub fn shouldSkipFileMemory(self: *const ToolConfig, file_path: []const u8) bool {
        return self.shouldSkipFile(file_path, self.memory_checker.skip_patterns);
    }
    
    /// Check if a file should be skipped for testing compliance
    pub fn shouldSkipFileTesting(self: *const ToolConfig, file_path: []const u8) bool {
        return self.shouldSkipFile(file_path, self.testing_compliance.skip_patterns);
    }
    
    fn shouldSkipFile(self: *const ToolConfig, file_path: []const u8, patterns: []const []const u8) bool {
        _ = self;
        for (patterns) |pattern| {
            if (std.mem.indexOf(u8, file_path, pattern) != null) {
                return true;
            }
        }
        return false;
    }
};

/// Parse severity level from string
pub fn parseSeverityLevel(level: []const u8) ![]const u8 {
    if (std.mem.eql(u8, level, "error") or
        std.mem.eql(u8, level, "warning") or
        std.mem.eql(u8, level, "info")) {
        return level;
    }
    return error.InvalidSeverityLevel;
}

/// Parse log level from string
pub fn parseLogLevel(level: []const u8) ![]const u8 {
    if (std.mem.eql(u8, level, "debug") or
        std.mem.eql(u8, level, "info") or
        std.mem.eql(u8, level, "warn") or
        std.mem.eql(u8, level, "error")) {
        return level;
    }
    return error.InvalidLogLevel;
}