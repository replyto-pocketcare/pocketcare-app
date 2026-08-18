"use client";

/**
 * Minimal .xlsx reader — enough to turn a broker export into rows of strings.
 *
 * Why not SheetJS: this app is an offline-first PWA where every kilobyte ships
 * to a phone, and the full library is ~1.5 MB to read a handful of cells from
 * a two-column spreadsheet. An .xlsx is just a ZIP of XML, and both browsers
 * and Node now expose `DecompressionStream('deflate-raw')`, so the whole job
 * is a small ZIP directory walk plus two XML scans. No dependency, nothing to
 * install, and it works offline like the rest of the app.
 *
 * Scope is deliberately narrow: read one sheet's cell VALUES as text. No
 * formulas, styles, merged cells, or number formats — an importer only needs
 * what the cells say. Anything it cannot read raises, and the caller falls
 * back to asking for CSV.
 */

/* ------------------------------- ZIP ------------------------------------ */

interface ZipEntry { name: string; method: number; size: number; offset: number; compressedSize: number }

const SIG_EOCD = 0x06054b50;
const SIG_CDIR = 0x02014b50;

/** Locate the End Of Central Directory record, scanning back from the tail
 *  (it sits at the very end unless there's a ZIP comment, which xlsx has not). */
function findEocd(view: DataView): number {
  const max = Math.min(view.byteLength, 0xffff + 22);
  for (let i = 22; i <= max; i++) {
    const at = view.byteLength - i;
    if (at < 0) break;
    if (view.getUint32(at, true) === SIG_EOCD) return at;
  }
  throw new Error("Not a valid .xlsx file (no ZIP end record)");
}

function readDirectory(buf: Uint8Array): Map<string, ZipEntry> {
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const eocd = findEocd(view);
  const count = view.getUint16(eocd + 10, true);
  let p = view.getUint32(eocd + 16, true);

  // ZIP64 puts sentinel values here; those files are far larger than any
  // broker export, so say so plainly rather than misreading offsets.
  if (p === 0xffffffff || count === 0xffff) throw new Error("ZIP64 .xlsx files are not supported");

  const entries = new Map<string, ZipEntry>();
  const dec = new TextDecoder();
  for (let i = 0; i < count; i++) {
    if (view.getUint32(p, true) !== SIG_CDIR) throw new Error("Corrupt .xlsx (bad central directory)");
    const method = view.getUint16(p + 10, true);
    const compressedSize = view.getUint32(p + 20, true);
    const size = view.getUint32(p + 24, true);
    const nameLen = view.getUint16(p + 28, true);
    const extraLen = view.getUint16(p + 30, true);
    const commentLen = view.getUint16(p + 32, true);
    const offset = view.getUint32(p + 42, true);
    const name = dec.decode(buf.subarray(p + 46, p + 46 + nameLen));
    entries.set(name, { name, method, size, offset, compressedSize });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

async function inflate(bytes: Uint8Array): Promise<Uint8Array> {
  // `deflate-raw`: ZIP stores a bare deflate stream with no zlib header.
  const ds = new DecompressionStream("deflate-raw");
  const stream = new Blob([bytes as unknown as BlobPart]).stream().pipeThrough(ds);
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

async function readEntry(buf: Uint8Array, e: ZipEntry): Promise<string> {
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  // The local header repeats the name/extra lengths, and its extra field can
  // differ in length from the central directory's — so the data offset must be
  // computed from the LOCAL header, not the one we already read.
  const nameLen = view.getUint16(e.offset + 26, true);
  const extraLen = view.getUint16(e.offset + 28, true);
  const start = e.offset + 30 + nameLen + extraLen;
  const raw = buf.subarray(start, start + e.compressedSize);
  const bytes = e.method === 0 ? raw : e.method === 8 ? await inflate(raw) : null;
  if (!bytes) throw new Error(`Unsupported compression in .xlsx (method ${e.method})`);
  return new TextDecoder().decode(bytes);
}

/* ------------------------------- XML ------------------------------------ */

/** Decode the five XML entities plus numeric escapes. */
function unescapeXml(s: string): string {
  return s.replace(/&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos);/g, (m, code: string) => {
    switch (code) {
      case "amp": return "&";
      case "lt": return "<";
      case "gt": return ">";
      case "quot": return '"';
      case "apos": return "'";
      default:
        return code.startsWith("#x") || code.startsWith("#X")
          ? String.fromCodePoint(parseInt(code.slice(2), 16))
          : String.fromCodePoint(parseInt(code.slice(1), 10));
    }
  });
}

/** All <t> text inside one element, concatenated — shared strings split into
 *  <r> runs whenever part of a cell is styled differently. */
function textOf(xml: string): string {
  let out = "";
  const rx = /<t\b[^>]*>([\s\S]*?)<\/t>/g;
  let m: RegExpExecArray | null;
  while ((m = rx.exec(xml))) out += m[1] ?? "";
  return unescapeXml(out);
}

function parseSharedStrings(xml: string): string[] {
  const out: string[] = [];
  const rx = /<si\b[^>]*>([\s\S]*?)<\/si>|<si\b[^>]*\/>/g;
  let m: RegExpExecArray | null;
  while ((m = rx.exec(xml))) out.push(m[1] ? textOf(m[1]) : "");
  return out;
}

/** "BC12" -> 54 (0-based column index). */
function colIndex(ref: string): number {
  const letters = /^([A-Z]+)/.exec(ref.toUpperCase())?.[1] ?? "A";
  let n = 0;
  for (const ch of letters) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}

function parseSheet(xml: string, shared: string[]): string[][] {
  const rows: string[][] = [];
  const rowRx = /<row\b([^>]*?)(?:\/>|>([\s\S]*?)<\/row>)/g;
  let rm: RegExpExecArray | null;
  while ((rm = rowRx.exec(xml))) {
    const body = rm[2];
    // Writers omit entirely-empty rows rather than emitting a blank <row>, so
    // document order is NOT row order. Honour r="N" and pad, or every row
    // below a gap shifts up — which silently reads the wrong header row.
    const rowNo = Number(/\br="(\d+)"/.exec(rm[1] ?? "")?.[1] ?? "0");
    if (rowNo > 0) while (rows.length < rowNo - 1) rows.push([]);
    const cells: string[] = [];
    if (body) {
      const cellRx = /<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g;
      let cm: RegExpExecArray | null;
      while ((cm = cellRx.exec(body))) {
        const attrs = cm[1] ?? "";
        const inner = cm[2] ?? "";
        const ref = /\br="([A-Z]+\d+)"/i.exec(attrs)?.[1];
        const type = /\bt="([^"]+)"/.exec(attrs)?.[1] ?? "n";
        let value = "";
        if (type === "s") {
          const idx = Number(/<v>([\s\S]*?)<\/v>/.exec(inner)?.[1] ?? "-1");
          value = shared[idx] ?? "";
        } else if (type === "inlineStr") {
          value = textOf(inner);
        } else {
          value = unescapeXml(/<v>([\s\S]*?)<\/v>/.exec(inner)?.[1] ?? "");
        }
        // Honour the cell reference so gaps stay gaps: a missing <c> means an
        // empty cell, and ignoring that would shift every later column left.
        const at = ref ? colIndex(ref) : cells.length;
        while (cells.length < at) cells.push("");
        cells[at] = value;
      }
    }
    rows.push(cells);
  }
  return rows;
}

