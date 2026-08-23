/**
 * tools/parity/css-assert.mjs
 *
 * A small, deliberately dumb CSS reader used to hold `tokens.spec.mjs`
 * accountable to apps/web/app/globals.css.
 *
 * It is not a CSS parser in any general sense — it walks the stylesheet with a
 * brace counter, tracks the enclosing @media condition, and records every
 * `selector { prop: value }` declaration it sees. That is enough to answer the
 * only question asked of it: "does this exact declaration still exist, with
 * this exact value?"
 *
 * Comments are stripped first; without that, a value mentioned inside a `/ * … * /`
 * explanation (globals.css is heavily commented) would be read as real CSS.
 */

const COMMENT = /\/\*[\s\S]*?\*\//g;

/**
 * @returns {Array<{selector: string, media: string|null, prop: string, value: string}>}
 */
export function readDeclarations(css) {
  const src = css.replace(COMMENT, "");
  const out = [];
  /** @type {string[]} */
  const mediaStack = [];
  let i = 0;
  let head = "";

  while (i < src.length) {
    const ch = src[i];
    if (ch === "{") {
      const selector = head.trim();
      head = "";
      if (selector.startsWith("@media")) {
        mediaStack.push(normaliseMedia(selector));
        i++;
        continue;
      }
      if (selector.startsWith("@")) {
        // @font-face, @keyframes, @supports — skip the whole block.
        i = skipBlock(src, i);
        continue;
      }
      const end = findBlockEnd(src, i);
      const body = src.slice(i + 1, end);
      for (const decl of splitDeclarations(body)) {
        for (const sel of selector.split(",")) {
          out.push({
            selector: sel.trim().replace(/\s+/g, " "),
            media: mediaStack.length ? mediaStack[mediaStack.length - 1] : null,
            prop: decl.prop,
            value: decl.value,
          });
        }
      }
      i = end + 1;
      continue;
    }
    if (ch === "}") {
      mediaStack.pop();
      head = "";
      i++;
      continue;
    }
    head += ch;
    i++;
  }
  return out;
}

function normaliseMedia(atRule) {
  return atRule.replace(/^@media\s*/, "").replace(/\s+/g, " ").trim();
}

/** Index of the `}` that closes the `{` at `open`. */
function findBlockEnd(src, open) {
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}") {
      depth--;
      if (depth === 0) return i;
    }
  }
  return src.length - 1;
}

function skipBlock(src, open) {
  return findBlockEnd(src, open) + 1;
}

/** Declarations only — nested blocks inside the body are ignored. */
function splitDeclarations(body) {
  const out = [];
  let depth = 0;
  let buf = "";
  for (const ch of body) {
    if (ch === "{") depth++;
    if (ch === "}") depth--;
    if (ch === ";" && depth === 0) {
      pushDecl(out, buf);
      buf = "";
      continue;
    }
    if (depth === 0) buf += ch;
  }
  pushDecl(out, buf);
  return out;
}

function pushDecl(out, raw) {
  const s = raw.trim();
  if (!s) return;
  const idx = s.indexOf(":");
  if (idx <= 0) return;
  out.push({
    prop: s.slice(0, idx).trim(),
    value: s
      .slice(idx + 1)
      .replace(/!important/g, "")
      .trim()
      .replace(/\s+/g, " "),
  });
}

/**
 * Check one assertion from tokens.spec.mjs against the parsed stylesheet.
 *
 * `media` is matched by substring so a spec can say `(max-width: 640px)` and
 * still match `only screen and (max-width: 640px)` if the source ever gains a
 * prefix. When a spec omits `media`, declarations from ANY context can satisfy
 * it — the base rule and the media override are both legitimate answers to
 * "does web still say this".
 */
export function checkAssertion(decls, a) {
  const candidates = decls.filter(
    (d) =>
      d.selector === a.selector &&
      d.prop === a.prop &&
      (a.media == null || (d.media != null && d.media.includes(a.media))),
  );
  if (candidates.length === 0) {
    return { ok: false, reason: `no declaration \`${a.selector} { ${a.prop} }\`${a.media ? ` in @media ${a.media}` : ""}` };
  }
  const hit = candidates.find((d) =>
    a.contains != null ? d.value.includes(a.contains) : d.value === a.expect,
  );
  if (hit) return { ok: true };
  return {
    ok: false,
    reason: `\`${a.selector} { ${a.prop} }\` is \`${candidates
      .map((c) => c.value)
      .join(" | ")}\`, spec expects \`${a.contains ?? a.expect}\``,
  };
}

/** Flatten every `assertions` array and every `css` object out of the spec. */
export function collectAssertions(spec) {
  const out = [];
  const walk = (node, path) => {
    if (node == null || typeof node !== "object") return;
    if (Array.isArray(node)) {
      node.forEach((n, i) => walk(n, `${path}[${i}]`));
      return;
    }
    for (const [k, v] of Object.entries(node)) {
      if (k === "assertions" && Array.isArray(v)) {
        v.forEach((a, i) => out.push({ ...a, path: `${path}.assertions[${i}]` }));
      } else if (k === "css" && v && typeof v === "object") {
        out.push({ ...v, path: `${path}.css` });
      } else {
        walk(v, path ? `${path}.${k}` : k);
      }
    }
  };
  walk(spec, "");
  return out;
}
