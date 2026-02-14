---
description: Fix Expo when it hangs or won't start (missing @expo/cli)
---

# Fix Expo Start Issues

This workflow fixes the recurring issue where `expo start` hangs silently because `@expo/cli` (or other critical deps) gets corrupted or removed from `node_modules`.

## Automated Safeguard

We have installed a `prestart` hook in `package.json` that runs `scripts/verify-deps.js` before every start. This script:

1. Checks for critical dependencies (expo, @expo/cli, react-native, etc.)
2. Handles nested dependencies correctly (e.g. `@expo/cli` nested inside `expo`)
3. Automatically triggers `npm run reset` (clean reinstall) if corruption is detected
4. Prevents the "silent hang" issue by ensuring the environment is healthy before starting Metro.

If you ever encounter issues, simply running `npm start` should self-heal.

## Manual Fix (Fallback)

If the automated script fails or gets stuck:

1. Run the reset command manually:

```bash
cd /Users/virajrungta/Desktop/ggcode/ggcode/mobile && npm run reset
```

## Root Cause

The `expo` package depends on `@expo/cli` which provides the actual CLI binary. npm sometimes fails to properly install/hoist this nested dependency due to:

- Interrupted installs
- npm cache corruption
- Disk issues during extraction

The `prestart` hook in `package.json` now auto-detects and self-heals this automatically.
