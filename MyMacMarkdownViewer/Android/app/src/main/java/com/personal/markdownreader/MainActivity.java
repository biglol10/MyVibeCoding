package com.personal.markdownreader;

import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.ContentResolver;
import android.content.Intent;
import android.content.UriPermission;
import android.database.Cursor;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.OpenableColumns;
import android.provider.DocumentsContract;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import androidx.documentfile.provider.DocumentFile;
import androidx.annotation.NonNull;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import androidx.webkit.WebViewAssetLoader;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URLConnection;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.RejectedExecutionException;

/** Read-only SAF host for the bundled reader. All document work stays on the IO executor. */
public final class MainActivity extends android.app.Activity {
    private static final String APP_ORIGIN = "https://appassets.androidplatform.net/reader/index.html";
    private static final int OPEN_FILE = 41;
    private static final int OPEN_TREE = 42;
    private static final int MAX_DOCUMENT_BYTES = 8 * 1024 * 1024;
    private static final int MAX_IMAGE_BYTES = 20 * 1024 * 1024;
    private static final int MAX_DIRECTORY_ENTRIES = 1000;
    private static final String[] CHILD_COLUMNS = {
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
    };

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private final SecureRandom random = new SecureRandom();
    private final Map<String, Node> nodes = new ConcurrentHashMap<>();
    private WebView webView;
    private FrameLayout container;
    private volatile long generation;
    private volatile long folderGeneration;
    private boolean pageReady;
    private String pendingError;
    private long pendingErrorGeneration;
    private volatile Session current;
    private FolderState currentFolder;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        container = new FrameLayout(this);
        ViewCompat.setOnApplyWindowInsetsListener(container, (view, insets) -> {
            Insets bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout() | WindowInsetsCompat.Type.ime());
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return insets;
        });
        webView = new WebView(this);
        webView.setBackgroundColor(Color.TRANSPARENT);
        container.addView(webView, new FrameLayout.LayoutParams(-1, -1));
        applyTheme("night");
        setContentView(container);

        WebViewAssetLoader loader = new WebViewAssetLoader.Builder()
                .addPathHandler("/reader/", new ReaderAssetsPathHandler())
                .addPathHandler("/media/", new MediaPathHandler())
                .build();
        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setDomStorageEnabled(true);
        webView.getSettings().setAllowFileAccess(false);
        webView.getSettings().setAllowContentAccess(false);
        webView.getSettings().setBlockNetworkImage(false);
        webView.getSettings().setMixedContentMode(android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        webView.addJavascriptInterface(new Bridge(), "AndroidBridge");
        if ((getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) WebView.setWebContentsDebuggingEnabled(true);
        webView.setWebViewClient(new ReaderClient(loader));
        webView.loadUrl(APP_ORIGIN);
        if (state != null && state.getParcelable("documentUri") != null) restore(state);
        else if (Intent.ACTION_VIEW.equals(getIntent().getAction())) handleViewIntent(getIntent());
        else restoreLastDocument();
    }

    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleViewIntent(intent);
    }

    @Override protected void onDestroy() {
        generation++;
        io.shutdownNow();
        if (webView != null) { webView.removeJavascriptInterface("AndroidBridge"); webView.destroy(); }
        super.onDestroy();
    }

    @Override protected void onPause() {
        // Scrolling is debounced in the page; this flush only captures the final lifecycle position.
        if (webView != null && pageReady) webView.evaluateJavascript("window.ReaderHost&&window.ReaderHost.flushPosition&&window.ReaderHost.flushPosition()", null);
        super.onPause();
    }

    @Override protected void onSaveInstanceState(@NonNull Bundle out) {
        super.onSaveInstanceState(out);
        if (current != null) {
            out.putParcelable("documentUri", current.uri);
            if (current.tree != null) out.putParcelable("treeUri", current.tree.root.getUri());
            if (current.parent != null) out.putParcelable("parentUri", current.parent.getUri());
        }
        if (currentFolder != null) { out.putParcelable("folderUri", currentFolder.file.getUri()); out.putParcelable("folderTreeUri", currentFolder.tree.root.getUri()); }
    }

    private void restore(Bundle state) {
        Uri document = state.getParcelable("documentUri"), documentTreeUri = state.getParcelable("treeUri");
        Uri parentUri = state.getParcelable("parentUri"), folderUri = state.getParcelable("folderUri");
        Uri folderTreeUri = state.getParcelable("folderTreeUri");
        if (folderTreeUri == null) folderTreeUri = documentTreeUri; // Migrate earlier sessions.
        if (document == null && folderTreeUri == null) return;
        final Uri browseTreeUri = folderTreeUri;
        final long ticket = ++generation;
        runIo(() -> {
            DocumentFile documentRoot = restoredTree(documentTreeUri);
            TreeState documentTree = documentRoot == null ? null : new TreeState(documentRoot);
            DocumentFile browseRoot = restoredTree(browseTreeUri);
            TreeState browseTree = browseRoot == null ? null : (browseTreeUri.equals(documentTreeUri) ? documentTree : new TreeState(browseRoot));
            List<DocumentFile> folderPath = null, parentPath = null;
            String folderError = browseTreeUri != null && browseRoot == null ? "마지막 폴더의 접근 정보를 복원하지 못했습니다. 폴더를 다시 선택해 주세요." : null;
            if (browseRoot != null) {
                try {
                    folderPath = folderUri == null ? java.util.Collections.singletonList(browseRoot) : findFolderPath(browseRoot, DocumentsContract.getDocumentId(folderUri));
                    if (folderPath == null) { folderPath = java.util.Collections.singletonList(browseRoot); folderError = "마지막 하위 폴더를 찾지 못해 상위 폴더를 열었습니다."; }
                } catch (Exception e) { folderError = "마지막 폴더를 열 수 없습니다. 삭제되었거나 접근 권한이 바뀌었을 수 있습니다. 폴더를 다시 선택해 주세요."; }
            }
            if (documentRoot != null && parentUri != null) {
                try { parentPath = findFolderPath(documentRoot, DocumentsContract.getDocumentId(parentUri)); }
                catch (IOException | SecurityException | IllegalArgumentException ignored) { /* The document may have its own read grant. */ }
            }
            final List<DocumentFile> restoredFolderPath = folderPath;
            final DocumentFile parent = parentPath == null ? null : parentPath.get(parentPath.size() - 1);
            final String notice = folderError;
            main.post(() -> {
                if (ticket != generation || isFinishing() || isDestroyed()) return;
                nodes.clear();
                if (restoredFolderPath != null) { currentFolder = registerFolderPath(restoredFolderPath, browseTree); emitFolder(currentFolder, true); }
                if (document != null) openUri(document, getSharedPreferences("reader", MODE_PRIVATE).getString("name", "Markdown 문서"), parent == null ? null : documentTree, parent, ticket, savedPosition(document), notice);
                else if (notice != null) sendError(notice);
            });
        });
    }

    private DocumentFile restoredTree(Uri uri) {
        if (uri == null) return null;
        try { return DocumentFile.fromTreeUri(this, uri); }
        catch (IllegalArgumentException | SecurityException ignored) { return null; }
    }

    private FolderState registerFolderPath(List<DocumentFile> path, TreeState tree) {
        String id = register(path.get(0), tree, null, safeName(path.get(0)), true); String parentId = null;
        for (int i = 1; i < path.size(); i++) { parentId = id; id = register(path.get(i), tree, parentId, safeName(path.get(i)), true); }
        return new FolderState(id, path.get(path.size() - 1), tree, parentId);
    }

    private List<DocumentFile> findFolderPath(DocumentFile root, String targetId) throws IOException {
        final int limit = 1000;
        ArrayDeque<List<DocumentFile>> pending = new ArrayDeque<>();
        List<DocumentFile> start = new ArrayList<>(); start.add(root); pending.add(start);
        int seen = 0;
        while (!pending.isEmpty() && seen++ < limit) {
            List<DocumentFile> path = pending.removeFirst(); DocumentFile folder = path.get(path.size() - 1);
            if (targetId.equals(DocumentsContract.getDocumentId(folder.getUri()))) return path;
            for (Child child : listChildren(folder)) {
                if (pending.size() + seen >= limit || Thread.currentThread().isInterrupted()) return null;
                if (child.directory && path.size() < 64) { List<DocumentFile> next = new ArrayList<>(path); next.add(child.file); pending.addLast(next); }
            }
        }
        return null;
    }

    private void restoreLastDocument() {
        android.content.SharedPreferences prefs = getSharedPreferences("reader", MODE_PRIVATE);
        String raw = prefs.getString("documentUri", null);
        String tree = prefs.getString("treeUri", null), parent = prefs.getString("parentUri", null), folder = prefs.getString("folderUri", null);
        String folderTree = prefs.getString("folderTreeUri", tree);
        if (raw == null) {
            if (folderTree != null) {
                Bundle state = new Bundle(); state.putParcelable("folderTreeUri", Uri.parse(folderTree));
                if (folder != null) state.putParcelable("folderUri", Uri.parse(folder));
                restore(state);
            }
            return;
        }
        Bundle state = new Bundle(); state.putParcelable("documentUri", Uri.parse(raw));
        if (tree != null) state.putParcelable("treeUri", Uri.parse(tree));
        if (parent != null) state.putParcelable("parentUri", Uri.parse(parent));
        if (folder != null) state.putParcelable("folderUri", Uri.parse(folder));
        if (folderTree != null) state.putParcelable("folderTreeUri", Uri.parse(folderTree));
        restore(state);
    }

    private void handleViewIntent(Intent intent) {
        if (!Intent.ACTION_VIEW.equals(intent.getAction()) || intent.getData() == null) return;
        Uri uri = intent.getData();
        if (!"content".equals(uri.getScheme()) || !isMarkdown(displayName(uri))) { sendError("Markdown(.md) 파일만 열 수 있습니다."); return; }
        try { getContentResolver().takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION); } catch (SecurityException ignored) { }
        openUri(uri, displayName(uri), null, null);
    }

    private final class Bridge {
        @JavascriptInterface public void postMessage(String raw) {
            try {
                JSONObject message = new JSONObject(raw);
                String type = message.optString("type", "");
                main.post(() -> dispatch(type, message));
            } catch (JSONException ignored) { main.post(() -> sendError("리더 요청 형식이 올바르지 않습니다.")); }
        }
    }

    private void dispatch(String type, JSONObject message) {
        switch (type) {
            case "ready": pageReady = true; sendCurrent(); if (pendingError != null) { String notice = pendingError; pendingError = null; if (pendingErrorGeneration == generation) sendError(notice); } break;
            case "openFile": chooseFile(); break;
            case "openFolder": chooseFolder(); break;
            case "listFolder": listFolder(message.optString("id", "")); break;
            case "openEntry": openEntry(message.optString("id", "")); break;
            case "allowRemote": requestRemotePermission(message.optString("id", "")); break;
            case "openLink": openLink(message.optString("id", ""), message.optString("href", "")); break;
            case "theme": applyTheme(message.optString("theme", "light")); break;
            case "position": savePosition(message.optString("id", ""), message.optDouble("ratio", -1)); break;
            default: sendError("지원하지 않는 리더 요청입니다.");
        }
    }

    private void chooseFile() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
                .putExtra(Intent.EXTRA_MIME_TYPES, new String[]{"text/markdown", "text/plain", "text/*", "application/octet-stream"})
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        startActivityForResult(intent, OPEN_FILE);
    }

    private void chooseFolder() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        startActivityForResult(intent, OPEN_TREE);
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (result != RESULT_OK || data == null || data.getData() == null) return;
        Uri uri = data.getData();
        if (!"content".equals(uri.getScheme())) { sendError("지원하지 않는 파일 위치입니다."); return; }
        try { getContentResolver().takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION); } catch (SecurityException ignored) { }
        if (request == OPEN_FILE) { if (!isMarkdown(displayName(uri))) { sendError("Markdown(.md) 파일만 열 수 있습니다."); return; } openUri(uri, displayName(uri), null, null); }
        if (request == OPEN_TREE) openTree(uri);
    }

    private void openTree(Uri uri) {
        final long ticket = ++generation;
        runIo(() -> {
            DocumentFile root = DocumentFile.fromTreeUri(this, uri);
            if (root == null) { postError(ticket, "선택한 폴더에 접근할 수 없습니다."); return; }
            main.post(() -> {
                if (ticket != generation || isFinishing()) return;
                nodes.clear();
                TreeState tree = new TreeState(root);
                String id = register(root, tree, null, safeName(root), true);
                current = null; currentFolder = new FolderState(id, root, tree, null);
                getSharedPreferences("reader", MODE_PRIVATE).edit().remove("documentUri").remove("parentUri").remove("positionUri").remove("scrollRatio").putString("treeUri", uri.toString()).putString("folderTreeUri", uri.toString()).putString("folderUri", uri.toString()).apply();
                emitFolder(currentFolder);
            });
        });
    }

    private void openEntry(String id) {
        Node node = nodes.get(id);
        if (node == null) { sendError("폴더 항목이 더 이상 유효하지 않습니다."); return; }
        final long action = ++generation;
        runIo(() -> {
            try {
                if (action != generation) return;
                if (node.directory) { main.post(() -> { if (action != generation || isDestroyed()) return; currentFolder = new FolderState(id, node.file, node.tree, node.parentId); saveFolderState(); emitFolder(currentFolder); }); }
                else if (isMarkdown(node.name)) { Node parentNode = node.parentId == null ? null : nodes.get(node.parentId); openUri(node.file.getUri(), node.name, node.tree, parentNode == null ? node.tree.root : parentNode.file, action); }
                else sendError("Markdown(.md) 파일만 열 수 있습니다.");
            } catch (SecurityException e) { sendError("파일 접근 권한이 만료되었습니다."); }
        });
    }

    private void listFolder(String id) {
        Node node = nodes.get(id);
        if (node == null) { sendError("폴더가 더 이상 유효하지 않습니다."); return; }
        final long action = ++generation;
        runIo(() -> { try { if (!node.directory) { sendError("선택한 항목은 폴더가 아닙니다."); return; } main.post(() -> { if (action != generation || isDestroyed()) return; currentFolder = new FolderState(id, node.file, node.tree, node.parentId); saveFolderState(); emitFolder(currentFolder); }); } catch (SecurityException e) { sendError("폴더 접근 권한이 만료되었습니다."); } });
    }

    private void emitFolder(FolderState folder) { emitFolder(folder, false); }
    private void emitFolder(FolderState folder, boolean passive) {
        final long ticket = ++folderGeneration;
        final long action = generation;
        runIo(() -> {
            JSONArray entries = new JSONArray(); boolean truncated = false; int count = 0;
            try {
            for (Child child : listChildren(folder.file)) {
                if (!(child.directory || isMarkdown(child.name))) continue;
                if (++count > MAX_DIRECTORY_ENTRIES) { truncated = true; break; }
                String id = register(child.file, folder.tree, folder.id, child.name, child.directory);
                JSONObject item = new JSONObject();
                try { item.put("id", id); item.put("name", child.name); item.put("directory", child.directory); entries.put(item); } catch (JSONException ignored) { }
            }
            } catch (LoadingException e) { postFolderError(folder, ticket, action, "폴더 목록을 불러오는 중입니다. 잠시 후 새로고침해 주세요."); return;
            } catch (SecurityException e) { postFolderError(folder, ticket, action, "폴더 접근 권한이 만료되었습니다."); return;
            } catch (IOException | IllegalArgumentException e) { postFolderError(folder, ticket, action, "폴더 목록을 읽지 못했습니다. 파일 앱에서 이 폴더를 다시 선택해 주세요."); return; }
            final boolean finalTruncated = truncated;
            main.post(() -> {
                if (ticket != folderGeneration || action != generation || isFinishing() || isDestroyed()) return;
                JSONObject event = new JSONObject();
                try {
                    event.put("type", "folder"); event.put("id", folder.id); event.put("name", safeName(folder.file));
                    event.put("entries", entries); event.put("parentId", folder.parentId == null ? JSONObject.NULL : folder.parentId);
                    if (passive) event.put("passive", true);
                    if (finalTruncated) { event.put("truncated", true); event.put("message", "폴더 목록은 1,000개 항목까지만 표시합니다."); }
                } catch (JSONException ignored) { }
                send(event);
            });
        });
    }

    private void openUri(Uri uri, String name, TreeState tree, DocumentFile parent) {
        openUri(uri, name, tree, parent, ++generation);
    }

    private void openUri(Uri uri, String name, TreeState tree, DocumentFile parent, long ticket) {
        openUri(uri, name, tree, parent, ticket, 0f);
    }

    private void openUri(Uri uri, String name, TreeState tree, DocumentFile parent, long ticket, float position) {
        openUri(uri, name, tree, parent, ticket, position, null);
    }

    private void openUri(Uri uri, String name, TreeState tree, DocumentFile parent, long ticket, float position, String restoreNotice) {
        runIo(() -> {
            try {
                if (ticket != generation) return;
                if (tree != null && parent != null) tree.parents.put(uri.toString(), parent);
                String text = readUtf8(uri, MAX_DOCUMENT_BYTES);
                Session session = new Session(token(), uri, name == null ? "Untitled.md" : name, text, tree, parent, position);
                main.post(() -> {
                    if (ticket != generation || isFinishing()) return;
                    current = session; saveLastDocument(session); sendDocument(session); if (restoreNotice != null) sendError(restoreNotice);
                });
            } catch (TooLargeException e) { postError(ticket, "Markdown 파일은 8 MiB까지 열 수 있습니다.");
            } catch (CharacterCodingException e) { postError(ticket, "이 파일은 UTF-8 Markdown 형식이 아닙니다.");
            } catch (SecurityException e) { postError(ticket, "파일 접근 권한이 만료되었습니다.");
            } catch (IOException e) { postError(ticket, "Markdown 파일을 읽을 수 없습니다."); }
        });
    }

    private void sendDocument(Session session) {
        JSONObject event = new JSONObject();
        try { event.put("type", "document"); event.put("id", session.id); event.put("name", session.name); event.put("text", session.text); event.put("hasFolder", session.tree != null); event.put("position", session.position); } catch (JSONException ignored) { }
        send(event);
    }

    private void requestRemotePermission(String requestedId) {
        if (current == null || !current.id.equals(requestedId)) { sendError("현재 문서에 대한 요청이 아닙니다."); return; }
        final String id = current.id;
        new AlertDialog.Builder(this)
                .setTitle("원격 이미지를 불러올까요?")
                .setMessage("이 문서가 인터넷에서 이미지를 요청할 수 있습니다. 이 문서에서만 허용할까요?")
                .setNegativeButton("나중에", null)
                .setPositiveButton("허용", (d, w) -> {
                    if (current != null && current.id.equals(id)) { current.remoteAllowed = true; JSONObject e = new JSONObject(); try { e.put("type", "remoteAllowed"); e.put("id", id); } catch (JSONException ignored) { } send(e); }
                }).show();
    }

    private void openLink(String requestedId, String href) {
        if (current == null || !current.id.equals(requestedId)) { sendError("현재 문서에 대한 요청이 아닙니다."); return; }
        if (href == null || href.isEmpty()) return;
        if (href.startsWith("https://")) {
            new AlertDialog.Builder(this).setTitle("링크를 열까요?").setMessage(href)
                    .setNegativeButton("취소", null).setPositiveButton("열기", (d, w) -> {
                        try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(href))); } catch (ActivityNotFoundException e) { sendError("이 링크를 열 수 있는 앱이 없습니다."); }
                    }).show();
            return;
        }
        if (current.tree == null) { sendError("로컬 링크는 폴더를 선택한 뒤에 열 수 있습니다."); return; }
        String path = href.split("#", 2)[0];
        if (path.isEmpty()) return;
        Session session = current;
        final long action = ++generation;
        runIo(() -> { try { if (action != generation) return; DocumentFile target = resolveRelative(session.parent, path, session.tree); if (target == null || target.isDirectory() || !isMarkdown(target.getName())) { sendError("선택한 폴더 밖의 Markdown 링크이거나 사용할 수 없습니다."); return; } openUri(target.getUri(), target.getName(), session.tree, relativeParent(session.parent, path, session.tree), action); } catch (SecurityException e) { sendError("파일 접근 권한이 만료되었습니다."); } });
    }

    private DocumentFile relativeParent(DocumentFile base, String source, TreeState tree) {
        int slash = source.replace('\\', '/').lastIndexOf('/');
        return slash < 0 ? base : resolveRelative(base, source.substring(0, slash), tree);
    }

    private DocumentFile resolveRelative(DocumentFile base, String source, TreeState tree) {
        if (base == null || source.startsWith("/") || source.startsWith("\\") || source.startsWith("//") || source.matches("^[A-Za-z][A-Za-z0-9+.-]*:.*")) return null;
        // Uri.decode performs percent decoding without URLDecoder's '+' to space conversion.
        String decoded = Uri.decode(source);
        DocumentFile cursor = base;
        for (String piece : decoded.replace('\\', '/').split("/")) {
            if (piece.isEmpty() || ".".equals(piece)) continue;
            if ("..".equals(piece)) {
                cursor = tree.parents.get(cursor.getUri().toString());
                if (cursor == null) return null; // Root escape is never permitted.
                continue;
            }
            DocumentFile parent = cursor;
            cursor = childNamed(cursor, piece);
            if (cursor == null) return null;
            tree.parents.put(cursor.getUri().toString(), parent);
        }
        return cursor;
    }

    private DocumentFile childNamed(DocumentFile folder, String name) {
        if (folder == null || !folder.isDirectory()) return null;
        try {
            for (Child child : listChildren(folder)) if (name.equals(child.name)) return child.file;
            return null;
        } catch (IOException | SecurityException | IllegalArgumentException ignored) { return null; }
    }

    private final class MediaPathHandler implements WebViewAssetLoader.PathHandler {
        @Override public WebResourceResponse handle(String path) {
            Session session = current;
            if (session == null) return notFound();
            int slash = path.indexOf('/');
            if (slash < 1 || !session.id.equals(path.substring(0, slash))) return notFound();
            if (session.tree == null || session.parent == null) return notFound();
            String relative = path.substring(slash + 1);
            try {
                DocumentFile image = resolveRelative(session.parent, relative, session.tree);
                if (image == null || image.isDirectory()) return notFound();
                InputStream input = limited(getContentResolver().openInputStream(image.getUri()), MAX_IMAGE_BYTES);
                if (input == null) return notFound();
                String mime = getContentResolver().getType(image.getUri());
                if (mime == null || !mime.startsWith("image/")) mime = URLConnection.guessContentTypeFromName(image.getName());
                if (mime == null || !mime.startsWith("image/")) { input.close(); return notFound(); }
                return new WebResourceResponse(mime, null, input);
            } catch (IOException | SecurityException e) { return notFound(); }
        }
    }

    private final class ReaderAssetsPathHandler implements WebViewAssetLoader.PathHandler {
        @Override public WebResourceResponse handle(String path) {
            if (path.contains("..") || path.startsWith("/")) return notFound();
            try {
                InputStream input = getAssets().open("reader/" + path);
                String type = URLConnection.guessContentTypeFromName(path);
                return new WebResourceResponse(type == null ? "application/octet-stream" : type, "UTF-8", input);
            } catch (IOException | SecurityException e) { return notFound(); }
        }
    }

    private final class ReaderClient extends WebViewClient {
        private final WebViewAssetLoader loader;
        ReaderClient(WebViewAssetLoader loader) { this.loader = loader; }
        @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
            Uri uri = request.getUrl();
            if ("https".equals(uri.getScheme()) && "appassets.androidplatform.net".equals(uri.getHost())) {
                WebResourceResponse response = loader.shouldInterceptRequest(uri);
                return response == null ? notFound() : response;
            }
            if ("https".equals(uri.getScheme()) && current != null && current.remoteAllowed && !request.isForMainFrame() && acceptsImage(request)) return fetchHttpsImage(uri);
            return notFound();
        }
        @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            Uri uri = request.getUrl();
            return !APP_ORIGIN.equals(uri.toString());
        }
        @Override public void onPageFinished(WebView view, String url) { if (APP_ORIGIN.equals(url)) pageReady = true; }
    }

    private boolean acceptsImage(WebResourceRequest request) {
        String accept = null;
        for (Map.Entry<String, String> header : request.getRequestHeaders().entrySet()) if ("accept".equalsIgnoreCase(header.getKey())) accept = header.getValue();
        return accept != null && accept.toLowerCase(Locale.ROOT).contains("image/");
    }

    private WebResourceResponse fetchHttpsImage(Uri uri) {
        try {
            URL url = new URL(uri.toString());
            for (int redirects = 0; redirects < 4; redirects++) {
                HttpURLConnection connection = (HttpURLConnection) url.openConnection();
                connection.setInstanceFollowRedirects(false);
                connection.setConnectTimeout(10_000); connection.setReadTimeout(15_000);
                connection.setRequestProperty("Accept", "image/*");
                int status = connection.getResponseCode();
                if (status >= 300 && status < 400) {
                    String location = connection.getHeaderField("Location"); connection.disconnect();
                    if (location == null) return notFound();
                    URL next = new URL(url, location);
                    if (!"https".equalsIgnoreCase(next.getProtocol())) return notFound();
                    url = next; continue;
                }
                if (status != HttpURLConnection.HTTP_OK || connection.getContentLengthLong() > MAX_IMAGE_BYTES) { connection.disconnect(); return notFound(); }
                String type = connection.getContentType();
                if (type == null || !type.toLowerCase(Locale.ROOT).startsWith("image/")) { connection.disconnect(); return notFound(); }
                return new WebResourceResponse(type.split(";", 2)[0], null, limited(connection.getInputStream(), MAX_IMAGE_BYTES));
            }
        } catch (IOException ignored) { }
        return notFound();
    }

    private void sendCurrent() { if (!pageReady) return; if (currentFolder != null) emitFolder(currentFolder, current != null); if (current != null) sendDocument(current); }
    private void sendError(String message) { if (Looper.myLooper() != Looper.getMainLooper()) { main.post(() -> sendError(message)); return; } if (!pageReady) { pendingError = message; pendingErrorGeneration = generation; return; } JSONObject e = new JSONObject(); try { e.put("type", "error"); e.put("message", message); } catch (JSONException ignored) { } send(e); }
    private void postError(long ticket, String message) { main.post(() -> { if (ticket == generation && !isFinishing()) sendError(message); }); }
    private void postFolderError(FolderState folder, long ticket, long action, String message) {
        main.post(() -> {
            if (ticket != folderGeneration || action != generation || isFinishing() || isDestroyed()) return;
            JSONObject event = new JSONObject();
            try {
                event.put("type", "folder"); event.put("id", folder.id); event.put("name", safeName(folder.file));
                event.put("entries", new JSONArray()); event.put("parentId", folder.parentId == null ? JSONObject.NULL : folder.parentId);
                event.put("error", message);
            } catch (JSONException ignored) { }
            send(event);
        });
    }
    private void send(JSONObject event) {
        if (!pageReady || isFinishing() || isDestroyed() || webView == null) return;
        webView.evaluateJavascript("window.ReaderHost&&window.ReaderHost.receive(JSON.parse(" + JSONObject.quote(event.toString()) + "));", null);
    }

    private void saveLastDocument(Session session) {
        android.content.SharedPreferences.Editor e = getSharedPreferences("reader", MODE_PRIVATE).edit().putString("documentUri", session.uri.toString()).putString("name", session.name);
        if (session.tree == null) e.remove("treeUri"); else e.putString("treeUri", session.tree.root.getUri().toString());
        if (session.parent == null) e.remove("parentUri"); else e.putString("parentUri", session.parent.getUri().toString());
        if (currentFolder != null) { e.putString("folderTreeUri", currentFolder.tree.root.getUri().toString()).putString("folderUri", currentFolder.file.getUri().toString()); }
        e.putString("positionUri", session.uri.toString()).putFloat("scrollRatio", session.position);
        e.apply();
    }

    private void saveFolderState() {
        if (currentFolder == null) return;
        getSharedPreferences("reader", MODE_PRIVATE).edit().putString("folderTreeUri", currentFolder.tree.root.getUri().toString()).putString("folderUri", currentFolder.file.getUri().toString()).apply();
    }

    private void savePosition(String sessionId, double ratio) {
        Session session = current;
        if (session == null || !session.id.equals(sessionId) || !Double.isFinite(ratio)) return;
        float clamped = (float) Math.max(0d, Math.min(1d, ratio));
        android.content.SharedPreferences prefs = getSharedPreferences("reader", MODE_PRIVATE);
        if (!session.uri.toString().equals(prefs.getString("documentUri", null))) return;
        session.position = clamped;
        prefs.edit().putString("positionUri", session.uri.toString()).putFloat("scrollRatio", clamped).apply();
    }

    private float savedPosition(Uri uri) {
        android.content.SharedPreferences prefs = getSharedPreferences("reader", MODE_PRIVATE);
        if (!uri.toString().equals(prefs.getString("documentUri", null)) || !uri.toString().equals(prefs.getString("positionUri", null))) return 0f;
        float value = prefs.getFloat("scrollRatio", 0f);
        return Float.isFinite(value) ? Math.max(0f, Math.min(1f, value)) : 0f;
    }

    private void applyTheme(String theme) {
        boolean night = "night".equals(theme);
        boolean dark = "dark".equals(theme) || night;
        String background = night ? "#373B40" : (dark ? "#15171D" : "#FFFFFF");
        getWindow().setStatusBarColor(Color.parseColor(background));
        getWindow().setNavigationBarColor(Color.parseColor(background));
        if (container != null) container.setBackgroundColor(Color.parseColor(background));
        new WindowInsetsControllerCompat(getWindow(), webView).setAppearanceLightStatusBars(!dark);
        new WindowInsetsControllerCompat(getWindow(), webView).setAppearanceLightNavigationBars(!dark);
    }

    @Override public void onBackPressed() {
        if (webView == null) { super.onBackPressed(); return; }
        webView.evaluateJavascript("Boolean(window.ReaderHost&&window.ReaderHost.back&&window.ReaderHost.back())", result -> { if (!"true".equals(result)) MainActivity.super.onBackPressed(); });
    }

    private void runIo(Runnable action) { if (isFinishing() || isDestroyed()) return; try { io.execute(action); } catch (RejectedExecutionException ignored) { } }

    private String register(DocumentFile file, TreeState tree, String parentId, String name, boolean directory) {
        String key = file.getUri().toString();
        String id = tree.ids.computeIfAbsent(key, unused -> token());
        nodes.putIfAbsent(id, new Node(file, tree, parentId, name, directory));
        if (parentId != null && nodes.get(parentId) != null) tree.parents.put(key, nodes.get(parentId).file);
        return id;
    }
    private String token() { byte[] bytes = new byte[18]; random.nextBytes(bytes); return java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes); }
    private String displayName(Uri uri) { android.database.Cursor c = null; try { c = getContentResolver().query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null); if (c != null && c.moveToFirst()) return c.getString(0); } catch (Exception ignored) { } finally { if (c != null) c.close(); } return "Untitled.md"; }
    private static String safeName(DocumentFile file) { String name = file.getName(); return name == null ? "Untitled" : name; }
    private static boolean isMarkdown(String name) { if (name == null) return false; String lower = name.toLowerCase(Locale.ROOT); return lower.endsWith(".md") || lower.endsWith(".markdown"); }
    /** Queries child rows directly because DocumentFile.listFiles() converts provider failures into an empty array. */
    private List<Child> listChildren(DocumentFile folder) throws IOException {
        if (folder == null) throw new IOException("Missing folder");
        final Uri children;
        try { children = DocumentsContract.buildChildDocumentsUriUsingTree(folder.getUri(), DocumentsContract.getDocumentId(folder.getUri())); }
        catch (IllegalArgumentException e) { throw new IOException("Invalid tree URI", e); }
        List<Child> result = new ArrayList<>();
        try (Cursor cursor = getContentResolver().query(children, CHILD_COLUMNS, null, null, null)) {
            if (cursor == null) throw new IOException("Provider returned no cursor");
            if (cursor.getExtras().getBoolean(DocumentsContract.EXTRA_LOADING, false)) throw new LoadingException();
            int idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID);
            int nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME);
            int mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE);
            if (idIndex < 0 || nameIndex < 0 || mimeIndex < 0) throw new IOException("Provider omitted document columns");
            while (cursor.moveToNext()) {
                String documentId = cursor.getString(idIndex);
                if (documentId == null || documentId.isEmpty()) continue;
                String name = cursor.getString(nameIndex);
                String mime = cursor.getString(mimeIndex);
                boolean directory = DocumentsContract.Document.MIME_TYPE_DIR.equals(mime);
                Uri document = DocumentsContract.buildDocumentUriUsingTree(folder.getUri(), documentId);
                DocumentFile child = DocumentFile.fromSingleUri(this, document);
                if (child != null) result.add(new Child(child, name == null || name.isEmpty() ? documentId : name, directory));
            }
        } catch (SecurityException e) {
            throw e;
        } catch (RuntimeException e) {
            throw new IOException("Provider could not return folder entries", e);
        }
        return result;
    }
    private String readUtf8(Uri uri, int max) throws IOException, CharacterCodingException { byte[] bytes; try (InputStream input = limited(getContentResolver().openInputStream(uri), max)) { if (input == null) throw new IOException(); bytes = readAll(input); } if (bytes.length >= 3 && bytes[0] == (byte)0xEF && bytes[1] == (byte)0xBB && bytes[2] == (byte)0xBF) { byte[] clean = new byte[bytes.length - 3]; System.arraycopy(bytes, 3, clean, 0, clean.length); bytes = clean; } CharBuffer decoded = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)); return decoded.toString(); }
    private static InputStream limited(InputStream stream, int max) throws IOException { if (stream == null) throw new IOException(); return new FilterInputStream(stream) { int count; @Override public int read() throws IOException { int r = super.read(); if (r >= 0 && ++count > max) throw new TooLargeException(); return r; } @Override public int read(byte[] b, int off, int len) throws IOException { int r = super.read(b, off, len); if (r > 0 && (count += r) > max) throw new TooLargeException(); return r; } }; }
    private static byte[] readAll(InputStream input) throws IOException { ByteArrayOutputStream output = new ByteArrayOutputStream(); byte[] buffer = new byte[8192]; for (int n; (n = input.read(buffer)) != -1;) output.write(buffer, 0, n); return output.toByteArray(); }
    private static WebResourceResponse notFound() { return new WebResourceResponse("text/plain", "UTF-8", 404, "Not Found", new HashMap<>(), new ByteArrayInputStream(new byte[0])); }
    private static final class TooLargeException extends IOException { }
    private static final class LoadingException extends IOException { }
    private static final class TreeState { final DocumentFile root; final Map<String, DocumentFile> parents = new ConcurrentHashMap<>(); final Map<String, String> ids = new ConcurrentHashMap<>(); TreeState(DocumentFile root) { this.root = root; } }
    private static final class Child { final DocumentFile file; final String name; final boolean directory; Child(DocumentFile f, String n, boolean d) { file = f; name = n; directory = d; } }
    private static final class Node { final DocumentFile file; final TreeState tree; final String parentId; final String name; final boolean directory; Node(DocumentFile f, TreeState t, String p, String n, boolean d) { file = f; tree = t; parentId = p; name = n; directory = d; } }
    private static final class FolderState { final String id; final DocumentFile file; final TreeState tree; final String parentId; FolderState(String i, DocumentFile f, TreeState t, String p) { id = i; file = f; tree = t; parentId = p; } }
    private static final class Session { final String id; final Uri uri; final String name; final String text; final TreeState tree; final DocumentFile parent; volatile float position; volatile boolean remoteAllowed; Session(String i, Uri u, String n, String tx, TreeState tr, DocumentFile p, float po) { id = i; uri = u; name = n; text = tx; tree = tr; parent = p; position = po; } }
}
