export function normalizeOutlineQuery(value) {
  return String(value ?? "").trim().normalize("NFC").toLocaleLowerCase();
}

export function outlineSignature(headings = []) {
  return headings
    .map((heading) => `${heading.from}:${heading.to ?? ""}:${heading.level ?? 1}:${String(heading.title ?? "").normalize("NFC")}`)
    .join("|");
}

// A heading belongs to the closest preceding heading with a lower level. This
// intentionally permits level jumps such as h1 -> h3.
export function buildOutline(headings = []) {
  const nodes = [];
  const stack = [];
  headings.forEach((heading, index) => {
    const level = Math.min(6, Math.max(1, Number(heading.level) || 1));
    while (stack.length && stack.at(-1).level >= level) stack.pop();
    const parent = stack.at(-1) ?? null;
    const node = {
      ...heading,
      index,
      id: `${index}:${heading.from}`,
      level,
      depth: parent ? parent.depth + 1 : 0,
      parent,
      children: [],
    };
    if (parent) parent.children.push(node);
    nodes.push(node);
    stack.push(node);
  });
  return nodes;
}

export function visibleOutline(nodes, { collapsed = new Set(), query = "" } = {}) {
  const normalizedQuery = normalizeOutlineQuery(query);
  if (normalizedQuery) {
    const shown = new Set();
    for (const node of nodes) {
      if (!normalizeOutlineQuery(node.title).includes(normalizedQuery)) continue;
      for (let current = node; current; current = current.parent) shown.add(current);
    }
    return nodes.filter((node) => shown.has(node));
  }
  return nodes.filter((node) => {
    for (let parent = node.parent; parent; parent = parent.parent)
      if (collapsed.has(parent.id)) return false;
    return true;
  });
}
