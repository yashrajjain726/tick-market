import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { resolve, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const source = fileURLToPath(new URL('../src/', import.meta.url));
function* files(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) yield* files(path);
    else if (path.endsWith('.mjs')) yield path;
  }
}

test('domain and application never depend on infrastructure or composition', () => {
  const violations = [];
  for (const file of files(source)) {
    const path = relative(source, file);
    const domain = path.startsWith('features/market/domain/');
    const application = path.startsWith('features/market/application/');
    if (!domain && !application) continue;
    const text = readFileSync(file, 'utf8');
    for (const match of text.matchAll(/\b(?:from\s*|import\s*\(?\s*)['"]([^'"]+)['"]/g)) {
      const target = match[1];
      const local = relative(source, resolve(dirname(file), target));
      const allowed = target.startsWith('.') && (local.startsWith('features/market/domain/') ||
        (application && local.startsWith('features/market/application/')));
      if (!allowed) violations.push(`${path} → ${target}`);
    }
    // Feed clocks, process configuration, sockets and scheduling belong to adapters.
    if (/\b(?:process\.|setInterval\(|setTimeout\(|Date\.now\(|performance\.now\(|JSON\.)/.test(text)) {
      violations.push(`${path} uses an infrastructure global`);
    }
  }
  assert.deepEqual(violations, []);
});
