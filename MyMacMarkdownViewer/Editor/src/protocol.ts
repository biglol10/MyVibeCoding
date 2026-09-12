export interface Settings {
  theme: 'dark' | 'night' | 'light'; fontSize: number; lineHeight: number; contentWidth: number;
  fontFamily: string; remoteImages: boolean;
  /** Kept optional so older native hosts can continue sending their existing settings object. */
  focusMode?: boolean; typewriterMode?: boolean;
}
export interface Heading { title: string; level: number; from: number }
export interface Session { documentID: string; sessionID: string; revision: number; baseURL: string }
export const defaultSettings: Settings = {
  theme: 'dark', fontSize: 17, lineHeight: 1.7, contentWidth: 800,
  fontFamily: 'system', remoteImages: false, focusMode: false, typewriterMode: false,
};
export let session: Session = { documentID: 'preview', sessionID: 'preview', revision: 0, baseURL: '' };
export function setSession(next: Session) { session = next; }
declare global {
  interface Window {
    webkit?: { messageHandlers: { editor: { postMessage: (message: unknown) => void } } };
    MarkdownHost: Record<string, (...args: any[]) => any>;
    __editorTest?: Record<string, (...args: any[]) => any>;
  }
}
export function post(type: string, payload: Record<string, unknown> = {}) {
  window.webkit?.messageHandlers.editor.postMessage({ type, ...session, ...payload });
}
export function accepts(message: { sessionID?: string; documentID?: string }) {
  return message.sessionID === session.sessionID && message.documentID === session.documentID;
}
