# Plan: Pre-built Sharp Distribution for BotDrop

**Date:** 2026-02-27
**Status:** Completed

## Context

During manual testing, installing sharp+libvips on BotDrop required ~15 manual fixes: missing .pc files, missing symlinks (`ar` -> `llvm-ar`), missing runtime libraries (libarchive, libopenjph), node-gyp Android quirks (`android_ndk_path`, `LD_PRELOAD`), and complex vips.pc dependency chains. No end user should go through this. The solution is to **pre-build the sharp native addon** and distribute it as a `.deb` package alongside the existing libvips dependencies.

## Approach: Pre-built `.node` Binary as a `.deb`

Sharp's loading chain (`lib/sharp.js`) tries `require('@img/sharp-{platform}-{arch}')` before falling back to local builds. On BotDrop, `process.platform` is `'android'` and `process.arch` is `'arm64'`, so it looks for `@img/sharp-android-arm64`. This package doesn't exist upstream.

We will:
1. **Build `sharp.node`** on the BotDrop device itself (via ADB/SSH) using the already-installed libvips + dev tools
2. **Package it as a `.deb`** (`sharp-node-addon`) that installs a fake `@img/sharp-android-arm64` npm package at `$PREFIX/lib/node_modules/@img/sharp-android-arm64/`
3. **End users** just run `apt install sharp-node-addon && npm install sharp --ignore-scripts`

### Why build on-device (not cross-compile)?

Cross-compiling Node.js native addons for Android/aarch64 requires a full Android NDK toolchain + Node.js headers matching the exact device version. Building on-device with the already-working environment is simpler and more reliable. We only need to do this **once** to produce the `.node` binary, then package and distribute it.

## Implementation Steps

### Step 1: Build `sharp.node` on device (one-time, via ADB)

Using the existing ADB connection and installed libvips environment:

```bash
# On device - set up build environment
export LD_PRELOAD=$PREFIX/lib/libtermux-exec.so
export GYP_DEFINES="android_ndk_path=$PREFIX"

# Create a clean build directory
mkdir -p /tmp/sharp-build && cd /tmp/sharp-build
npm init -y
npm install sharp --build-from-source --ignore-scripts

# Or use node-gyp directly on extracted sharp source
# The key output is: sharp.node (the compiled addon)
```

Alternatively, we can just copy the `sharp.node` that was already built during our testing session (it should be in the npm cache or build directory on the device).

### Step 2: Create packaging script

**New file: `botdrop-packages/scripts/package-sharp-addon.sh`**

Takes a pre-built `sharp.node` binary and creates a `.deb` package with this structure:

```
$PREFIX/lib/node_modules/@img/sharp-android-arm64/
|-- package.json    (fake npm package metadata)
|-- lib/
    +-- sharp-android-arm64.node
```

The `package.json` will declare:
```json
{
  "name": "@img/sharp-android-arm64",
  "version": "0.34.5",
  "main": "lib/sharp-android-arm64.node",
  "os": ["android"],
  "cpu": ["arm64"]
}
```

The `.deb` control file:
```
Package: sharp-node-addon
Version: 0.34.5
Architecture: aarch64
Depends: libvips, libglib-2.0-0, libarchive
Description: Pre-built sharp native addon for Node.js on Android/aarch64
```

### Step 3: Fix libvips packaging issues

**File: `botdrop-packages/packages/libvips/build.sh`** (or post-install script)

Address the missing runtime dependencies discovered during testing:
- Add `libarchive` to libvips Depends
- Ensure `libopenjph` is included (or remove OpenEXR JPEG2000 support if not needed)

### Step 4: Add to APT repository

Add the generated `sharp-node-addon_0.34.5_aarch64.deb` to the botdrop-packages output directory so `create-botdrop-repo.sh` includes it in the repository.

### Step 5: Update TermuxInstaller.java install flow

**File: `botdrop-android/app/src/main/java/com/termux/app/TermuxInstaller.java`**

In `createBotDropScripts()` -> `install.sh`, after the environment setup step (step 0), add:

