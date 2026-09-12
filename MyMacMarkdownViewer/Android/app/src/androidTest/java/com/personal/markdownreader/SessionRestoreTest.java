package com.personal.markdownreader;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.test.InstrumentationTestCase;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

public final class SessionRestoreTest extends InstrumentationTestCase {
    private Activity activity;
    private SharedPreferences prefs;
    private Uri tree(String id) { return DocumentsContract.buildTreeDocumentUri(SafEdgeDocumentsProvider.AUTHORITY,id); }
    private Uri child(Uri tree,String id) { return DocumentsContract.buildDocumentUriUsingTree(tree,id); }
    @Override protected void setUp() throws Exception {
        super.setUp(); prefs=getInstrumentation().getTargetContext().getSharedPreferences("reader",0); prefs.edit().clear().commit();
    }
    @Override protected void tearDown() throws Exception { if(activity!=null) { final Activity a=activity; getInstrumentation().runOnMainSync(a::finish); } super.tearDown(); }
    private Object field(Object target,String name) throws Exception { Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target); }
    private Object launchAndWaitForDocument() throws Exception {
        activity=getInstrumentation().startActivitySync(new Intent(getInstrumentation().getTargetContext(),MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        for(int i=0;i<200;i++) { Object current=field(activity,"current"); if(current!=null)return current; Thread.sleep(50); }
        fail("Saved document did not restore"); return null;
    }
    private void seed(Uri browseTree, Uri browseFolder) {
        Uri docTree=tree("document-root"), document=child(docTree,"session-doc");
        prefs.edit().putString("documentUri",document.toString()).putString("name","session.md")
            .putString("treeUri",docTree.toString()).putString("parentUri",child(docTree,"document-root").toString())
            .putString("folderTreeUri",browseTree.toString()).putString("folderUri",browseFolder.toString())
            .putString("positionUri",document.toString()).putFloat("scrollRatio",.61f).commit();
    }
    private String script(String source) throws Exception {
        android.webkit.WebView web=(android.webkit.WebView)field(activity,"webView");
        java.util.concurrent.CountDownLatch latch=new java.util.concurrent.CountDownLatch(1);
        java.util.concurrent.atomic.AtomicReference<String> value=new java.util.concurrent.atomic.AtomicReference<>();
        getInstrumentation().runOnMainSync(()->web.evaluateJavascript(source,result->{value.set(result);latch.countDown();}));
        assertTrue(latch.await(5,java.util.concurrent.TimeUnit.SECONDS));return value.get();
    }
    public void testIndependentFolderAndDocumentRestoreAcrossActivityRestart() throws Exception {
        Uri browseTree=tree("browse-root"); seed(browseTree,child(browseTree,"browse-root"));
        Object current=launchAndWaitForDocument();
        assertEquals("session-doc",DocumentsContract.getDocumentId((Uri)field(current,"uri")));
        assertEquals(.61f,(Float)field(current,"position"),.001f);
        assertEquals(DocumentsContract.getTreeDocumentId(browseTree),DocumentsContract.getTreeDocumentId(Uri.parse(prefs.getString("folderTreeUri",null))));
        Object folder=field(activity,"currentFolder"); assertNotNull(folder);
        assertEquals("browse-root",DocumentsContract.getDocumentId(((androidx.documentfile.provider.DocumentFile)field(folder,"file")).getUri()));
        String sessionId=(String)field(current,"id");
        for(int i=0;i<200;i++) { if("true".equals(script("Boolean(window.ReaderHost&&window.ReaderHost.snapshot().ready==='"+sessionId+"')")))break;Thread.sleep(50); }
        script("(()=>{const s=document.querySelector('#reading');s.style.scrollBehavior='auto';s.scrollTop=(s.scrollHeight-s.clientHeight)*.78;window.ReaderHost.flushPosition();return true})()");
        for(int i=0;i<100 && Math.abs(prefs.getFloat("scrollRatio",0)-.78f)>.002;i++)Thread.sleep(50);
        assertEquals(.78f,prefs.getFloat("scrollRatio",0),.001f);
        final Activity old=activity; getInstrumentation().runOnMainSync(old::finish);getInstrumentation().waitForIdleSync();activity=null;
        Object restored=launchAndWaitForDocument();
        assertEquals(.78f,(Float)field(restored,"position"),.001f);
    }
    public void testStalePositionCannotOverwriteActiveSession() throws Exception {
        Uri browseTree=tree("browse-root");seed(browseTree,child(browseTree,"browse-root"));
        Object current=launchAndWaitForDocument();
        Method save=MainActivity.class.getDeclaredMethod("savePosition",String.class,double.class);save.setAccessible(true);
        getInstrumentation().runOnMainSync(()->{try{save.invoke(activity,"expired-session",.1d);}catch(Exception e){throw new RuntimeException(e);}});
        assertEquals(.61f,prefs.getFloat("scrollRatio",0),.001f);
    }
    public void testUnavailableBrowseFolderDoesNotBlockReadableDocument() throws Exception {
        Uri bad=tree("provider-failure");seed(bad,child(bad,"unknown-folder"));
        Object current=launchAndWaitForDocument();
        assertEquals("session-doc",DocumentsContract.getDocumentId((Uri)field(current,"uri")));
    }
    public void testMalformedBrowseTreeDoesNotBlockReadableDocument() throws Exception {
        Uri bad=Uri.parse("content://invalid-provider/not-a-tree");seed(bad,bad);
        Object current=launchAndWaitForDocument();
        assertEquals("session-doc",DocumentsContract.getDocumentId((Uri)field(current,"uri")));
    }
}