/* ------------------------------- public --------------------------------- */

export interface SheetData { name: string; rows: string[][] }

/** True when this runtime can inflate ZIP data at all. */
export const canReadXlsx = (): boolean => typeof DecompressionStream !== "undefined";

/**
 * Read every worksheet in an .xlsx as rows of strings, in workbook order.
 * Brokers commonly split equity / MF / F&O across sheets, so the caller picks
 * whichever sheet actually parses into holdings rather than assuming the first.
 */
export async function readXlsxSheets(data: ArrayBuffer): Promise<SheetData[]> {
  if (!canReadXlsx()) throw new Error("This browser cannot read .xlsx files — please save as CSV");
  const buf = new Uint8Array(data);
  const dir = readDirectory(buf);

  const sharedEntry = dir.get("xl/sharedStrings.xml");
  const shared = sharedEntry ? parseSharedStrings(await readEntry(buf, sharedEntry)) : [];

  // Sheet name -> file, resolved through the workbook's relationships so the
  // names shown to the user match the tabs in Excel.
  const wbEntry = dir.get("xl/workbook.xml");
  const relsEntry = dir.get("xl/_rels/workbook.xml.rels");
  const relTarget = new Map<string, string>();
  if (relsEntry) {
    const relsXml = await readEntry(buf, relsEntry);
    const rx = /<Relationship\b([^>]*)\/>/g;
    let m: RegExpExecArray | null;
    while ((m = rx.exec(relsXml))) {
      const a = m[1] ?? "";
      const id = /\bId="([^"]+)"/.exec(a)?.[1];
      const target = /\bTarget="([^"]+)"/.exec(a)?.[1];
      if (id && target) relTarget.set(id, target.replace(/^\/?xl\//, "").replace(/^\//, ""));
    }
  }

  const sheets: { name: string; path: string }[] = [];
  if (wbEntry) {
    const wbXml = await readEntry(buf, wbEntry);
    const rx = /<sheet\b([^>]*)\/>/g;
    let m: RegExpExecArray | null;
    while ((m = rx.exec(wbXml))) {
      const a = m[1] ?? "";
      const name = unescapeXml(/\bname="([^"]*)"/.exec(a)?.[1] ?? "Sheet");
      const rid = /\br:id="([^"]+)"/.exec(a)?.[1] ?? /\bid="([^"]+)"/.exec(a)?.[1];
      const target = rid ? relTarget.get(rid) : undefined;
      sheets.push({ name, path: `xl/${target ?? "worksheets/sheet1.xml"}` });
    }
  }
  if (sheets.length === 0) sheets.push({ name: "Sheet1", path: "xl/worksheets/sheet1.xml" });

  const out: SheetData[] = [];
  for (const s of sheets) {
    const entry = dir.get(s.path) ?? dir.get(s.path.replace("xl/", "xl/worksheets/"));
    if (!entry) continue;
    out.push({ name: s.name, rows: parseSheet(await readEntry(buf, entry), shared) });
  }
  if (out.length === 0) throw new Error("No readable sheet found in this .xlsx");
  return out;
}
