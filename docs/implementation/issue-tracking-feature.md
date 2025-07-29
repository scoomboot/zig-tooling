# Issue Tracking Feature Implementation Guide

**Version**: 1.0  
**Date**: 2025-07-29  
**Purpose**: Add issue tracking as a core feature of the zig-tooling library

## Executive Summary

This document outlines the implementation of issue tracking as a first-class feature within the zig-tooling library. Rather than treating issue management as a separate tool, we'll integrate it into the existing analyzer architecture, making it as natural as memory analysis or test compliance checking.

### Vision Statement
> "Make issue tracking just another type of code analysis - leveraging the same pattern matching, configuration, and reporting infrastructure already proven in the zig-tooling ecosystem."

### Key Benefits
- ✅ **Consistency**: Same API patterns as existing analyzers
- ✅ **Leverage**: Reuse proven pattern matching and file parsing code
- ✅ **Integration**: Native build system and CI/CD support
- ✅ **Extensibility**: Programmable issue management beyond simple linking
- ✅ **Dogfooding**: Demonstrate library flexibility beyond Zig code analysis

## Architecture Overview

### Current Architecture (What We Have)
```
zig-tooling/
├── src/
│   ├── memory_analyzer.zig      # Analyzes Zig code for memory issues
│   ├── testing_analyzer.zig     # Analyzes test compliance
│   ├── patterns.zig             # High-level convenience functions
│   ├── formatters.zig           # Output formatting (text, JSON, GitHub Actions)
│   └── types.zig                # Unified types (Issue, Config, etc.)
├── tools/
│   └── quality_check.zig        # CLI tool using the library
└── build.zig                    # Build integration
```

### Proposed Architecture (What We'll Add)
```
zig-tooling/
├── src/
│   ├── memory_analyzer.zig      # [existing]
│   ├── testing_analyzer.zig     # [existing]
│   ├── issue_analyzer.zig       # [NEW] Analyzes markdown/issue files
│   ├── issue_tracker.zig        # [NEW] Issue management API
│   ├── patterns.zig             # [extended] Add issue tracking patterns
│   ├── formatters.zig           # [extended] Add issue report formats
│   └── types.zig                # [extended] Add issue tracking types
├── tools/
│   ├── quality_check.zig        # [existing]
│   └── issue_manager.zig        # [NEW] CLI for issue operations
├── build.zig                    # [extended] Add issue management steps
└── docs/examples/
    └── issue_tracking_usage.zig  # [NEW] Usage examples
```

## Core Components

### 1. Issue Analyzer (`src/issue_analyzer.zig`)

The core analyzer that treats markdown files as another type of source code to analyze.

**Responsibilities:**
- Parse markdown files to extract issue definitions
- Validate issue format consistency
- Detect broken references and links
- Generate statistics and reports
- Follow the same API patterns as `memory_analyzer.zig`

**API Design:**
```zig
pub const IssueAnalyzer = struct {
    allocator: std.mem.Allocator,
    config: IssueConfig,
    issues: std.ArrayList(Issue),
    
    pub fn init(allocator: std.mem.Allocator, config: IssueConfig) IssueAnalyzer;
    pub fn deinit(self: *IssueAnalyzer) void;
    pub fn analyzeFile(self: *IssueAnalyzer, file_path: []const u8) !void;
    pub fn analyzeSource(self: *IssueAnalyzer, source: []const u8, file_path: []const u8) !void;
    pub fn getResults(self: *const IssueAnalyzer) AnalysisResult;
};
```

**Analysis Capabilities:**
- **Link Validation**: Detect broken internal links (`#LCXXX` → line numbers)
- **Format Consistency**: Ensure uniform issue format across files
- **Priority Distribution**: Analyze priority balance (🔴🟡🟢)
- **Completeness**: Detect missing fields, incomplete descriptions
- **Cross-References**: Validate dependency links between issues
- **Statistics**: Generate metrics (open/closed counts, age analysis, etc.)

### 2. Issue Tracker (`src/issue_tracker.zig`)

High-level API for programmatic issue management operations.