```bash
# Step: Install sharp native addon
apt update -o Dir::Etc::sourcelist="$PREFIX/etc/apt/sources.list.d/botdrop.list" -o Dir::Etc::sourceparts="-" 2>&1
apt install -y sharp-node-addon 2>&1
```

Then in the OpenClaw install step, use `--ignore-scripts` for sharp:

```bash
npm install sharp --ignore-scripts
```

### Step 6: Configure BotDrop APT source in bootstrap

**File: `botdrop-android/app/src/main/java/com/termux/app/TermuxInstaller.java`**

In `install.sh` step 0 (environment setup), add:
```bash
# Add BotDrop APT source
mkdir -p $PREFIX/etc/apt/sources.list.d
echo "deb [trusted=yes] https://zhixianio.github.io/botdrop-packages/ stable main" > $PREFIX/etc/apt/sources.list.d/botdrop.list
```

## Files Created/Modified

| File | Action | Description |
|------|--------|-------------|
| `botdrop-packages/scripts/package-sharp-addon.sh` | **Created** | Script to package sharp.node as .deb |
| `botdrop-packages/scripts/create-botdrop-repo.sh` | Already fixed | bsdtar fix already applied |
| `botdrop-android/app/.../TermuxInstaller.java` | **Modified** | Add apt source config + sharp-node-addon install step |

## Install Flow (Updated)

After these changes, the install.sh steps are:

| Step | Name | Description |
|------|------|-------------|
| 0 | Setting up environment | SSH keys, dirs, sshd, APT source |
| 1 | Verifying Node.js | Check node/npm available |
| 2 | Installing sharp image library | `apt install sharp-node-addon` + `npm install -g sharp --ignore-scripts` |
| 3 | Installing OpenClaw | `npm install -g openclaw` + koffi mock |

## Build Order & Dependencies

`sharp.node` 的编译依赖 libvips，因此整个流程有严格的顺序依赖：

```
Linux Server                        BotDrop Device                     Linux Server
───────────                         ──────────────                     ───────────
1. Build libvips +                  2. apt install libvips             4. package-sharp-addon.sh
   all dependency .debs  ────────>     + dev dependencies  ────────>     sharp.node → .deb
   (build-sharp-packages.sh)           (from APT repo)                   (pull via adb)
                                    3. Build sharp.node on-device
                                       (npm install sharp
                                        --build-from-source)
                                                                       5. Add .deb to repo
                                                                          (create-botdrop-repo.sh)
```

**详细步骤：**

1. **Linux 服务器**：运行 `build-sharp-packages.sh` 构建 libvips 及其 65 个依赖的 .deb 包，然后 `create-botdrop-repo.sh` 生成 APT repo
2. **BotDrop 设备**：通过 APT repo 安装 libvips 及所有依赖（包括 dev 包、.pc 文件、头文件等）
3. **BotDrop 设备**：在设备上编译 `sharp.node`（需要 libvips 的 .so 和头文件）
4. **Linux 服务器**：`adb pull` 拉出编译好的 `sharp.node`，运行 `package-sharp-addon.sh` 打包为 .deb
5. **Linux 服务器**：将 `sharp-node-addon_0.34.5_aarch64.deb` 加入 `debs-output/`，重新跑 `create-botdrop-repo.sh`

> **注意：** `sharp.node` 只需要编译一次。编译完成并打包为 .deb 后，后续用户只需 `apt install sharp-node-addon && npm install sharp --ignore-scripts`，无需在设备上编译。

## Verification

1. **Build sharp.node on device**: ADB into BotDrop, verify the compiled `.node` binary works with `node -e "const sharp = require('sharp'); ..."`
2. **Package as .deb**: Run `package-sharp-addon.sh`, verify .deb contents with `dpkg-deb -c`
3. **Test fresh install flow**: Uninstall sharp + libvips, then install via `apt install sharp-node-addon && npm install sharp --ignore-scripts`, verify sharp works
4. **Test from repo**: Add .deb to repo, serve locally, test `apt update && apt install sharp-node-addon` from clean state
