#!/usr/bin/env python3
"""Build a personally signed release APK without putting signing secrets in the repository."""
from pathlib import Path
import hashlib,json,os,secrets,subprocess,re
root=Path(__file__).resolve().parents[2]
android=root/'Android'
sdk=Path(os.environ.get('ANDROID_SDK_ROOT',str(Path.home()/'Library/Android/sdk')))
tools=sdk/'build-tools/36.0.0'
java_home=Path(os.environ.get('JAVA_HOME','/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home'))
env=dict(os.environ,JAVA_HOME=str(java_home),ANDROID_SDK_ROOT=str(sdk),ANDROID_HOME=str(sdk))
subprocess.run(['node',str(android/'scripts/build-reader.mjs')],cwd=root,env=env,check=True)
subprocess.run([str(android/'gradlew'),':app:assembleRelease','--no-daemon'],cwd=android,env=env,check=True)
signing=Path.home()/'.local/share/mymarkdownreader-signing'
signing.mkdir(parents=True,exist_ok=True,mode=0o700)
key=signing/'personal-release.jks';password=signing/'password'
if not key.exists():
    if not password.exists():
        descriptor=os.open(password,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(descriptor,'w') as handle:handle.write(secrets.token_urlsafe(40))
    subprocess.run([str(java_home/'bin/keytool'),'-genkeypair','-keystore',str(key),'-storepass:file',str(password),'-keypass:file',str(password),'-alias','markdown-reader','-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=Markdown Reader Personal'],check=True,env=env)
    key.chmod(0o600)
if not password.exists():raise RuntimeError('Signing password file missing; preserve the existing key and restore its password file.')
out=root/'dist/android';out.mkdir(parents=True,exist_ok=True)
unsigned=android/'app/build/outputs/apk/release/app-release-unsigned.apk'
aligned=android/'app/build/outputs/apk/release/app-release-aligned.apk'
subprocess.run([str(tools/'zipalign'),'-f','-p','4',str(unsigned),str(aligned)],check=True,env=env)
gradle=(android/'app/build.gradle').read_text(encoding='utf-8')
version_match=re.search(r"versionName\s+['\"]([^'\"]+)['\"]",gradle)
if not version_match: raise RuntimeError('Could not read versionName from Android/app/build.gradle')
version=version_match.group(1)
apk=out/f'MarkdownReader-{version}-Android.apk'
subprocess.run([str(tools/'apksigner'),'sign','--ks',str(key),'--ks-key-alias','markdown-reader','--ks-pass','file:'+str(password),'--out',str(apk),str(aligned)],check=True,env=env)
subprocess.run([str(tools/'apksigner'),'verify','--verbose',str(apk)],check=True,env=env)
badging=subprocess.check_output([str(tools/'aapt'),'dump','badging',str(apk)],env=env,text=True)
if 'application-debuggable' in badging:raise RuntimeError('Distribution APK must not be debuggable')
digest=hashlib.sha256(apk.read_bytes()).hexdigest()
Path(str(apk)+'.sha256').write_text(f'{digest}  {apk.name}\n')
print(json.dumps({'apk':str(apk),'bytes':apk.stat().st_size,'sha256':digest,'signed':True,'debuggable':False},indent=2))
