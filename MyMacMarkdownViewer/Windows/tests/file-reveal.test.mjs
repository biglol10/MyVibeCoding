import assert from "node:assert/strict";
import test from "node:test";
import {
  findFileEntry,
  isPathWithinRoot,
  knownAncestorDirectories,
  sameTreePath,
} from "../ui/file-reveal.mjs";

test("path containment respects boundaries and Windows case rules", () => {
  assert.equal(isPathWithinRoot("/notes/topic.md", "/notes"), true);
  assert.equal(isPathWithinRoot("/notes-old/topic.md", "/notes"), false);
  assert.equal(isPathWithinRoot("/Notes/topic.md", "/notes"), false);
  assert.equal(isPathWithinRoot("C:\\Notes\\topic.md", "c:\\notes"), true);
  assert.equal(isPathWithinRoot("C:\\Notes-old\\topic.md", "C:\\Notes"), false);
  assert.equal(sameTreePath("C:\\Notes\\topic.md", "c:/notes/topic.md"), true);
  assert.equal(sameTreePath("/Notes/topic.md", "/notes/topic.md"), false);
});

test("known ancestor rows are returned from root outward", () => {
  const entries = [
    { path: "/notes/chapters", directory: true },
    { path: "/notes/chapters/part-1", directory: true },
    { path: "/notes/chapters/part-1/topic.md", directory: false },
    { path: "/notes/other", directory: true },
  ];
  assert.equal(findFileEntry("/notes/chapters/part-1/topic.md", entries), entries[2]);
  assert.deepEqual(
    knownAncestorDirectories("/notes/chapters/part-1/topic.md", "/notes", entries),
    ["/notes/chapters", "/notes/chapters/part-1"],
  );
  assert.equal(knownAncestorDirectories("/notes/chapters/part-1/topic.md", "/notes", entries.slice(1)), null);
  assert.equal(knownAncestorDirectories("/notes/unknown/topic.md", "/notes", entries), null);
  assert.equal(knownAncestorDirectories("/outside/topic.md", "/notes", entries), null);
});

test("Windows ancestor matching tolerates path casing while returning indexed paths", () => {
  const entries = [
    { path: "C:\\Notes\\Chapters", directory: true },
    { path: "C:\\Notes\\Chapters\\Part-1", directory: true },
    { path: "C:\\Notes\\Chapters\\Part-1\\Topic.md", directory: false },
  ];
  assert.deepEqual(
    knownAncestorDirectories("c:/notes/chapters/part-1/topic.md", "c:/notes", entries),
    ["C:\\Notes\\Chapters", "C:\\Notes\\Chapters\\Part-1"],
  );
});
