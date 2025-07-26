# Zig Tooling Library Usage Flow

This document provides visual flow charts showing how to integrate and use the Zig Tooling library in your projects.

## Integration Flow

```mermaid
flowchart TD
    Start([New Zig Project]) --> AddDep[Add to build.zig.zon]
    AddDep --> FetchHash[zig fetch --save]
    FetchHash --> ImportModule[Import in build.zig]
    ImportModule --> ChooseUsage{Choose Usage Pattern}
    
    ChooseUsage --> DirectAPI[Direct API Usage]
    ChooseUsage --> BuildStep[Build System Integration]
    ChooseUsage --> CustomTool[Custom Analysis Tool]
    
    DirectAPI --> ImportLib[Import zig_tooling]
    BuildStep --> CreateStep[Create Build Step]
    CustomTool --> CreateExe[Create Executable]
    
    ImportLib --> UseAPI[Use Analysis Functions]
    CreateStep --> AddCheck[Add to Build Pipeline]
    CreateExe --> CompileTool[Compile Tool]
    
    UseAPI --> Results[Get Analysis Results]
    AddCheck --> Results
    CompileTool --> Results
```

## Analysis Type Selection

```mermaid
flowchart TD
    Start([Choose Analysis Type]) --> Input{Input Type?}
    
    Input --> File[File Path]
    Input --> Source[Source Code]
    
    File --> FileAnalysis{Analysis Scope?}
    Source --> SourceAnalysis{Analysis Scope?}
    
    FileAnalysis --> BothFile[Both Analyzers]
    FileAnalysis --> MemFile[Memory Only]
    FileAnalysis --> TestFile[Tests Only]
    
    SourceAnalysis --> BothSource[Both Analyzers]
    SourceAnalysis --> MemSource[Memory Only]
    SourceAnalysis --> TestSource[Tests Only]
    
    BothFile --> analyzeFile[analyzeFile]
    MemFile --> analyzeMemoryFile[analyzeFile → analyzeMemory]
    TestFile --> analyzeTestsFile[analyzeFile → analyzeTests]
    
    BothSource --> analyzeSource[analyzeSource]
    MemSource --> analyzeMemory[analyzeMemory]
    TestSource --> analyzeTests[analyzeTests]
    
    analyzeFile --> ProcessResult
    analyzeMemoryFile --> ProcessResult
    analyzeTestsFile --> ProcessResult
    analyzeSource --> ProcessResult
    analyzeMemory --> ProcessResult
    analyzeTests --> ProcessResult[Process Results]
```

## Data Flow

```mermaid
flowchart LR
    subgraph Input
        SourceCode[Source Code]
        FilePath[File Path]
        Config[Configuration]
    end
    
    subgraph Library["Zig Tooling Library"]
        subgraph Analyzers
            MemAnalyzer[Memory Analyzer]
            TestAnalyzer[Testing Analyzer]
        end
        
        subgraph Core
            ScopeTracker[Scope Tracker]
            SourceContext[Source Context]
        end
        
        Analyzers --> Core
    end
    
    subgraph Output
        Result[AnalysisResult]
        Issues[Issues Array]
        Metadata[Analysis Metadata]
    end
    
    Input --> Library
    Library --> Output
    
    Result --> Issues
    Result --> Metadata
```

## Configuration Options

```mermaid
flowchart TD
    Config[Config Structure] --> Memory[Memory Config]
    Config --> Testing[Testing Config]
    Config --> Patterns[Pattern Config]
    Config --> Options[Analysis Options]
    
    Memory --> check_defer[check_defer: bool]
    Memory --> check_arena[check_arena_usage: bool]
    Memory --> check_allocator[check_allocator_usage: bool]
    Memory --> check_ownership[check_ownership_transfer: bool]
    Memory --> allowed_alloc[allowed_allocators: []const u8]
    
    Testing --> enforce_cat[enforce_categories: bool]
    Testing --> enforce_name[enforce_naming: bool]
    Testing --> allowed_cat[allowed_categories: []const u8]
    Testing --> test_suffix[test_file_suffix: []const u8]
    
    Patterns --> include[include_patterns: []const u8]
    Patterns --> exclude[exclude_patterns: []const u8]
    
    Options --> max_issues[max_issues: ?u32]
    Options --> fail_warn[fail_on_warnings: bool]
    Options --> verbose[verbose: bool]
```

## Error Handling Flow

```mermaid
flowchart TD
    Analysis[Start Analysis] --> Try{Try Analysis}
    
    Try --> Success[Success]
    Try --> Error[Error]
    
    Error --> ErrorType{Error Type}
    
    ErrorType --> FileNotFound[FileNotFound]
    ErrorType --> AccessDenied[AccessDenied]
    ErrorType --> OutOfMemory[OutOfMemory]
    ErrorType --> ParseError[ParseError]
    ErrorType --> InvalidConfig[InvalidConfiguration]
    
    FileNotFound --> HandleFile[Check file exists]
    AccessDenied --> HandleAccess[Check permissions]
    OutOfMemory --> HandleMem[Increase memory/reduce scope]
    ParseError --> HandleParse[Check source syntax]
    InvalidConfig --> HandleConfig[Validate configuration]
    
    Success --> ProcessResults[Process Results]
    ProcessResults --> CheckSeverity{Check Severity}
    
    CheckSeverity --> HasErrors[Has Errors]
    CheckSeverity --> HasWarnings[Has Warnings]
    CheckSeverity --> Clean[No Issues]
    
    HasErrors --> FailBuild[Fail Build/Exit]
    HasWarnings --> WarnDecision{fail_on_warnings?}
    WarnDecision --> |Yes| FailBuild
    WarnDecision --> |No| Continue[Continue]
    Clean --> Continue
```

