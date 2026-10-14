# PR #2 review

Reviewed starting head: `4e175188ecd65f12b1121847cb86939b0918d430`.
Review fixes: `9d8ea9eb6adee55d53d1f9775682718f33336b32`.

## Findings addressed

1. **macOS build blocker:** the unguarded Swift `InlineArray` use requires macOS 26, but the package and app target macOS 14. Use `withUnsafeTemporaryAllocation` for the fixed 20-byte number-formatting scratch space. Preserve the decimal signature format and the deployment target.
2. **Wide-directory descriptor exhaustion:** the new measurement traversal opened all pending siblings before descending. Keep only the current directory ancestry open instead, and fail closed at a depth of 128 rather than exhausting process resources on unusually deep trees.
3. **Directory replacement / mount race:** compare `fstat` on every opened directory with the preceding no-follow metadata before descending. Recheck directory metadata after enumeration; a changed or inaccessible tree is incomplete and therefore not cleanup-eligible.
4. **Developer packaging:** never distribute the unsigned Debug test bundle as the app artifact. Build optimized Release arm64, sign nested code inside out with an explicit ad-hoc identity, verify strictly, archive with `ditto`, extract again, verify the extracted bundle, and smoke-launch that exact bundle with synthetic demo data. Record commit/tree/architecture/signature metadata and a SHA-256 checksum.

Six added regression tests cover wide and deep trees, symlink roots, regular files, protected directory names, and hard-linked block accounting. Existing tests and cleanup allowlists are retained.

## Validation and distribution boundary

Native SwiftPM tests, the shared Xcode test plan, Release compilation, package verification, and the synthetic demo launch are required by `.github/workflows/tests.yml`. Refer to the run for the exact tested commit; this document alone does not assert that CI passed.

The artifact is **ad-hoc signed, not Developer ID signed and not notarized**. Its internal signature and ZIP integrity do not establish an Apple-verified publisher or guarantee Gatekeeper acceptance. No global security setting or quarantine attribute is changed by the packaging script. Public distribution still requires the owner's Developer ID signing identity and Apple notarization.

The smoke check verifies a live full-size window owned by the packaged app's process. It is not a substitute for manual dragging, undo/redo, row-height scrolling, read-only browsing, or disposable-data cleanup/restore testing on a Mac.
