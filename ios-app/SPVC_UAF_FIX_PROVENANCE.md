# 26.4 SPIR-V Use-After-Free — Root Fix (Class-Set Source) and Delivery

> Device: iPhone 17 Pro / iOS 27.2 / instance 26.4-snapshot-2 / Metal backend.
> Symptom: During the first compilation of the UI pipeline `minecraft:pipeline/gui`,
> `com.mojang.renderpearl.util.ShaderCompileException: SPIRV-Cross error at spvc_context_parse_spirv: -1`。
> The previous round (`tree510@7a6b5129b`, `★ [SPVC-PATH]`) added only a native-side "snapshot ring + in-place restore" fallback; **this round fixes the root cause in the Java/class-set source**.
> Delivered: `tree510`'s `JavaApp/libs/others/metallum_agent.jar` (replaced only 9 entries under `classes264/**`; every other byte is unchanged).

## 1. Root Cause (Lifecycle Timeline and Source Locations)

Call chain (26.4 renderpearl frontend → Metal backend):

```
PipelineBuilder.compilePipeline(RenderPipeline, ShaderSource)            (com.mojang.blaze3d.pipeline)
  1) generateBackendCreateInfo(...)
       · compiler.compileToSpv(...)              → memAlloc'd ByteBuffer (GLSL→SPIR-V, glslang)
       · device.createSpvModule(name, spv, type, "main")  → new SPIRVModule(name, spv, ...)
         (MetalDevice.createSpvModule delegates directly to SPIRVModule)
       · module.reflect()  ← first and second spvc_context_parse_spirv calls (reflection; buffer is still alive)
       · added to CreateInfo(List<SpvModule>)
  2) device.compilePipeline(createInfo)          → FrontendGpuDevice → MetalDevice.compilePipeline
       · MetalDevice returns a deferred Pending (actual parsing occurs in finishCompile())
  3) createInfo.shaders().forEach(SpvModule::close)   ← ★★ Free point
       · SPIRVModule.close() = { MemoryUtil.memFree(this.spv); spvc_context_destroy(...); }
  ...
  4) Later, the frontend calls Pending.finishCompile()
       · MetalDevice$2.finishCompile → MetalCrossShaderCompiler.compile(device, info)
       · spirvToMsl(vertexSpirv.spv(), …)  ← third spvc_context_parse_spirv call
         ⇒ reads heap memory already freed in step 3 = use-after-free
```

On-device evidence: `parse#3` and `parse#1` have the same length (503 words) and match byte-for-byte from the sixth word onward. Only the **first 16 bytes** differ
(`66297a96 e3a84b13 00000180 …`), matching the **libmalloc free-list header** ⇒ the buffer had been freed but not yet reused.
(The previous `_SPVC_PATH_FIX.md` attributed the free point to `IntermediaryShaderModule`/`MetalDevice.shaderCache`; that is the **26.2/26.3 code path**. In 26.4 it was replaced by `CreateInfo`/`SpvModule`, so that attribution does not apply; see §5.)

Key locations:
- Free point: Step 3 of `com/mojang/blaze3d/pipeline/PipelineBuilder.compilePipeline` (after `device.compilePipeline` returns).
- Read-after-free point: `MetalCrossShaderCompiler.spirvToMsl(vertexSpirv.spv(), …)` (lines 83/99 in `_mc264src`).
- Ownership boundary: **The backend may use `CreateInfo.shaders()` only during the `compilePipeline(info)` call.**

## 2. Fix (Option (c): Copy + Lifecycle Contract)

Changes were made in the **26.4 class-set source `D:\CTF\_mc264src\java`** (a copy of `metaluni/mu263` plus eight `// ★ [MC264]` porting patches; `classes264` is built from it), marked with `// ★ [SPVC-UAF-FIX]`:

1. `MetalDevice.compilePipeline(CreateInfo)` (while the module is **still alive**):
   - `SpvSnapshot.take(info)` makes a **byte-for-byte copy** of each `SpvModule`'s `spv()`
     (`MemoryUtil.memAlloc(n)` + `dup.order()` + `put` + `flip`, preserving `[position,limit)` and byte order).
   - `MetalDevice` owns the copy and **releases it once** when `finishCompile()` ends (idempotently).
   - `close()` calls `releaseAllSpvSnapshots()` as a fallback to drain snapshots left by a Pending that never reaches `finishCompile()`; the collection is naturally bounded.
2. `MetalCrossShaderCompiler.compile(MetalDevice, CreateInfo, Map<ShaderType,ByteBuffer> ownedSpirv)`:
   - When `ownedSpirv != null`, **never** read `SpvModule.spv()` again (the contract is encoded in the signature and comments).
   - A missing entry means that stage is genuinely absent → return null (the old behavior); do not fall back to reading a freed module.
3. The copy is byte-for-byte identical, so content is unchanged; its lifetime is extended only through `finishCompile()`, with no leak.

Why not choose only (a) or (b):
- Only (a), "copy inside `MetalCrossShaderCompiler.compile`," is **too late**: by then `finishCompile` has already read freed memory, so the copy would contain corrupted bytes (the first 16 bytes are already free-list metadata). The copy must be made during `compilePipeline`, while the module is alive.
- Only (b), "extend the lifetime," means the backend would retain/read the frontend buffer and assume the frontend does not close it. The frontend **always** closes it (it treats `SpvModule` as a method-scoped resource), so the contract cannot hold without changing the frontend.
- (c) does both: copy to fix the bug and a signature/contract to prevent regression.

## 3. Rebuild and Extracted-JAR Verification (Run Locally)

