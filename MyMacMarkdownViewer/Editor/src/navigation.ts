import { EditorSelection } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { headingTargets } from './semantic';
import { post } from './protocol';
import type { RenderContext } from './render';

export function followLink(view: EditorView, href: string, context: RenderContext, explicitPosition?: number) {
  if (view.state.readOnly || view.composing) return;
  if (!href.startsWith('#')) { post('openLink', { href }); return; }
  let fragment = href.slice(1);
  try { fragment = decodeURIComponent(fragment); } catch { /* Keep literal percent signs. */ }
  const target = explicitPosition ?? context.jumps.get(fragment)
    ?? headingTargets(view.state.doc.toString()).find(heading => heading.id === fragment)?.from;
  if (target === undefined || target < 0 || target > view.state.doc.length) {
    post('error', { message: '문서에서 링크가 가리키는 제목을 찾을 수 없습니다.' }); return;
  }
  view.dispatch({ selection: EditorSelection.cursor(target), effects: EditorView.scrollIntoView(target, { y: 'center' }) });
  view.focus();
}

export function bindPreviewLinks(dom: HTMLElement, view: EditorView, context: () => RenderContext) {
  dom.addEventListener('mousedown', event => {
    if (!(event.target as Element).closest('a[href]')) return;
    event.preventDefault(); event.stopPropagation();
  });
  // Native Enter activation also produces click; prevent WebView navigation in
  // both cases and use the same route as inline Markdown modifier-clicks.
  dom.addEventListener('click', event => {
    const anchor = (event.target as Element).closest<HTMLAnchorElement>('a[href]');
    if (!anchor) return;
    event.preventDefault(); event.stopPropagation();
    const raw = anchor.getAttribute('data-jump'), at = raw === null ? undefined : Number(raw);
    followLink(view, anchor.getAttribute('href') ?? '', context(), at !== undefined && Number.isInteger(at) ? at : undefined);
  });
}