**API Design:**
```zig
pub const IssueTracker = struct {
    allocator: std.mem.Allocator,
    config: IssueTrackerConfig,
    
    pub fn init(allocator: std.mem.Allocator, config: IssueTrackerConfig) IssueTracker;
    pub fn deinit(self: *IssueTracker) void;
    
    // Core operations
    pub fn loadIssues(self: *IssueTracker, file_path: []const u8) ![]IssueEntry;
    pub fn saveIssues(self: *IssueTracker, file_path: []const u8, issues: []const IssueEntry) !void;
    pub fn generateIndex(self: *IssueTracker, issues_file: []const u8, completed_file: []const u8) ![]u8;
    
    // Analysis operations
    pub fn validateLinks(self: *IssueTracker, index_content: []const u8) ![]LinkValidationError;
    pub fn findBrokenReferences(self: *IssueTracker) ![]BrokenReference;
    pub fn generateStatistics(self: *IssueTracker) !IssueStatistics;
    
    // Management operations
    pub fn moveIssueToCompleted(self: *IssueTracker, issue_id: []const u8) !void;
    pub fn updateIssuePriority(self: *IssueTracker, issue_id: []const u8, priority: Priority) !void;
    pub fn addCrossReference(self: *IssueTracker, from_issue: []const u8, to_issue: []const u8) !void;
};
```

### 3. Extended Types (`src/types.zig`)

Add issue tracking types to the existing unified type system.

```zig
// Issue tracking specific types
pub const IssueConfig = struct {
    // File paths
    issues_file: []const u8 = "ISSUES.md",
    completed_file: []const u8 = "00_completed_issues.md", 
    index_file: []const u8 = "00_index.md",
    
    // Validation settings
    validate_links: bool = true,
    validate_format: bool = true,
    enforce_dependencies: bool = true,
    
    // Link validation
    allow_external_links: bool = true,
    check_line_numbers: bool = true,
    
    // Index generation
    auto_sort_by_priority: bool = true,
    group_by_component: bool = false,
    include_statistics: bool = true,
};

pub const IssueEntry = struct {
    id: []const u8,              // e.g., "LC076" 
    title: []const u8,           // e.g., "Add build validation for tools/"
    component: ?[]const u8,      // e.g., "build.zig, tools/"
    priority: Priority,          // High, Medium, Low
    status: IssueStatus,         // Open, InProgress, Completed
    created: []const u8,         // Date string
    dependencies: [][]const u8,  // Other issue IDs
    line_number: u32,           // Line number in source file
    description: []const u8,     // Full description
};

pub const Priority = enum { high, medium, low };
pub const IssueStatus = enum { open, in_progress, completed };

pub const LinkValidationError = struct {
    issue_id: []const u8,
    target_file: []const u8,
    expected_line: u32,
    actual_line: ?u32,
    error_type: LinkErrorType,
};

pub const LinkErrorType = enum {
    file_not_found,
    line_mismatch,
    issue_not_found,
    invalid_format,
};

pub const IssueStatistics = struct {
    total_issues: u32,
    open_issues: u32,
    completed_issues: u32,
    high_priority: u32,
    medium_priority: u32,
    low_priority: u32,
    avg_completion_time_days: f64,
    most_common_components: []ComponentStats,
};
```

### 4. Extended Patterns API (`src/patterns.zig`)

Add high-level convenience functions for issue tracking.

```zig
// Add to existing patterns.zig
pub fn checkIssueTracking(
    allocator: std.mem.Allocator,
    project_path: []const u8,
    config: ?IssueConfig,
) !IssueTrackingResult {
    // Analyze all issue-related files in project
    // Validate links, format, dependencies
    // Generate comprehensive report
}

pub fn updateIssueIndex(
    allocator: std.mem.Allocator,  
    project_path: []const u8,
    config: ?IssueConfig,
) !void {
    // Automatically regenerate index with correct links
    // Update statistics
    // Maintain formatting consistency
}

pub const IssueTrackingResult = struct {
    issues_analyzed: u32,
    links_validated: u32,
    broken_links: []LinkValidationError,
    format_issues: []FormatIssue,
    statistics: IssueStatistics,
    suggestions: [][]const u8,
};
```

### 5. Extended Formatters (`src/formatters.zig`)

Add issue tracking output formats to existing formatter system.

