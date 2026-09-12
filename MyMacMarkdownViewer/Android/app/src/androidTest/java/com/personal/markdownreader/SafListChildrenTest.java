package com.personal.markdownreader;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.test.InstrumentationTestCase;

import androidx.documentfile.provider.DocumentFile;

import java.io.IOException;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.List;

public final class SafListChildrenTest extends InstrumentationTestCase {
    private Activity activity;
    private Method listChildren;

    @Override protected void setUp() throws Exception {
        super.setUp();
        Intent intent = new Intent(getInstrumentation().getTargetContext(), MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        activity = getInstrumentation().startActivitySync(intent);
        listChildren = MainActivity.class.getDeclaredMethod("listChildren", DocumentFile.class);
        listChildren.setAccessible(true);
    }

    @Override protected void tearDown() throws Exception {
        if (activity != null) activity.finish();
        super.tearDown();
    }

    public void testChildRowNameSurvivesBrokenIndividualMetadataQuery() throws Exception {
        List<?> children = invoke(folder("name-fails", "name-fails"));
        assertEquals(1, children.size());
        Object child = children.get(0);
        assertEquals("preserved.md", field(child, "name"));
        DocumentFile file = (DocumentFile) field(child, "file");
        assertNull("The provider fixture must reproduce DocumentFile.getName() failure", file.getName());
    }

    public void testNullCursorIsFailureInsteadOfEmptyDirectory() throws Exception {
        assertIOException(folder("null-cursor", "null-cursor"), "IOException", "Provider returned no cursor");
    }

    public void testLoadingCursorIsFailureInsteadOfEmptyDirectory() throws Exception {
        assertIOException(folder("loading", "loading"), "LoadingException", null);
    }

    public void testProviderRuntimeFailureIsReportedAsIOException() throws Exception {
        assertIOException(folder("provider-failure", "provider-failure"), "IOException", "Provider could not return folder entries");
    }

    public void testNestedFolderQueriesItsDocumentIdAndBuildsChildWithinOriginalTree() throws Exception {
        List<?> children = invoke(folder("root", "nested"));
        assertEquals(1, children.size());
        DocumentFile file = (DocumentFile) field(children.get(0), "file");
        assertEquals("root", DocumentsContract.getTreeDocumentId(file.getUri()));
        assertEquals("child-nested", DocumentsContract.getDocumentId(file.getUri()));
    }

    private DocumentFile folder(String treeId, String documentId) {
        Uri tree = DocumentsContract.buildTreeDocumentUri(SafEdgeDocumentsProvider.AUTHORITY, treeId);
        Uri document = DocumentsContract.buildDocumentUriUsingTree(tree, documentId);
        DocumentFile folder = DocumentFile.fromSingleUri(activity, document);
        assertNotNull(folder);
        return folder;
    }

    @SuppressWarnings("unchecked") private List<?> invoke(DocumentFile folder) throws Exception {
        try { return (List<?>) listChildren.invoke(activity, folder); }
        catch (InvocationTargetException e) {
            Throwable cause = e.getCause();
            if (cause instanceof Exception) throw (Exception) cause;
            throw e;
        }
    }

    private void assertIOException(DocumentFile folder, String simpleName, String message) throws Exception {
        try { invoke(folder); fail("Expected " + simpleName); }
        catch (IOException expected) {
            assertEquals(simpleName, expected.getClass().getSimpleName());
            if (message != null) assertEquals(message, expected.getMessage());
        }
    }

    private static Object field(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(target);
    }
}
