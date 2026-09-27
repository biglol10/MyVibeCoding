type TextInput = HTMLInputElement | HTMLTextAreaElement;
type Snapshot = { value: string; start: number | null; end: number | null };
type History = { current: Snapshot; undo: Snapshot[]; redo: Snapshot[]; lastType: string; lastTime: number };
const histories = new WeakMap<TextInput, History>();
const composing = new WeakSet<TextInput>();
let replaying = false;

function textInput(target: EventTarget | null): TextInput | undefined {
  if ((target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement)
      && !target.classList.contains('table-cell-input') && target.selectionStart !== null) return target;
}
function snapshot(input: TextInput): Snapshot {
  return { value: input.value, start: input.selectionStart, end: input.selectionEnd };
}
function history(input: TextInput) {
  let result = histories.get(input);
  if (!result) {
    result = { current: snapshot(input), undo: [], redo: [], lastType: '', lastTime: 0 };
    histories.set(input, result);
  }
  return result;
}

/** WebKit's document undo stack can include edits from the contenteditable
 * document and a search input in the same group. Keep auxiliary fields local. */
export function undoInput(input: TextInput, direction: 'undo' | 'redo') {
  if (input.disabled || input.readOnly || composing.has(input)) return;
  const state = history(input);
  if (state.current.value !== input.value) {
    histories.delete(input); return; // A programmatic replacement starts a new history.
  }
  const previous = state[direction].pop();
  if (!previous) return;
  state[direction === 'undo' ? 'redo' : 'undo'].push(snapshot(input));
  input.value = previous.value;
  input.setSelectionRange(previous.start ?? 0, previous.end ?? 0);
  state.current = snapshot(input); state.lastType = '';
  replaying = true;
  try { input.dispatchEvent(new Event('input', { bubbles: true })); }
  finally { replaying = false; }
}

export function installInputHistory() {
  document.addEventListener('focusin', event => {
    const input = textInput(event.target);
    if (input) history(input).lastType = '';
  }, true);
  document.addEventListener('compositionstart', event => { const input = textInput(event.target); if (input) composing.add(input); }, true);
  document.addEventListener('compositionend', event => { const input = textInput(event.target); if (input) composing.delete(input); }, true);
  document.addEventListener('beforeinput', event => {
    const input = textInput(event.target); if (!input) return;
    const type = (event as InputEvent).inputType;
    if (type === 'historyUndo' || type === 'historyRedo') {
      event.preventDefault(); undoInput(input, type === 'historyUndo' ? 'undo' : 'redo'); return;
    }
    const state = history(input);
    if (state.current.value !== input.value) { histories.delete(input); history(input); }
    else state.current = snapshot(input);
  }, true);
  document.addEventListener('input', event => {
    const input = textInput(event.target); if (!input || replaying) return;
    const state = history(input), current = snapshot(input), type = (event as InputEvent).inputType ?? '';
    if (current.value === state.current.value) return;
    const now = performance.now();
    const continuous = ['insertText', 'insertCompositionText', 'deleteContentBackward', 'deleteContentForward'].includes(type);
    if (!continuous || type !== state.lastType || now - state.lastTime > 750 || !state.undo.length) state.undo.push(state.current);
    if (state.undo.length > 100) state.undo.shift();
    state.current = current; state.redo = []; state.lastType = type; state.lastTime = now;
  }, true);
  document.addEventListener('keydown', event => {
    const input = textInput(event.target); if (!input) return;
    if ((event.metaKey || event.ctrlKey) && !event.altKey && event.key.toLowerCase() === 'z') {
      event.preventDefault(); event.stopPropagation(); undoInput(input, event.shiftKey ? 'redo' : 'undo');
    } else if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) history(input).lastType = '';
  }, true);
}
