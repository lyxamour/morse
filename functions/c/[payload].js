const latin6 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .';
const textDecoder = new TextDecoder();

function decodePayload(payload) {
  const normalized = payload.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(normalized + '='.repeat((4 - normalized.length % 4) % 4));
  const data = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  if (data.length === 0 || (data[0] & 0x3f) !== 1) {
    throw new Error('未知 payload 版本');
  }

  const parts = [];
  let utf8Pending = [];
  const flushUtf8 = () => {
    if (utf8Pending.length === 0) return;
    parts.push(textDecoder.decode(Uint8Array.from(utf8Pending)));
    utf8Pending = [];
  };

  let pos = 1;
  while (pos < data.length) {
    const tag = data[pos++];
    const type = tag >> 6;
    const count = tag & 0x3f;
    switch (type) {
      case 1:
        flushUtf8();
        for (let i = 0; i < count; i++) {
          if (pos + 1 >= data.length) throw new Error('payload 截断');
          const b1 = data[pos++];
          const b2 = data[pos++];
          parts.push(String.fromCodePoint(parseInt(`${b1 >> 4}${b1 & 0xf}${b2 >> 4}${b2 & 0xf}`, 10)));
        }
        break;
      case 2:
        flushUtf8();
        let acc = 0;
        let bits = 0;
        for (let i = 0; i < count; i++) {
          while (bits < 6) {
            if (pos >= data.length) throw new Error('payload 截断');
            acc = (acc << 8) | data[pos++];
            bits += 8;
          }
          parts.push(latin6[(acc >> (bits - 6)) & 0x3f]);
          acc &= (1 << (bits - 6)) - 1;
          bits -= 6;
        }
        break;
      default:
        if (pos + count > data.length) throw new Error('payload 截断');
        utf8Pending.push(...data.slice(pos, pos + count));
        pos += count;
    }
  }
  flushUtf8();
  return parts.join('');
}

function escapeHtml(value) {
  return value.replace(/[&<>"]/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
  })[char]);
}

function previewText(text) {
  const collapsed = text.replace(/\s+/g, ' ').trim();
  if (collapsed.length <= 80) return collapsed;
  return `${collapsed.slice(0, 80)}…`;
}

function injectPreviewMeta(html, request, text) {
  const url = new URL(request.url);
  const escapedUrl = escapeHtml(url.href);
  const title = 'Morse';
  const description = previewText(text) || '打开 Morse 分享内容';
  const escapedDescription = escapeHtml(description);
  const meta = `
  <meta name="description" content="${escapedDescription}">
  <meta property="og:type" content="website">
  <meta property="og:title" content="${title}">
  <meta property="og:description" content="${escapedDescription}">
  <meta property="og:image" content="${url.origin}/icons/Icon-512.png">
  <meta property="og:url" content="${escapedUrl}">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="${title}">
  <meta name="twitter:description" content="${escapedDescription}">`;
  return html
    .replace(/\s*<meta name="description" content="[^"]*">/, meta)
    .replace(/<title>[^<]*<\/title>/, `<title>${title}</title>`);
}

export async function onRequest(context) {
  const response = await context.env.ASSETS.fetch(context.request);
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.includes('text/html')) return response;

  const payload = context.params.payload;
  let text;
  try {
    text = decodePayload(payload);
  } catch (_) {
    return response;
  }

  const headers = new Headers(response.headers);
  headers.set('content-type', 'text/html; charset=UTF-8');
  headers.set('cache-control', 'no-store');
  return new Response(injectPreviewMeta(await response.text(), context.request, text), {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export const test = { decodePayload, escapeHtml, injectPreviewMeta, previewText };
