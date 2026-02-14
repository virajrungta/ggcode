#!/usr/bin/env node

/**
 * verify-deps.js
 * 
 * Pre-start dependency verification script.
 * Checks that all critical Expo dependencies are properly installed
 * before launching the dev server. If anything is missing, it 
 * automatically triggers a clean reinstall.
 * 
 * This prevents the silent-hang issue caused by @expo/cli being
 * missing from node_modules (npm hoisting/corruption bug).
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');

// Critical packages that MUST be resolvable for Expo to work.
// These are the ones most prone to disappearing due to npm hoisting issues.
const CRITICAL_DEPS = [
  'expo',
  '@expo/cli',
  '@expo/metro-config',
  '@expo/metro-runtime',
  'react',
  'react-native',
  'metro',
];

function checkDependency(dep) {
  try {
    // 1. Try standard resolution
    require.resolve(dep, { paths: [ROOT] });
    return true;
  } catch (e) {
    // 2. Fallback: Check for nested dependencies (common with expo -> @expo/cli)
    // If 'dep' is @expo/cli, it might be inside node_modules/expo/node_modules
    if (dep === '@expo/cli') {
      const nestedPath = path.join(ROOT, 'node_modules', 'expo', 'node_modules', '@expo', 'cli', 'package.json');
      if (fs.existsSync(nestedPath)) {
        return true;
      }
    }
    return false;
  }
}

function main() {
  console.log('\x1b[36m⚙  Verifying critical dependencies...\x1b[0m');

  const missing = CRITICAL_DEPS.filter(dep => !checkDependency(dep));

  if (missing.length === 0) {
    console.log('\x1b[32m✓  All critical dependencies verified.\x1b[0m\n');
    return;
  }

  console.log('\x1b[33m⚠  Missing critical dependencies:\x1b[0m');
  missing.forEach(dep => console.log(`   \x1b[31m✗ ${dep}\x1b[0m`));
  console.log('');
  console.log('\x1b[36m⟳  Auto-healing: running clean reinstall...\x1b[0m');

  try {
    // Remove node_modules and reinstall
    execSync('rm -rf node_modules', { cwd: ROOT, stdio: 'inherit' });
    execSync('npm ci', { cwd: ROOT, stdio: 'inherit' });
  } catch {
    console.error('\x1b[31m✗  npm ci failed. Falling back to npm install...\x1b[0m');
    try {
      execSync('npm install', { cwd: ROOT, stdio: 'inherit' });
    } catch (e2) {
      console.error('\x1b[31m✗  npm install also failed. Please check your network and try manually.\x1b[0m');
      process.exit(1);
    }
  }

  // Re-verify after reinstall
  const stillMissing = CRITICAL_DEPS.filter(dep => !checkDependency(dep));
  if (stillMissing.length > 0) {
    console.error('\x1b[31m✗  Dependencies still missing after reinstall:\x1b[0m');
    stillMissing.forEach(dep => console.log(`   \x1b[31m✗ ${dep}\x1b[0m`));
    console.error('\x1b[31m   This may indicate a deeper compatibility issue.\x1b[0m');
    process.exit(1);
  }

  console.log('\x1b[32m✓  All dependencies restored successfully.\x1b[0m\n');
}

main();
