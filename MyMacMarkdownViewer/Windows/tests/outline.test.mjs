import assert from "node:assert/strict";
import test from "node:test";
import { buildOutline, normalizeOutlineQuery, outlineSignature, visibleOutline } from "../ui/outline.mjs";

const headings = [
  { title: "소개", level: 1, from: 0 },
  { title: "건너뛴 소제목", level: 3, from: 8 },
  { title: "같은 제목", level: 2, from: 24 },
  { title: "같은 제목", level: 2, from: 40 },
  { title: "마무리", level: 1, from: 56 },
];

test("outline hierarchy allows skipped levels and keeps duplicate offsets distinct", () => {
  const nodes = buildOutline(headings);
  assert.equal(nodes[1].parent, nodes[0]);
  assert.equal(nodes[1].depth, 1);
  assert.equal(nodes[2].parent, nodes[0]);
  assert.notEqual(nodes[2].id, nodes[3].id);
});

test("outline filtering is NFC, case-insensitive, trimmed, and includes ancestors", () => {
  const nodes = buildOutline(headings);
  assert.equal(normalizeOutlineQuery("  SO\u0308GAE  "), "sögae");
  const visible = visibleOutline(nodes, { query: "  건너뛴  " });
  assert.deepEqual(visible.map(node => node.title), ["소개", "건너뛴 소제목"]);
  assert.deepEqual(visibleOutline(nodes, { collapsed: new Set([nodes[0].id]) }).map(node => node.title), ["소개", "마무리"]);
});

test("heading signature changes for titles and offsets", () => {
  assert.notEqual(outlineSignature(headings), outlineSignature([{ ...headings[0], from: 1 }, ...headings.slice(1)]));
  assert.notEqual(outlineSignature(headings), outlineSignature([{ ...headings[0], title: "다른 소개" }, ...headings.slice(1)]));
});
