#!/usr/bin/env python3
"""Ephemeral loopback-only fixture. Not part of the distributed application."""
from pathlib import Path
from impacket import smbserver, smb3structs as smb2
import os, struct, argparse
parser=argparse.ArgumentParser()
parser.add_argument('--port',type=int,default=1445)
args=parser.parse_args()
root=Path('/Users/Shared/PaneHarbor SMB QA 20261001')
root.mkdir(exist_ok=True)
(root/'NAS 한글 공백').mkdir(exist_ok=True)
(root/'NAS 한글 공백'/'server original.txt').write_text('Loopback SMB fixture only\n')
server=smbserver.SimpleSMBServer(listenAddress='127.0.0.1',listenPort=args.port)
server.addShare('PaneHarborQA',str(root),'Disposable local test files')
server.setSMB2Support(True)
server.setLogFile(str(Path(__file__).resolve().parents[1]/'build/qa-smb-server.log'))
# The minimal upstream example omits QFid responses. macOS then hashes filenames
# into inode numbers, which change on rename. Supply the backing file's stable ID
# for this disposable fixture rather than relaxing the application's race guards.
def create_with_disk_id(conn_id, backend, packet):
    commands, packets, status = original_create(conn_id, backend, packet)
    request = smb2.SMB2Create(packet['Data'])
    if status == 0 and request['CreateContextsLength'] and commands:
        requested = request['Buffer'][request['CreateContextsOffset'] - 64 - 56:]
        contexts = []
        opened = backend.getConnectionData(conn_id)['OpenedFiles']
        info = os.stat(opened[commands[0]['FileID']]['FileName'])
        for name, data in [(b'QFid',struct.pack('<QQ',info.st_ino,info.st_dev)+b'\0'*16),
                           (b'MxAc',struct.pack('<II',0,0x001f01ff))]:
            if name not in requested: continue
            context = smb2.SMB2CreateContext()
            context['NameOffset']=16; context['NameLength']=4
            context['DataOffset']=24; context['DataLength']=len(data)
            context['Buffer']=name+b'\0'*4+data
            contexts.append(context)
        if contexts:
            for context in contexts[:-1]: context['Next']=len(context.getData())
            payload=b''.join(context.getData() for context in contexts)
            commands[0]['CreateContextsOffset']=152
            commands[0]['CreateContextsLength']=len(payload)
            commands[0]['Buffer']=payload
    return commands, packets, status
original_create=server.getServer().hookSmb2Command(smb2.SMB2_CREATE,create_with_disk_id)
print(f'Loopback QA server: smb://127.0.0.1:{args.port}/PaneHarborQA',flush=True)
server.start()
