#!/usr/bin/env python3
"""Exercise nft verdict counters with synthetic frames in an EMPTY network namespace."""
import json
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'packages/swfence/files/usr/lib/swfence'
MAC = '02:00:00:00:00:11'

def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout

links = json.loads(run('ip', '-j', 'link', 'show'))
assert {x['ifname'] for x in links} == {'lo'}, 'Refusing to run outside an empty network namespace'
run('ip', 'link', 'add', 'sftx', 'type', 'veth', 'peer', 'name', 'sfrx')
run('ip', 'link', 'add', 'sfbr', 'type', 'bridge')
run('ip', 'link', 'set', 'sfrx', 'master', 'sfbr')
for dev in ['lo', 'sftx', 'sfrx', 'sfbr']: run('ip', 'link', 'set', dev, 'up')
run('ip', 'addr', 'add', '192.168.50.1/24', 'dev', 'sfbr')
destmac = json.loads(run('ip', '-j', 'link', 'show', 'sfbr'))[0]['address']


def checksum(data):
    total = sum(struct.unpack('!' + 'H' * (len(data) // 2), data))
    while total >> 16: total = (total & 65535) + (total >> 16)
    return (~total) & 65535


def send(dst, port=443, ipv6=False, mac=MAC, tcp=False):
    if tcp:
        payload = struct.pack('!HHIIBBHHH', 40000, port, 1, 0, 5 << 4, 2, 4096, 0, 0)
        protocol = 6
    else:
        payload = struct.pack('!HHHH', 40000, port, 12, 0) + b'test'
        protocol = 17
    if ipv6:
        header = struct.pack('!IHBB16s16s', 6 << 28, len(payload), protocol, 64,
                             socket.inet_pton(socket.AF_INET6, 'fd00::2'), socket.inet_pton(socket.AF_INET6, dst))
        kind = 0x86dd
    else:
        header = struct.pack('!BBHHHBBH4s4s', 0x45, 0, 20 + len(payload), 0, 0, 64, protocol, 0,
                             socket.inet_aton('192.168.50.2'), socket.inet_aton(dst))
        header = header[:10] + struct.pack('!H', checksum(header)) + header[12:]
        kind = 0x0800
    frame = bytes.fromhex(destmac.replace(':', '')) + bytes.fromhex(mac.replace(':', '')) + struct.pack('!H', kind) + header + payload
    with socket.socket(socket.AF_PACKET, socket.SOCK_RAW) as s:
        s.bind(('sftx', 0)); s.send(frame)
    time.sleep(0.04)


def counters(family):
    table, chain = ('swfence', 'console') if family == 'bridge' else ('fw4', 'swfence_policy')
    rules = json.loads(run('nft', '-j', 'list', 'chain', family, table, chain))['nftables']
    out = {}
    for item in rules:
        rule = item.get('rule', {})
        for expression in rule.get('expr', []):
            if 'counter' in expression:
                out[rule.get('comment', '')] = expression['counter']['packets']
    return out


with tempfile.TemporaryDirectory() as temp:
    folder = Path(temp)
    cfg = folder / 'config'
    cfg.write_text(f'MACS={MAC}\nROUTER_IP=192.168.50.1\nLAN_SUBNET=192.168.50.0/24\nLOCAL_HOST=\nLOCAL_PORT=\nALLOWED_IPS=203.0.113.88\nALLOWED_DOMAINS=allowed.example\n')
    run('sh', str(LIB / 'render.sh'), str(cfg), str(folder / 'generated'))
    inet = (folder / 'generated/inet.nft').read_text()
    bridge = (folder / 'generated/bridge.nft').read_text()
    rules = 'table inet fw4 {\n' + inet + '\n}\n' + bridge
    run('nft', '-f', '-', input=rules)
    # Loading the bridge include twice must reset just its own table safely.
    run('nft', '-f', '-', input=bridge)
    for family, table in [('bridge', 'swfence'), ('inet', 'fw4')]:
        run('nft', '-f', '-', input=f'add element {family} {table} swfence_domain_v4 {{ 198.51.100.55 timeout 30s }}\n')
    for family in ['bridge', 'inet']:
        if family == 'inet': run('nft', 'delete', 'table', 'bridge', 'swfence')
        def delta(label, target, **kwargs):
            before = counters(family).get(label, 0)
            send(target, **kwargs)
            after = counters(family).get(label, 0)
            assert after > before, (family, label, before, after)
        delta('SWFence trusted LAN', '192.168.50.3', port=8080)
        delta('SWFence explicit IPv4 exception', '203.0.113.88')
        delta('SWFence domain IPv4 exception', '198.51.100.55')
        delta('SWFence block router proxies', '192.168.50.1', port=1080)
        other = 'SWFence block other bridged traffic' if family == 'bridge' else 'SWFence block other routed traffic'
        for address, port in [('8.8.8.8', 53), ('203.0.113.10', 443), ('198.51.100.20', 1234)]:
            delta(other, address, port=port)
        table = 'swfence' if family == 'bridge' else 'fw4'
        run('nft', '-f', '-', input=f'add element {family} {table} swfence_domain_v4 {{ 198.51.100.56 timeout 1s }}\n')
        delta('SWFence domain IPv4 exception', '198.51.100.56')
        time.sleep(1.1)
        delta(other, '198.51.100.56')
        run('nft', '-f', '-', input=f'delete element {family} {table} swfence_domain_v4 {{ 198.51.100.55 }}\n')
        delta(other, '198.51.100.55')
        ipv6 = 'SWFence block IPv6 on bridge' if family == 'bridge' else 'SWFence block IPv6'
        delta(ipv6, '2001:db8::1', ipv6=True)
        before = counters(family)
        send('203.0.113.10', mac='02:00:00:00:00:22')
        assert counters(family) == before, (family, 'unlisted MAC was affected')
        print(f'{family}: explicit and domain IPv4 exceptions allowed; revoked/expired exceptions, other external traffic and IPv6 dropped; other MAC untouched')
    # Also validate the strict profile syntax.
    cfg.write_text(f'MACS={MAC}\nROUTER_IP=192.168.50.1\nLAN_SUBNET=\nLOCAL_HOST=192.168.50.3\nLOCAL_PORT=8080\n')
    run('sh', str(LIB / 'render.sh'), str(cfg), str(folder / 'strict'))
    strict = 'flush table inet fw4\ntable inet fw4 {\n' + (folder / 'strict/inet.nft').read_text() + '\n}\n'
    run('nft', '-f', '-', input=strict)
    before = counters('inet')
    send('203.0.113.88')
    assert counters('inet')['SWFence block other routed traffic'] > before.get('SWFence block other routed traffic', 0), 'Removed manual exception survived reload'
    before = counters('inet')
    send('192.168.50.3', port=8080, tcp=True)
    assert counters('inet')['SWFence host only'] > before.get('SWFence host only', 0)
    before = counters('inet')
    send('192.168.50.3', port=8081, tcp=True)
    assert counters('inet')['SWFence block other routed traffic'] > before.get('SWFence block other routed traffic', 0)
    print('strict: selected local TCP service allowed; adjacent port dropped')
print('Kernel packet checks passed. No physical interface or internet path was used.')