```zig
// Add to existing formatters.zig
pub fn formatIssueTrackingAsText(
    allocator: std.mem.Allocator,
    result: IssueTrackingResult,
    options: FormatOptions,
) ![]u8;

pub fn formatIssueTrackingAsJson(
    allocator: std.mem.Allocator,
    result: IssueTrackingResult,
    options: FormatOptions,
) ![]u8;

pub fn formatIssueIndexAsMarkdown(
    allocator: std.mem.Allocator,
    issues: []const IssueEntry,
    completed: []const IssueEntry,
    config: IssueConfig,
) ![]u8;
```

### 6. CLI Tool (`tools/issue_manager.zig`)

Command-line interface for issue management operations.

```zig
const std = @import("std");
const zig_tooling = @import("zig_tooling");

const Command = enum {
    validate,       // Validate links and format
    update_index,   // Regenerate index
    statistics,     // Generate statistics report
    move_completed, // Move issue to completed
    add_reference,  // Add cross-reference
    help,
};

pub fn main() !void {
    // Command-line argument parsing
    // Route to appropriate operations
    // Use zig_tooling.IssueTracker API
}

// Example commands:
// zig build issue-manager -- validate
// zig build issue-manager -- update-index
// zig build issue-manager -- move-completed LC076
// zig build issue-manager -- statistics --format json
```

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1)
**Goal**: Basic issue parsing and validation

**Tasks**:
1. **Create `IssueAnalyzer` skeleton**
   - Basic markdown parsing using existing pattern matching
   - Issue extraction with regex patterns
   - Follow existing analyzer API patterns

2. **Add issue tracking types to `types.zig`**
   - Define `IssueEntry`, `IssueConfig`, etc.
   - Integrate with existing `AnalysisResult` system

3. **Implement basic link validation**
   - Parse `#LCXXX` references  
   - Validate line number accuracy
   - Report broken links

4. **Create basic tests**
   - Unit tests for issue parsing
   - Link validation tests
   - Integration with existing test infrastructure

**Success Criteria**:
- Can parse existing `ISSUES.md` and `00_completed_issues.md`
- Can detect broken links in `00_index.md`
- Tests pass with existing CI infrastructure

### Phase 2: Issue Tracker API (Week 2)
**Goal**: High-level programmatic issue management

**Tasks**:
1. **Implement `IssueTracker` class**
   - Load/save operations for issue files
   - Index generation algorithm
   - Statistics calculation

2. **Add to patterns API**
   - `checkIssueTracking()` function
   - `updateIssueIndex()` function
   - Integration with existing project analysis

3. **Extend formatters**
   - Text output for issue validation results
   - JSON format for CI integration
   - Markdown generation for index updates

4. **Create comprehensive tests**
   - API functionality tests
   - End-to-end workflow tests
   - Performance tests for large issue sets

**Success Criteria**:
- Can automatically regenerate `00_index.md` with correct links
- API integration matches existing analyzer patterns
- Performance acceptable for 100+ issues

### Phase 3: CLI Tool & Build Integration (Week 3)
**Goal**: User-friendly tools and build system integration

**Tasks**:
1. **Create `tools/issue_manager.zig`**
   - Command-line interface
   - Integration with existing argument parsing patterns
   - User-friendly error messages

2. **Extend `build.zig`**
   - Add issue management build steps
   - Integration with existing quality checks
   - Pre-commit hook support

3. **Documentation and examples**
   - Usage examples in `docs/examples/`
   - Integration guide
   - Migration guide for existing projects

4. **Dogfooding integration**
   - Use issue tracking on zig-tooling itself
   - Add to existing `zig build dogfood` workflow
   - Validate with real-world usage

**Success Criteria**:
- `zig build update-index` works seamlessly
- Integration with existing quality workflows
- Documentation complete and accurate

### Phase 4: Advanced Features (Week 4)
**Goal**: Polish and advanced capabilities

**Tasks**:
1. **Enhanced analysis capabilities**
   - Issue age tracking
   - Dependency cycle detection
   - Priority distribution analysis
   - Component-based grouping

2. **Automation features**
   - Auto-detection of completed issues (by external tools)
   - Smart priority assignment
   - Bulk operations support

3. **CI/CD integration**
   - GitHub Actions integration
   - Automated issue index updates
   - Pull request validation