## Build Integration Example

```mermaid
flowchart TD
    BuildStart[build.zig] --> AddDep[Add Dependency]
    AddDep --> CreateTool[Create Check Tool]
    
    CreateTool --> AddImport[Add zig_tooling Import]
    AddImport --> CreateStep[Create Build Step]
    
    CreateStep --> Normal[Normal Build]
    CreateStep --> Check[Check Step]
    
    Check --> RunAnalysis[Run Analysis]
    RunAnalysis --> Issues{Found Issues?}
    
    Issues --> |Yes| ShowIssues[Display Issues]
    Issues --> |No| Success[Build Success]
    
    ShowIssues --> FailOnError{Has Errors?}
    FailOnError --> |Yes| BuildFail[Build Failed]
    FailOnError --> |No| BuildWarn[Build with Warnings]
    
    Normal --> Compile[Compile Project]
    Success --> Compile
    BuildWarn --> Compile
```

## Memory Cleanup Pattern

```mermaid
flowchart TD
    Allocate[Allocate for Analysis] --> CallAPI[Call Analysis API]
    CallAPI --> GetResult[Get AnalysisResult]
    
    GetResult --> FreeIssues[Free result.issues array]
    FreeIssues --> IterateIssues[Iterate through issues]
    
    IterateIssues --> FreeFields[Free Issue String Fields]
    FreeFields --> FreePath[Free file_path]
    FreePath --> FreeMsg[Free message]
    FreeMsg --> FreeSugg{Has suggestion?}
    
    FreeSugg --> |Yes| FreeSuggestion[Free suggestion]
    FreeSugg --> |No| NextIssue[Next Issue]
    FreeSuggestion --> NextIssue
    
    NextIssue --> MoreIssues{More Issues?}
    MoreIssues --> |Yes| FreeFields
    MoreIssues --> |No| Complete[Cleanup Complete]
```

## Common Integration Patterns

### 1. Pre-commit Hook Pattern
```mermaid
flowchart LR
    GitCommit[git commit] --> PreCommit[Pre-commit Hook]
    PreCommit --> RunCheck[Run zig_tooling Check]
    RunCheck --> Result{Pass?}
    Result --> |Yes| Commit[Allow Commit]
    Result --> |No| Block[Block Commit]
    Block --> ShowErrors[Show Errors]
```

### 2. CI/CD Integration Pattern
```mermaid
flowchart TD
    Push[Push to Repository] --> CI[CI Pipeline]
    CI --> Checkout[Checkout Code]
    Checkout --> BuildLib[Build with zig_tooling]
    BuildLib --> RunTests[Run Tests]
    RunTests --> RunAnalysis[Run Code Analysis]
    RunAnalysis --> Report{Generate Report}
    Report --> PR[Update PR Status]
    Report --> Artifacts[Store Artifacts]
```

### 3. IDE Integration Pattern
```mermaid
flowchart LR
    Edit[Edit Code] --> Save[Save File]
    Save --> Trigger[Trigger Analysis]
    Trigger --> Analyze[zig_tooling.analyzeFile]
    Analyze --> Display[Display Issues]
    Display --> Inline[Show Inline]
    Display --> Panel[Problems Panel]
```

## Usage Examples

### Basic File Analysis
```zig
const zig_tooling = @import("zig_tooling");

// Analyze a single file
const result = try zig_tooling.analyzeFile(allocator, "src/main.zig", null);
defer allocator.free(result.issues);
defer for (result.issues) |issue| {
    allocator.free(issue.file_path);
    allocator.free(issue.message);
    if (issue.suggestion) |s| allocator.free(s);
};

if (result.hasErrors()) {
    // Handle errors
}
```

### Custom Configuration
```zig
const config = zig_tooling.Config{
    .memory = .{
        .check_defer = true,
        .check_arena_usage = false, // Disable for this project
    },
    .testing = .{
        .allowed_categories = &.{ "unit", "integration", "benchmark" },
    },
};

const result = try zig_tooling.analyzeFile(allocator, path, config);
```

### Build System Integration
```zig
// In build.zig
const check_step = b.step("check", "Run code quality checks");

// Create a separate executable for checking
const check_exe = b.addExecutable(.{
    .name = "check_code",
    .root_source_file = b.path("tools/check.zig"),
});

// Add the library import
check_exe.root_module.addImport("zig_tooling", zig_tooling.module("zig_tooling"));

const run_check = b.addRunArtifact(check_exe);
check_step.dependOn(&run_check.step);
```