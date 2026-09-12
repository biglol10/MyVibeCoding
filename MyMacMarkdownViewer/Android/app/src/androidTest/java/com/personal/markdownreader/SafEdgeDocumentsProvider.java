package com.personal.markdownreader;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract;

import java.io.FileNotFoundException;

/** Test-only provider for SAF error and URI-shape behavior. */
public final class SafEdgeDocumentsProvider extends ContentProvider {
    static final String AUTHORITY = "com.personal.markdownreader.safedge.test";

    @Override public boolean onCreate() { return true; }

    @Override public Cursor query(Uri uri, String[] projection, String selection,
                                  String[] selectionArgs, String sortOrder) {
        final String documentId;
        try { documentId = DocumentsContract.getDocumentId(uri); }
        catch (IllegalArgumentException ignored) { return null; }
        if (!"children".equals(uri.getLastPathSegment())) {
            if (documentId.startsWith("child")) return null;
            MatrixCursor document = cursor(projection);
            document.addRow(row(document, documentId, documentId, DocumentsContract.Document.MIME_TYPE_DIR));
            return document;
        }
        if ("null-cursor".equals(documentId)) return null;
        if ("provider-failure".equals(documentId)) throw new IllegalStateException("fixture provider failure");
        MatrixCursor cursor = cursor(projection);
        if ("loading".equals(documentId)) {
            Bundle extras = new Bundle();
            extras.putBoolean(DocumentsContract.EXTRA_LOADING, true);
            cursor.setExtras(extras);
            return cursor;
        }
        if ("nested".equals(documentId)) {
            cursor.addRow(row(cursor, "child-nested", "nested.md", "text/markdown"));
        } else {
            cursor.addRow(row(cursor, "child-name-fails", "preserved.md", "text/markdown"));
        }
        return cursor;
    }

    @Override public String getType(Uri uri) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] selectionArgs) { return 0; }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) { return 0; }
    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if ("session-doc".equals(DocumentsContract.getDocumentId(uri))) {
            try {
                java.io.File file = new java.io.File(getContext().getCacheDir(), "session-reader.md");
                if (!file.exists()) {
                    try (java.io.FileOutputStream out = new java.io.FileOutputStream(file)) {
                        for (int i=0;i<200;i++) out.write(("## 읽던 절 " + i + "\n\n문서 복원 검증입니다.\n\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
                    }
                }
                return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
            } catch (java.io.IOException e) { throw new FileNotFoundException(e.getMessage()); }
        }
        throw new FileNotFoundException(uri.toString());
    }

    private static MatrixCursor cursor(String[] projection) {
        return new MatrixCursor(projection == null ? new String[] {
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
        } : projection);
    }

    private static Object[] row(MatrixCursor cursor, String id, String name, String mime) {
        Object[] row = new Object[cursor.getColumnCount()];
        for (int i = 0; i < cursor.getColumnCount(); i++) {
            String column = cursor.getColumnName(i);
            if (DocumentsContract.Document.COLUMN_DOCUMENT_ID.equals(column)) row[i] = id;
            else if (DocumentsContract.Document.COLUMN_DISPLAY_NAME.equals(column)) row[i] = name;
            else if (DocumentsContract.Document.COLUMN_MIME_TYPE.equals(column)) row[i] = mime;
        }
        return row;
    }
}
