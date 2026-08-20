import assert from 'node:assert/strict';
import { test } from '../functions/c/[payload].js';

const payload = 'AYH8wS2C-_DBLYL78MEt';
const html = '<html><head><meta name="description" content="A new Flutter project."><title>morse</title></head><body></body></html>';
const request = new Request(`http://localhost:46315/c/${payload}`);

assert.equal(test.previewText('  你好\nMorse  '), '你好 Morse');
assert.equal(test.previewText('a'.repeat(81)), `${'a'.repeat(80)}…`);
const injected = test.injectPreviewMeta(html, request, '... --- ...');
assert.match(injected, /<meta property="og:description" content="\.\.\. --- \.\.\.">/);
assert.match(injected, /<meta property="og:image" content="http:\/\/localhost:46315\/icons\/Icon-512.png">/);
assert.match(injected, /<title>Morse<\/title>/);
assert.doesNotMatch(injected, /A new Flutter project/);

const escaped = test.injectPreviewMeta(html, request, '<SOS & "OK">');
assert.match(escaped, /content="&lt;SOS &amp; &quot;OK&quot;&gt;"/);
