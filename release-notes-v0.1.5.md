# v0.1.5 - Critical Memory Leak Fix

## 🚨 Critical Fix

This release fixes a **critical use-after-free bug** in the memory analyzer that could cause memory corruption and segmentation faults when using `GeneralPurposeAllocator`.

### Bug Details
- **Location**: `memory_analyzer.validateAllocatorChoice()` ([src/memory_analyzer.zig:794](src/memory_analyzer.zig#L794))
- **Issue**: String was freed with `defer` while still being referenced in a HashMap
- **Impact**: Caused segfaults and memory corruption with GPA
- **Reported**: GitHub Issue #4

### Technical Details
The bug occurred when validating allocator choices - a string was being freed within a defer statement inside a loop, but the same string was still being used as a key in a HashMap. This created a use-after-free condition that corrupted memory when using certain allocators.

## 🔧 What's Fixed

- Fixed use-after-free bug by properly managing string ownership in HashMap operations
- Resolved memory corruption issues when using GeneralPurposeAllocator
- Eliminated ~18 memory leaks per analysis run

## 📦 Upgrading

If you're using zig-tooling as a dependency, update your `build.zig.zon`:

```zig
.dependencies = .{
    .zig_tooling = .{
        .url = "https://github.com/scoomboot/zig-tooling/archive/refs/tags/v0.1.5.tar.gz",
        .hash = "...", // Use `zig fetch` to get the hash
    },
},
```

## 🙏 Thanks

Special thanks to the reporter of Issue #4 for identifying this critical bug and providing the reproduction case.

---

**Full Changelog**: https://github.com/scoomboot/zig-tooling/compare/v0.1.4...v0.1.5