4. **Performance optimization**
   - Large issue set handling
   - Incremental updates
   - Caching for repeated operations

**Success Criteria**:
- Handles 1000+ issues efficiently
- CI integration working smoothly
- Advanced features documented and tested

## Integration Points

### 1. Build System Integration (`build.zig`)

```zig
// Add to existing build.zig
pub fn build(b: *std.Build) void {
    // ... existing code ...
    
    // Issue management tools
    const issue_manager_exe = b.addExecutable(.{
        .name = "issue_manager",
        .root_source_file = b.path("tools/issue_manager.zig"),
        .target = target,
        .optimize = optimize,
    });
    issue_manager_exe.root_module.addImport("zig_tooling", zig_tooling_module);
    
    // Issue management steps
    const validate_issues_step = b.step("validate-issues", "Validate issue tracking");
    const run_validate = b.addRunArtifact(issue_manager_exe);
    run_validate.addArg("validate");
    validate_issues_step.dependOn(&run_validate.step);
    
    const update_index_step = b.step("update-index", "Update issue index");
    const run_update = b.addRunArtifact(issue_manager_exe);
    run_update.addArg("update-index");
    update_index_step.dependOn(&run_update.step);
    
    // Integration with existing quality checks
    const quality_step = b.step("quality", "Run all quality checks");
    quality_step.dependOn(validate_issues_step);  // Add to existing checks
    
    // Add to dogfood workflow
    const dogfood_step = b.step("dogfood", "Self-analysis including issues");
    dogfood_step.dependOn(&run_validate.step);
}
```

### 2. Quality Check Integration (`tools/quality_check.zig`)

```zig
// Extend existing quality_check.zig
pub fn main() !void {
    // ... existing code ...
    
    // Add issue tracking to quality checks
    if (check_mode == .all or check_mode == .issues) {
        const issue_result = try zig_tooling.patterns.checkIssueTracking(
            allocator,
            ".",
            null,
        );
        defer zig_tooling.patterns.freeIssueTrackingResult(allocator, issue_result);
        
        // Format and display results
        const issue_output = try zig_tooling.formatters.formatIssueTrackingAsText(
            allocator,
            issue_result,
            format_options,
        );
        defer allocator.free(issue_output);
        
        try stdout.writeAll(issue_output);
        
        if (issue_result.broken_links.len > 0 and fail_on_warnings) {
            std.process.exit(1);
        }
    }
}
```

### 3. CI/CD Integration

**GitHub Actions** (`.github/workflows/issues.yml`):
```yaml
name: Issue Tracking Validation

on:
  push:
    paths: ['**.md', 'ISSUES.md', '00_*.md']
  pull_request:
    paths: ['**.md', 'ISSUES.md', '00_*.md']

jobs:
  validate-issues:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: mlugg/setup-zig@v1
      with:
        version: 0.14.1
    
    - name: Validate issue tracking
      run: zig build validate-issues
    
    - name: Check if index needs updating
      run: |
        zig build update-index
        if ! git diff --quiet; then
          echo "Issue index is out of date. Run 'zig build update-index' locally."
          exit 1
        fi
```

### 4. Pre-commit Hook Integration

```bash
#!/bin/sh
# .git/hooks/pre-commit

# Check if any issue-related files changed
if git diff --cached --name-only | grep -E '\.(md)$|ISSUES\.md|00_.*\.md'; then
    echo "Issue-related files changed, validating..."
    
    if ! zig build validate-issues --quiet; then
        echo "Issue validation failed. Please fix issues before committing."
        exit 1
    fi
    
    # Auto-update index if needed
    zig build update-index --quiet
    if ! git diff --quiet; then
        echo "Issue index updated automatically. Please review and re-commit."
        git add 00_index.md
        exit 1
    fi
fi
```

## Usage Examples

### 1. Basic Programmatic Usage

```zig
const std = @import("std");
const zig_tooling = @import("zig_tooling");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Validate issue tracking in current directory
    const result = try zig_tooling.patterns.checkIssueTracking(
        allocator,
        ".",
        null, // Use default config
    );
    defer zig_tooling.patterns.freeIssueTrackingResult(allocator, result);
    
    // Display results
    const output = try zig_tooling.formatters.formatIssueTrackingAsText(
        allocator,
        result,
        .{ .color = true, .verbose = true },
    );
    defer allocator.free(output);
    
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(output);
    
    // Exit with error if issues found
    if (result.broken_links.len > 0) {
        std.process.exit(1);
    }
}
```

