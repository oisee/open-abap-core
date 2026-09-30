// Synthetic sanctions-list-shaped pull benchmark. Run under flock /tmp/osd-heavy.lock.
import { initializeABAP } from '../output/init.mjs';

await initializeABAP();
const mib = Number(process.argv[2] || 1);
if (![1, 10, 50].includes(mib)) throw new Error('size must be 1, 10, or 50 MiB');
const shape = process.env.SXML_SHAPE === 'text' ? 'text' : 'elements';
const fields = Array.from({length: 15}, (_, i) => {
  const tag = `f${i}`;
  const attr = i < 12 ? ` k="${i}"` : '';
  const value = i === 3 ? 'A&amp;B' : i === 9 ? '<![CDATA[x&]]>' : 'v';
  return `<${tag}${attr}>${value}</${tag}>`;
}).join('');
const record = `<record id="000000" status="active">${fields}</record>`;
const start = '<list xmlns="urn:sanctions">';
const end = '</list>';
const records = shape === 'text' ? 0 : Math.ceil((mib * 1048576 - start.length - end.length) / record.length);
let xml = shape === 'text' ? '<r>' + 'a'.repeat(mib * 1048576 - 7) + '</r>'
  : start + record.repeat(records) + end;
const bytes = Buffer.byteLength(xml);
const hex = Buffer.from(xml).toString('hex').toUpperCase();
xml = undefined;
global.gc?.();
const input = new abap.types.XString().set(hex);
const rssBefore = process.memoryUsage().rss;
const t0 = performance.now();
const reader = (await abap.Classes.CL_SXML_STRING_READER.create({input})).get();
let tokens = 0;
let attributes = 0;
for (;;) {
  await reader.if_sxml_reader$next_node();
  const kind = reader.if_sxml_reader$node_type.get();
  if (kind === 128) break;
  tokens++;
  if (kind === 1) {
    for (;;) {
      await reader.if_sxml_reader$next_attribute();
      if (reader.if_sxml_reader$node_type.get() === 128) break;
      tokens++;
      attributes++;
    }
  }
}
const seconds = (performance.now() - t0) / 1000;
console.log(JSON.stringify({shape, mib, bytes, recordBytes: record.length, records, tokens, attributes,
  seconds, mibPerSec: bytes / 1048576 / seconds, tokensPerSec: tokens / seconds,
  rssBeforeMiB: rssBefore / 1048576, peakRssMiB: process.resourceUsage().maxRSS / 1024}));