Source: `D:\CTF\_mc264src\java` (156 sources) → JDK 25 `javac` (`client-26.4.jar` + `_b261_stub` + `_mc211/libs`)
→ `classes264` = 185 project classes + 55 slf4j classes = **240** (239 before; added `MetalDevice$SpvSnapshot`).
Assembly scripts: `D:\CTF\_uafwork\{build_classes264.py,assemble264fix.py}`; merge script: `merge_spvcuaf.py`.

| Check | Result |
|---|---|
| Baseline reproduction (pre-fix source → 184 classes) | **184/184 byte-for-byte identical** to `_mc264out/build` (proves the build is reproducible) |
| Post-fix compilation | 185 classes, 0 errors |
| Difference from old `classes264` | **8 changed + 1 added**; the other 231 entries are byte-for-byte unchanged |
| Residual constant-pool references (7 removed/relocated 26.4 types) | **0** |
| `Harness264` (load+link using the real 26.4 client class loader) | **89/89 LOADED_OK, FAILED=0** |
| Agent JAR merge | `entries 1541 → 1542`; **0 entries changed outside `classes264/**`**; `testzip() OK` |
| Root `com/mojang/blaze3d/` = 0 / `classes264/com/mojang/` = 0 | Unchanged |
| `MetallumAgent.class` routing markers (`classes264`/`is264`/`classSetPresent`/`FIX263-ROUTE`) and `TapUniversal` | Unchanged (agent class was not recompiled) |
| `Natives/check_spvc_provenance.py` | **EXIT=0** |
| New JAR | MD5 `215a521c34552dd987f51ebbf0152604` / 5,661,113 B (**old** `bd6f7a647cf12654c188077d4ac7ac2d` / 5,659,509 B) |

Extracted-JAR verification (re-extracted from the **final assembled** JAR): `classes264` = 240. `javap` confirms that
`MetalDevice.compilePipeline(CreateInfo)` calls `SpvSnapshot.take` → `new MetalDevice$2(device,snapshot,info)`,
`copySpv` uses `memAlloc/order/put/flip`, and `MetalDevice$2.finishCompile` calls
`MetalCrossShaderCompiler.compile(MetalDevice,CreateInfo,Map)` and calls `releaseSpvSnapshot` in `finally`.

**Other class sets are unaffected**: `MetalDevice` in `classes263`/`classes262` uses `ShaderSource` and its own `shaderCache` (no `CreateInfo`/`SpvModule` in the constant pool); the backend itself owns the buffers, so this UAF does not occur and no rebuild is needed.

## 4. On-Device Criteria (Next 26.4 Launch)

1. **Must no longer show** `★ [SPVC-PATH] … FREED/CLOBBERED in place … RESTORED from snapshot`
   (If this still appears, the fallback is still intervening and the native code is not loading the new JAR.)
2. The `head8` values in all three `[spvc][26.4-SPVC] parse_spirv input: … head8=[…]` logs **must** start with `07230203`,
   and `rc=0`.
3. 26.4 must pass `preloadUiShader` / `loadCriticalShaders` without throwing `ShaderCompileException`
   (or at least no longer reports `spvc_context_parse_spirv: -1`).
4. Regression: 26.2/26.3 instances still print their respective `prefix='classes262/'`/`'classes263/'`, and the image remains unchanged.

## 5. Not Done / Unverified

- **Not verified on a device** (`libspvc.dylib` in the bundle is an iOS Mach-O and cannot be dlopen'ed on macOS/Windows; there is no host-side spvc on this machine).
  Only the next on-device 26.4 log can confirm this.
- Only `classes264` was rebuilt and replaced in the JAR; **26.2/26.3 class sets, routing logic, native code, launcher, and glass-related files were not touched**.
- Backups: `D:\CTF\_510src\_bak_\spvcuaf_<ts>\metallum_agent.jar.orig` and `classes264.orig`;
  source backups `_mc264src\...\MetalDevice.java._bak_spvcuaf` and `MetalCrossShaderCompiler.java._bak_spvcuaf`
  (compiling them with the modified source can **byte-for-byte** reproduce the pre-fix class set; verified).
- `_mc264out\classes264` was synchronized to the fixed version (offline artifacts match the JAR). **Note**: the `tree264` reference JAR is still pre-fix,
  so the `classes264 vs tree264 ref mismatch=0` assertion in `_mc264merge_scripts\build_mc264_tree510.sh` will report a mismatch for these 9 classes.
  That assertion must be updated to the fixed baseline (the script was not changed in this round).
- Not pushed, merged, or filed as an issue.

---

## Appendix: Reproduction Commands

```bash
python D:/CTF/_uafwork/build_classes264.py D:/CTF/_mc264src/java D:/CTF/_mc264out/files264.txt D:/CTF/_uafwork/out_fix
python D:/CTF/_uafwork/assemble264fix.py    D:/CTF/_uafwork/out_fix D:/CTF/_uafwork/classes264_fix
python D:/CTF/_uafwork/merge_spvcuaf.py \
  D:/CTF/_510src/tree510/JavaApp/libs/others/metallum_agent.jar \
  D:/CTF/_uafwork/classes264_fix D:/CTF/_uafwork/metallum_agent.jar.new
# Rollback
cp D:/CTF/_510src/_bak_/spvcuaf_<ts>/metallum_agent.jar.orig \
   D:/CTF/_510src/tree510/JavaApp/libs/others/metallum_agent.jar
# Source patch (CRLF source; use --binary or git apply)
patch -p0 --binary < D:/CTF/_510src/tree510/patches/26.4-spvc-uaf-fix.diff
```

> Verification: `python D:/CTF/_uafwork/build_classes264.py` produced 184 classes from the **pre-fix source** (= `*.java._bak_spvcuaf`)
> that are byte-for-byte identical to `_mc264out/build` ⇒ the build is reproducible, and the source backup is the pre-fix source.