### 2. Custom Configuration

```zig
const config = zig_tooling.IssueConfig{
    .issues_file = "docs/ISSUES.md",
    .completed_file = "docs/COMPLETED.md",
    .index_file = "docs/INDEX.md",
    .validate_links = true,
    .validate_format = true,
    .auto_sort_by_priority = false,  // Maintain manual ordering
    .group_by_component = true,      // Group by component in index
};

const result = try zig_tooling.patterns.checkIssueTracking(
    allocator,
    ".",
    config,
);
```

### 3. Index Generation Only

```zig
// Just regenerate the index without full validation
var tracker = zig_tooling.IssueTracker.init(allocator, config);
defer tracker.deinit();

const new_index = try tracker.generateIndex("ISSUES.md", "00_completed_issues.md");
defer allocator.free(new_index);

// Write to file
const file = try std.fs.cwd().createFile("00_index.md", .{});
defer file.close();
try file.writeAll(new_index);
```

### 4. Statistics and Reporting

```zig
const result = try zig_tooling.patterns.checkIssueTracking(allocator, ".", null);
defer zig_tooling.patterns.freeIssueTrackingResult(allocator, result);

const stats = result.statistics;
std.debug.print("Project has {} issues ({} open, {} completed)\n", .{
    stats.total_issues, 
    stats.open_issues, 
    stats.completed_issues,
});

std.debug.print("Priority breakdown: {} high, {} medium, {} low\n", .{
    stats.high_priority,
    stats.medium_priority, 
    stats.low_priority,
});
```

### 5. CLI Tool Usage

```bash
# Validate all issue tracking
zig build issue-manager validate

# Update the index
zig build issue-manager update-index

# Generate statistics
zig build issue-manager statistics --format json > stats.json

# Move an issue to completed
zig build issue-manager move-completed LC076

# Add cross-reference between issues  
zig build issue-manager add-reference LC076 LC060

# Integration with build system
zig build validate-issues   # Validate only
zig build update-index      # Update index only  
zig build quality          # Include issue validation in quality checks
```

## Testing Strategy

### 1. Unit Tests

**Test File**: `tests/test_issue_analyzer.zig`
```zig
test "parse issue from markdown" {
    const source = 
        \\- [ ] #LC076: Add build validation for tools/ directory compilation
        \\  - **Component**: build.zig, tools/
        \\  - **Priority**: Medium
    ;
    
    var analyzer = IssueAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();
    
    try analyzer.analyzeSource(source, "test.md");
    const result = analyzer.getResults();
    
    try testing.expect(result.issues.len == 1);
    try testing.expectEqualStrings("LC076", result.issues[0].id);
    try testing.expect(result.issues[0].priority == .medium);
}

test "detect broken link" {
    const index_content =
        \\- [#LC076](ISSUES.md#L99): Some issue
    ;
    const issues_content =
        \\- [ ] #LC076: Some issue
    ; // Issue is actually at line 1, not 99
    
    // Test link validation logic
    var tracker = IssueTracker.init(testing.allocator, .{});
    defer tracker.deinit();
    
    const errors = try tracker.validateLinks(index_content, issues_content);
    defer testing.allocator.free(errors);
    
    try testing.expect(errors.len == 1);
    try testing.expect(errors[0].error_type == .line_mismatch);
}
```

### 2. Integration Tests

**Test File**: `tests/integration/test_issue_tracking.zig`
```zig
test "end-to-end issue tracking workflow" {
    // Create temporary project structure
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Write test issue files
    try tmp_dir.dir.writeFile(.{
        .sub_path = "ISSUES.md",
        .data = 
            \\- [ ] #LC001: Test issue
            \\  - **Priority**: High
        ,
    });
    
    // Run full analysis
    const result = try zig_tooling.patterns.checkIssueTracking(
        testing.allocator,
        tmp_dir.path,
        null,
    );
    defer zig_tooling.patterns.freeIssueTrackingResult(testing.allocator, result);
    
    // Verify results
    try testing.expect(result.issues_analyzed == 1);
    try testing.expect(result.broken_links.len == 0);
}
```

