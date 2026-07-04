// Patch a cloned Claude.app so its window title carries the profile name
// (e.g. "Claude — Work"), so window-title-based taskbars (like Taskbar) can
// tell instances apart. Injects a tiny main-process hook that keeps each
// window's title suffixed, then repacks app.asar (preserving native unpacked
// binaries) and updates the ElectronAsarIntegrity hash in Info.plist.
//
//   node patch-title.js "/path/to/Claude Work.app" "Work"
//
// Requires @electron/asar (installed alongside this script by setup-claude.sh).
// The caller must re-sign the app bundle afterwards (asar + Info.plist change).
const asar = require('@electron/asar');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');

async function main() {
  const appPath = process.argv[2];
  const profile = process.argv[3];
  if (!appPath || !profile) { console.error('usage: patch-title.js <app> <profile>'); process.exit(1); }
  const res = path.join(appPath, 'Contents/Resources');
  const asarPath = path.join(res, 'app.asar');
  const unpackedPath = asarPath + '.unpacked';

  const listFiles = (d) => fs.existsSync(d)
    ? cp.execSync(`find "${d}" -type f`).toString().trim().split('\n').filter(Boolean).map(s => s.replace(d + '/', '')).sort()
    : [];
  const origUnpacked = listFiles(unpackedPath);

  // 1. extract the whole asar tree
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-asar-'));
  asar.extractAll(asarPath, tmp);

  // 2. inject the title hook at the top of the main entry (idempotent)
  const mainFile = path.join(tmp, '.vite/build/index.pre.js');
  if (!fs.existsSync(mainFile)) throw new Error('main entry not found: ' + mainFile);
  let code = fs.readFileSync(mainFile, 'utf8');
  const marker = '/*__TITLE_PATCH__*/';
  if (!code.includes(marker)) {
    const tag = String(profile).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
    // Non-invasive: a light interval that ensures every open window's title
    // ends with " — <profile>". Overriding BrowserWindow.setTitle breaks
    // Claude's window creation, so we enforce the suffix on a timer instead.
    const snippet = marker +
      ';(function(){try{' +
      'var e=require("electron"),B=e.BrowserWindow;' +
      'var T=" \\u2014 ' + tag + '";' +
      'setInterval(function(){try{(B.getAllWindows()||[]).forEach(function(w){try{' +
      'if(w.isDestroyed())return;var t=w.getTitle()||"";' +
      'if(t.indexOf(T)===-1)w.setTitle((t||"Claude")+T);}catch(_){}});}catch(_){}},700);' +
      '}catch(_){}})();\n';
    code = snippet + code;
    fs.writeFileSync(mainFile, code);
  }

  // 3. repack, keeping the native binaries unpacked exactly as before
  fs.rmSync(asarPath, { force: true });
  fs.rmSync(unpackedPath, { recursive: true, force: true });
  await asar.createPackageWithOptions(tmp, asarPath, { unpack: '**/{*.node,*.dylib,spawn-helper}' });

  // 4. verify the unpacked set is unchanged
  const newUnpacked = listFiles(unpackedPath);
  const missing = origUnpacked.filter(f => !newUnpacked.includes(f));
  if (missing.length) { console.error('MISSING unpacked files after repack:', missing); process.exit(2); }

  // 5. recompute the integrity hash and write it into Info.plist
  const raw = asar.getRawHeader(asarPath);
  const hash = crypto.createHash('sha256').update(raw.headerString).digest('hex');
  const plist = path.join(appPath, 'Contents/Info.plist');
  cp.execSync(`/usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash ${hash}" "${plist}"`);
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`      title patched ("… — ${profile}"); asar integrity hash updated`);
}
main().catch(e => { console.error(e); process.exit(1); });
