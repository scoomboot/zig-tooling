const std = @import("std");
const config = @import("config.zig");

const ConfigError = error{
    InvalidJson,
    FileNotFound,
    InvalidConfigValue,
    AllocationError,
};

/// Config loader that handles JSON parsing and loading
pub const ConfigLoader = struct {
    allocator: std.mem.Allocator,
    
    /// Initialize a new config loader
    pub fn init(allocator: std.mem.Allocator) ConfigLoader {
        return .{ .allocator = allocator };
    }
    
    /// Load configuration from default locations with overrides
    pub fn loadConfig(self: *ConfigLoader) !config.ToolConfig {
        var tool_config = config.ToolConfig.init(self.allocator);
        
        // Try loading from config file
        const config_paths = [_][]const u8{
            ".zigtools.json",
            ".zig-tooling/config.json",
            try self.getHomeConfigPath(),
        };
        
        for (config_paths) |path| {
            if (self.loadFromFile(&tool_config, path)) {
                break;
            } else |_| {
                // Try next path
            }
        }
        
        // Apply environment variable overrides
        try self.applyEnvOverrides(&tool_config);
        
        return tool_config;
    }
    
    /// Load configuration from a specific file path
    pub fn loadFromFile(self: *ConfigLoader, tool_config: *config.ToolConfig, path: []const u8) !void {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return error.FileNotFound;
            }
            return err;
        };
        defer file.close();
        
        const file_size = try file.getEndPos();
        const content = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(content);
        
        _ = try file.read(content);
        
        try self.parseJsonConfig(tool_config, content);
    }
    
    /// Parse JSON configuration content
    fn parseJsonConfig(self: *ConfigLoader, tool_config: *config.ToolConfig, content: []const u8) !void {
        var parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            content,
            .{}
        ) catch return error.InvalidJson;
        defer parsed.deinit();
        
        // Check if parsed value is actually an object
        if (parsed.value != .object) {
            return error.InvalidJson;
        }
        
        const root = parsed.value.object;
        
        // Parse global config
        if (root.get("global")) |global_obj| {
            try self.parseGlobalConfig(&tool_config.global, global_obj);
        }
        
        // Parse memory checker config
        if (root.get("memory_checker")) |mc_obj| {
            try self.parseMemoryCheckerConfig(&tool_config.memory_checker, mc_obj);
        }
        
        // Parse testing compliance config
        if (root.get("testing_compliance")) |tc_obj| {
            try self.parseTestingComplianceConfig(&tool_config.testing_compliance, tc_obj);
        }
        
        // Parse logger config
        if (root.get("logger")) |logger_obj| {
            try self.parseLoggerConfig(&tool_config.logger, logger_obj);
        }
    }
    
    fn parseGlobalConfig(self: *ConfigLoader, global: *config.GlobalConfig, obj: std.json.Value) !void {
        if (obj != .object) return;
        
        if (obj.object.get("log_path")) |val| {
            if (val == .string) {
                // Free old path if it exists
                if (global.log_path) |old_path| {
                    self.allocator.free(old_path);
                }
                global.log_path = try self.allocator.dupe(u8, val.string);
            }
        }
        
        if (obj.object.get("output_format")) |val| {
            if (val == .string) {
                if (std.mem.eql(u8, val.string, "json") or std.mem.eql(u8, val.string, "text")) {
                    global.output_format = try self.allocator.dupe(u8, val.string);
                }
            }
        }
        
        if (obj.object.get("color_output")) |val| {
            if (val == .bool) {
                global.color_output = val.bool;
            }
        }
        
        if (obj.object.get("verbosity")) |val| {
            if (val == .integer) {
                global.verbosity = @intCast(val.integer);
            }
        }
    }
    
    fn parseMemoryCheckerConfig(self: *ConfigLoader, mc: *config.MemoryCheckerConfig, obj: std.json.Value) !void {
        if (obj != .object) return;
        
        if (obj.object.get("analyze_tests")) |val| {
            if (val == .bool) {
                mc.analyze_tests = val.bool;
            }
        }
        
        if (obj.object.get("max_file_size")) |val| {
            if (val == .integer) {
                mc.max_file_size = @intCast(val.integer);
            }
        }
        
        // Parse severity levels
        if (obj.object.get("severity_levels")) |severity_obj| {
            if (severity_obj == .object) {
                if (severity_obj.object.get("missing_defer")) |val| {
                    if (val == .string) {
                        const level = try config.parseSeverityLevel(val.string);
                        mc.severity_levels.missing_defer = try self.allocator.dupe(u8, level);
                    }
                }
                if (severity_obj.object.get("missing_errdefer")) |val| {
                    if (val == .string) {
                        const level = try config.parseSeverityLevel(val.string);
                        mc.severity_levels.missing_errdefer = try self.allocator.dupe(u8, level);
                    }
                }
                if (severity_obj.object.get("allocation_no_free")) |val| {
                    if (val == .string) {
                        const level = try config.parseSeverityLevel(val.string);
                        mc.severity_levels.allocation_no_free = try self.allocator.dupe(u8, level);
                    }
                }
                if (severity_obj.object.get("ownership_transfer")) |val| {
                    if (val == .string) {
                        const level = try config.parseSeverityLevel(val.string);
                        mc.severity_levels.ownership_transfer = try self.allocator.dupe(u8, level);
                    }
                }
            }
        }
        
        // Note: Skip patterns would require dynamic allocation
        // For now, we'll keep the default patterns
    }
    
    fn parseTestingComplianceConfig(self: *ConfigLoader, tc: *config.TestingComplianceConfig, obj: std.json.Value) !void {
        if (obj != .object) return;
        
        if (obj.object.get("test_naming_strict")) |val| {
            if (val == .bool) {
                tc.test_naming_strict = val.bool;
            }
        }
        
        if (obj.object.get("test_file_prefix")) |val| {
            if (val == .string) {
                tc.test_file_prefix = try self.allocator.dupe(u8, val.string);
            }
        }
        
        if (obj.object.get("require_test_category")) |val| {
            if (val == .bool) {
                tc.require_test_category = val.bool;
            }
        }
    }
    
    fn parseLoggerConfig(self: *ConfigLoader, logger: *config.LoggerConfig, obj: std.json.Value) !void {
        if (obj != .object) return;
        
        if (obj.object.get("max_log_size_mb")) |val| {
            if (val == .integer) {
                logger.max_log_size_mb = @intCast(val.integer);
            }
        }
        
        if (obj.object.get("max_archives")) |val| {
            if (val == .integer) {
                logger.max_archives = @intCast(val.integer);
            }
        }
        
        if (obj.object.get("performance_warn_threshold_ms")) |val| {
            if (val == .integer) {
                logger.performance_warn_threshold_ms = @intCast(val.integer);
            }
        }
        
        if (obj.object.get("log_level")) |val| {
            if (val == .string) {
                const level = try config.parseLogLevel(val.string);
                logger.log_level = try self.allocator.dupe(u8, level);
            }
        }
        
        if (obj.object.get("include_timestamps")) |val| {
            if (val == .bool) {
                logger.include_timestamps = val.bool;
            }
        }
        
        if (obj.object.get("archive_compression")) |val| {
            if (val == .string) {
                if (std.mem.eql(u8, val.string, "none") or std.mem.eql(u8, val.string, "gzip")) {
                    logger.archive_compression = try self.allocator.dupe(u8, val.string);
                }
            }
        }
    }
    
    /// Apply environment variable overrides
    fn applyEnvOverrides(self: *ConfigLoader, tool_config: *config.ToolConfig) !void {
        // Check for log path override
        if (std.process.getEnvVarOwned(self.allocator, "ZIG_TOOLING_LOG_PATH")) |path| {
            if (tool_config.global.log_path) |old_path| {
                self.allocator.free(old_path);
            }
            tool_config.global.log_path = path;
        } else |_| {}
        
        // Check for output format override
        if (std.process.getEnvVarOwned(self.allocator, "ZIG_TOOLING_OUTPUT_FORMAT")) |format| {
            defer self.allocator.free(format);
            if (std.mem.eql(u8, format, "json")) {
                tool_config.global.output_format = "json";
            }
        } else |_| {}
        
        // Check for verbosity override
        if (std.process.getEnvVarOwned(self.allocator, "ZIG_TOOLING_VERBOSITY")) |verb| {
            defer self.allocator.free(verb);
            if (std.fmt.parseInt(u8, verb, 10)) |level| {
                tool_config.global.verbosity = level;
            } else |_| {}
        } else |_| {}
    }
    
    /// Get home directory config path
    fn getHomeConfigPath(self: *ConfigLoader) ![]const u8 {
        const home = std.process.getEnvVarOwned(self.allocator, "HOME") catch {
            return error.FileNotFound;
        };
        defer self.allocator.free(home);
        
        return std.fmt.allocPrint(self.allocator, "{s}/.zig-tooling/config.json", .{home});
    }
    
    /// Create a default configuration file
    pub fn createDefaultConfig(self: *ConfigLoader, path: []const u8) !void {
        _ = self;
        const default_config =
            \\{
            \\  "global": {
            \\    "log_path": "logs/app.log",
            \\    "output_format": "text",
            \\    "color_output": true,
            \\    "verbosity": 1
            \\  },
            \\  "memory_checker": {
            \\    "analyze_tests": false,
            \\    "max_file_size": 10485760,
            \\    "severity_levels": {
            \\      "missing_defer": "error",
            \\      "missing_errdefer": "warning",
            \\      "allocation_no_free": "error",
            \\      "ownership_transfer": "info"
            \\    }
            \\  },
            \\  "testing_compliance": {
            \\    "test_naming_strict": true,
            \\    "test_file_prefix": "test_",
            \\    "require_test_category": true
            \\  },
            \\  "logger": {
            \\    "max_log_size_mb": 10,
            \\    "max_archives": 5,
            \\    "performance_warn_threshold_ms": 1000,
            \\    "log_level": "info",
            \\    "include_timestamps": true,
            \\    "archive_compression": "none"
            \\  }
            \\}
        ;
        
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        
        try file.writeAll(default_config);
    }
    
    /// Validate a configuration file
    pub fn validateConfig(self: *ConfigLoader, path: []const u8) !void {
        var tool_config = config.ToolConfig.init(self.allocator);
        defer tool_config.deinit();
        
        try self.loadFromFile(&tool_config, path);
        // If we get here without errors, the config is valid
    }
};