### 3. Performance Tests

```zig
test "performance with large issue set" {
    // Generate 1000+ test issues
    var issues = std.ArrayList(u8).init(testing.allocator);
    defer issues.deinit();
    
    for (0..1000) |i| {
        try issues.writer().print("- [ ] #LC{:03}: Test issue {}\n", .{i, i});
    }
    
    // Time the analysis
    const start = std.time.milliTimestamp();
    
    var analyzer = IssueAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();
    
    try analyzer.analyzeSource(issues.items, "large_test.md");
    const result = analyzer.getResults();
    
    const duration = std.time.milliTimestamp() - start;
    
    // Should complete in reasonable time (< 1 second)
    try testing.expect(duration < 1000);
    try testing.expect(result.issues.len == 1000);
}
```

### 4. Dogfooding Tests

Run issue tracking on zig-tooling itself:
```bash
# This should pass without errors
zig build validate-issues

# Index should be up to date
zig build update-index
git diff --quiet 00_index.md
```

## Future Extensions

### 1. Advanced Analytics
- **Issue Age Tracking**: Analyze how long issues stay open
- **Velocity Metrics**: Track completion rates over time
- **Component Analysis**: Identify which components have most issues
- **Burndown Charts**: Generate progress visualization data

### 2. External Integrations
- **GitHub Issues Sync**: Two-way sync with GitHub issue tracker
- **JIRA Integration**: Import/export to enterprise issue tracking
- **Slack/Discord Notifications**: Alert on issue status changes
- **Email Reports**: Periodic summary emails

### 3. AI-Powered Features
- **Auto-Categorization**: Use pattern matching to suggest issue categories
- **Duplicate Detection**: Find similar issues automatically  
- **Priority Suggestion**: Analyze issue content to suggest priority
- **Impact Analysis**: Predict which issues affect most code

### 4. Enhanced Workflows
- **Kanban Board Generation**: Export issues to visual board formats
- **Sprint Planning**: Group issues into development sprints
- **Release Planning**: Associate issues with release milestones
- **Time Tracking**: Add time estimation and tracking

### 5. Multi-Project Support
- **Monorepo Support**: Handle multiple projects in one repository
- **Cross-Project Dependencies**: Link issues across different projects
- **Workspace Analytics**: Aggregate statistics across multiple projects
- **Template Management**: Reusable issue templates for different project types

## Migration Plan

### For Existing Users
1. **Phase 1**: Add issue tracking as optional feature (no breaking changes)
2. **Phase 2**: Integrate with existing workflows gradually
3. **Phase 3**: Enable by default in new projects
4. **Phase 4**: Full integration with all zig-tooling features

### For New Users  
1. Start with basic validation and index generation
2. Add to quality checks as comfort level increases
3. Explore advanced features as project grows
4. Contribute patterns and improvements back to library

## Conclusion

Adding issue tracking as a core feature of zig-tooling represents a natural evolution of the library's philosophy: **treating all aspects of software development as analyzable, configurable, and automatable**.

By leveraging the existing pattern matching infrastructure, unified type system, and proven analyzer architecture, we can deliver a robust issue tracking system that feels native to the zig-tooling ecosystem.

The key insight is that **issue tracking is just another form of code analysis** - instead of analyzing Zig syntax for memory safety, we're analyzing markdown syntax for project management consistency.

This implementation will:
- ✅ **Solve the immediate problem** of broken links and manual maintenance
- ✅ **Demonstrate library flexibility** beyond just Zig code analysis  
- ✅ **Provide value** to other projects using zig-tooling
- ✅ **Establish patterns** for future analyzer types
- ✅ **Dogfood the library** in a meaningful way

The result will be a more complete development toolchain that handles both code quality and project management with the same level of automation and precision.

---

**Next Steps:**
1. Review and approve this implementation plan
2. Begin Phase 1 implementation (core infrastructure)
3. Create GitHub issues for tracking development progress
4. Set up project milestones and timeline
5. Begin dogfooding on zig-tooling itself

**Estimated Timeline**: 4 weeks for full implementation  
**Estimated Effort**: ~40 hours of development + testing + documentation