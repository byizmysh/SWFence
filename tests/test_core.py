import json
import hashlib
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FILES = ROOT / 'packages/swfence/files'
LIB = FILES / 'usr/lib/swfence'


def config(macs='02:00:00:00:00:11', subnet='192.168.50.0/24', host='', port=''):
    return f'MACS={macs}\nROUTER_IP=192.168.50.1\nLAN_SUBNET={subnet}\nLOCAL_HOST={host}\nLOCAL_PORT={port}\n'


class RendererTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)

    def render(self, content=None, ok=True, installing=True):
        src = self.path / 'config'
        src.write_text(content or config())
        out = self.path / 'output'
        result = subprocess.run(['sh', str(LIB / 'render.sh'), str(src), str(out)],
                                env=dict(os.environ, SWFENCE_FOR_INSTALL=str(int(installing))),
                                text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return out

    def test_lan_and_router_proxy_precedence(self):
        out = self.render()
        for name in ['inet.nft', 'bridge.nft']:
            text = (out / name).read_text()
            self.assertNotRegex(text, r'@[A-Z_]+@')
            self.assertLess(text.index('SWFence local DNS and conntest'), text.index('SWFence block router proxies'))
            self.assertLess(text.index('SWFence block router proxies'), text.index('SWFence trusted LAN'))
            self.assertIn('192.168.50.0/24 counter return', text)
            self.assertIn('counter drop comment "SWFence block other', text)
            self.assertIn('SWFence block IPv6', text)

    def test_single_service_profile_and_two_macs(self):
        out = self.render(config('02:00:00:00:00:11 02:00:00:00:00:12', '', '192.168.50.2', '8080'))
        for name in ['inet.nft', 'bridge.nft']:
            text = (out / name).read_text()
            self.assertIn('{ 02:00:00:00:00:11, 02:00:00:00:00:12 }', text)
            self.assertIn('192.168.50.2 tcp dport 8080', text)
            self.assertNotIn('SWFence trusted LAN', text)

    def test_internet_exceptions_validation_and_rendering(self):
        out = self.render(config() + 'ALLOWED_IPS=1.1.1.1 203.0.113.88\nALLOWED_DOMAINS=example.com api.example.com\n')
        for name in ['inet.nft', 'bridge.nft']:
            text = (out / name).read_text()
            self.assertIn('ip daddr { 1.1.1.1, 203.0.113.88 } counter return', text)
            self.assertLess(text.index('SWFence block router proxies'), text.index('SWFence explicit IPv4 exception'))
            self.assertIn('swfence_domain_v4', text)
        for value in ['https://example.com', '*.example.com', 'example.com/path', '-bad.example', 'a..com', '8.8.8.8', 'CTEST.CDN.NINTENDO.NET', 'a.example;reboot']:
            self.render(config() + f'ALLOWED_DOMAINS={value}\n', ok=False)
        for value in ['0.0.0.0', '127.0.0.1', '192.168.50.1', '169.254.1.1', '100.64.0.1', '224.0.0.1', '::1', '1.1.1.1/32']:
            self.render(config() + f'ALLOWED_IPS={value}\n', ok=False)

    def test_invalid_config_is_rejected(self):
        for text in [config(''), config('   '), config('ff:ff:ff:ff:ff:ff'),
                     config('00:00:00:00:00:00'), config('02:00:00:00:00:11; reboot'),
                     config(subnet='0.0.0.0/0'), config(subnet='192.168.1.0/33'),
                     config(host='8.8.8.8', port='80'), config(host='192.168.50.2', port='65536'),
                     config().replace('192.168.50.1\n', '192.168.50.999\n')]:
            with self.subTest(text=text): self.render(text, ok=False)

    def test_example_mac_cannot_be_enabled(self):
        self.render(config('02:7e:93:4c:a8:61'), ok=False)
        self.render(config('02:B4:6F:21:D9:30'), ok=False)
        self.render(config('02:7e:93:4c:a8:61'), installing=False)

    def test_both_generations_http_and_invalid_requests(self):
        for host in ['ctest.cdn.nintendo.net', 'ctest.p01.ctest.srv.nintendo.net',
                     'ctest-ipv6.p01.ctest.srv.nintendo.net', 'conntest.nintendowifi.net']:
            for method, uri, good in [('GET', '/', True), ('POST', '/', False), ('GET', '/etc/passwd', False)]:
                env = dict(os.environ, HTTP_HOST=host, REQUEST_METHOD=method, REQUEST_URI=uri)
                r = subprocess.run(['sh', str(LIB / 'templates/index.cgi')], env=env, capture_output=True)
                self.assertEqual(r.returncode, 0)
                self.assertIn(b'200 OK' if good else b'404 Not Found', r.stdout)
                if good:
                    self.assertIn(b'X-Organization: Nintendo\r\n', r.stdout)
                    self.assertTrue(r.stdout.endswith(b'\r\n\r\nok'))
        r = subprocess.run(['sh', str(LIB / 'templates/index.cgi')],
                           env=dict(os.environ, HTTP_HOST='example.com', REQUEST_METHOD='GET', REQUEST_URI='/'), capture_output=True)
        self.assertIn(b'404 Not Found', r.stdout)

    def test_shell_and_json_syntax_and_acl_scope(self):
        for p in ROOT.rglob('*'):
            if '.git' in p.parts or not p.is_file(): continue
            if p.suffix == '.json': json.loads(p.read_text())
            if p.suffix == '.sh' or p.name in ['swfence', 'index.cgi']:
                subprocess.run(['sh', '-n', str(p)], check=True)
        acl = json.loads((ROOT / 'packages/luci-app-swfence/root/usr/share/rpcd/acl.d/luci-app-swfence.json').read_text())['luci-app-swfence']
        self.assertEqual(acl['write'], {'ubus': {'swfence': ['configure']}})
        self.assertEqual(acl['read']['ubus']['swfence'], ['status', 'diagnostics'])

    @unittest.skipUnless(shutil.which('dnsmasq'), 'host dnsmasq unavailable')
    def test_live_dns_returns_local_answer_and_nxdomain(self):
        out = self.render()
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]
        conf = out / 'dnsmasq.conf'
        hosts = self.path / 'allowed-hosts'
        hosts.write_text('203.0.113.88 allowed.example\n')
        conf.write_text(conf.read_text().replace('port=5357', f'port={port}').replace('listen-address=192.168.50.1', 'listen-address=127.0.0.1').replace('/var/run/swfence/allowed-hosts', str(hosts)))
        log = open(self.path / 'dns.log', 'w+')
        self.addCleanup(log.close)
        import pwd, grp
        proc = subprocess.Popen(['dnsmasq', '--keep-in-foreground', '--pid-file=', f'--conf-file={conf}',
                                 '--user=' + pwd.getpwuid(os.getuid()).pw_name,
                                 '--group=' + grp.getgrgid(os.getgid()).gr_name], stdout=log, stderr=log)
        def stop(): proc.terminate(); proc.wait(timeout=5)
        self.addCleanup(stop)
        def query(name, kind):
            qname = b''.join(bytes([len(s)]) + s.encode() for s in name.split('.')) + b'\0'
            packet = struct.pack('!6H', 1234, 0x0100, 1, 0, 0, 0) + qname + struct.pack('!HH', kind, 1)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.settimeout(0.2)
                for _ in range(15):
                    s.sendto(packet, ('127.0.0.1', port))
                    try: return s.recv(4096)
                    except socket.timeout:
                        if proc.poll() is not None:
                            log.seek(0); self.fail(log.read())
                self.fail('DNS did not answer')
        for name in ['ctest.cdn.nintendo.net', 'ctest.p01.ctest.srv.nintendo.net']:
            reply = query(name, 1)
            self.assertEqual(reply[3] & 15, 0)
            self.assertIn(socket.inet_aton('192.168.50.1'), reply)
        for kind in [1, 28]:
            reply = query('example.com', kind)
            self.assertEqual(reply[3] & 15, 3)
            self.assertEqual(struct.unpack('!H', reply[6:8])[0], 0)
        reply = query('allowed.example', 1)
        self.assertEqual(reply[3] & 15, 0)
        self.assertIn(socket.inet_aton('203.0.113.88'), reply)
        self.assertEqual(query('sub.allowed.example', 1)[3] & 15, 3, 'Only exact names are allowed')
        hosts.write_text('')
        import signal, time
        proc.send_signal(signal.SIGHUP)
        for _ in range(15):
            reply = query('allowed.example', 1)
            if reply[3] & 15 == 3: break
            time.sleep(0.02)
        self.assertEqual(reply[3] & 15, 3, 'Removing an exception must remove its DNS answer')


@unittest.skipUnless(os.environ.get('SWFENCE_ROOTFS'), 'set SWFENCE_ROOTFS for real OpenWrt shell/UCI tests')
class NativeOpenWrtTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'root'
        shutil.copytree(os.environ['SWFENCE_ROOTFS'], self.root, symlinks=True)
        if (self.root / 'var').is_symlink(): (self.root / 'var').unlink()
        (self.root / 'var').mkdir(exist_ok=True)
        shutil.copytree(FILES, self.root, dirs_exist_ok=True)
        rpc = ROOT / 'packages/luci-app-swfence/root'
        shutil.copytree(rpc, self.root, dirs_exist_ok=True)
        for p in self.root.joinpath('usr/lib/swfence').glob('*.sh'): p.chmod(0o755)
        (self.root / 'usr/sbin/swfence').chmod(0o755)
        (self.root / 'usr/libexec/rpcd/swfence').chmod(0o755)
        self.write('/sbin/fw4', '''#!/bin/sh
if [ -f /tmp/fail-$1 ]; then rm /tmp/fail-$1; echo "Injected fw4 $1 failure" >&2; exit 1; fi
if [ "$1" = reload ]; then
 if [ -f /etc/nftables.d/90-swfence.nft ]; then touch /tmp/guard; else rm -f /tmp/guard; fi
fi
exit 0
''')
        self.write('/usr/sbin/nft', '''#!/bin/sh
[ -f /tmp/guard ] || exit 1
case "$1" in
 delete) rm -f /tmp/guard ;;
 list) echo 'chain swfence_early { counter packets 7 bytes 700 drop; }' ;;
esac
''')
        self.write('/usr/sbin/uhttpd', '#!/bin/sh\nexit 0\n')
        self.write('/bin/ubus', '#!/bin/sh\necho \'{"swfence":{"instances":{"dns":{"running":true},"http":{"running":true}}}}\'\n')
        self.write('/etc/init.d/swfence', '#!/bin/sh\nexec /usr/lib/swfence/apply.sh\n')
        (self.root / 'tmp/.uci').mkdir(parents=True, exist_ok=True)
        (self.root / 'dev').mkdir(exist_ok=True)
        (self.root / 'dev/null').touch(exist_ok=True)
        # dnsmasq --test seeds its RNG even without binding a socket.
        (self.root / 'dev/urandom').write_bytes(os.urandom(4096))

    def write(self, path, text):
        dest = self.root / path.lstrip('/')
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.is_symlink(): dest.unlink()
        dest.write_text(text); dest.chmod(0o755)

    def native(self, *args, input=None, check=True):
        cmd = ['unshare', '-Urn', 'chroot', str(self.root), *args]
        result = subprocess.run(cmd, input=input, text=True, capture_output=True, timeout=60)
        if check and result.returncode:
            self.fail(f'Native command {args}: {result.returncode}\n{result.stdout}\n{result.stderr}')
        return result

    def settings(self, **changes):
        data = dict(enabled='1', macs='02:00:00:00:00:11', router_ip='192.168.50.1',
                    lan_subnet='192.168.50.0/24', local_host='', local_port='')
        data.update(changes)
        return json.loads(self.native('/usr/sbin/swfence', 'configure', input=json.dumps(data)).stdout)

    def test_enable_status_and_disable(self):
        result = self.settings()
        self.assertTrue(result['ok'], result)
        s = json.loads(self.native('/usr/sbin/swfence', 'status').stdout)
        self.assertTrue(s['guard_present'])
        self.assertTrue(s['config_matches'])
        self.assertEqual(s['config']['macs'], ['02:00:00:00:00:11'])
        self.assertEqual(s['counters']['bridge_dropped'], '7')
        result = self.settings(enabled='0')
        self.assertTrue(result['ok'], result)
        self.assertFalse((self.root / 'etc/nftables.d/90-swfence.nft').exists())
        s = json.loads(self.native('/usr/sbin/swfence', 'status').stdout)
        self.assertFalse(s['guard_present'])

    def statistics_fixture(self):
        self.write('/bin/date', '''#!/bin/sh
case "$1" in
 +%F) cat /tmp/test-day ;;
 +%s) cat /tmp/test-now ;;
 *) exec /bin/busybox date "$@" ;;
esac
''')
        self.write('/usr/sbin/nft', '''#!/bin/sh
case "$*" in
 *"bridge swfence console"*) count=$(cat /tmp/test-bridge) ;;
 *"inet fw4 swfence_policy"*) count=$(cat /tmp/test-inet) ;;
 *) exit 1 ;;
esac
printf 'counter packets %s bytes 700 drop;\\n' "$count"
''')
        self.write('/tmp/test-day', '2026-10-28\n')
        self.write('/tmp/test-now', '1793142000\n')
        self.write('/tmp/test-bridge', '100\n')
        self.write('/tmp/test-inet', '20\n')

    def test_daily_statistics_midnight_reset_and_rule_reload(self):
        self.statistics_fixture()
        def sample():
            return json.loads(self.native('/usr/sbin/swfence', 'status').stdout)['daily_counters']
        first = sample()
        self.assertTrue(first['available'])
        self.assertEqual(first['bridge_dropped'], '0', 'Unknown previous history must not be attributed to today')
        self.write('/tmp/test-bridge', '107\n')
        self.write('/tmp/test-inet', '23\n')
        next_sample = sample()
        self.assertEqual((next_sample['bridge_dropped'], next_sample['inet_dropped']), ('7', '3'))
        self.assertEqual(sample(), next_sample, 'Repeated readers must not double count')
        self.write('/tmp/test-bridge', '2\n')  # Firewall counters reset independently.
        self.write('/tmp/test-inet', '24\n')
        self.assertEqual((sample()['bridge_dropped'], sample()['inet_dropped']), ('9', '4'))
        self.write('/tmp/test-day', '2026-10-29\n')
        self.write('/tmp/test-now', '1793228400\n')
        rollover = sample()
        self.assertEqual(rollover['day'], '2026-10-29')
        self.assertEqual((rollover['bridge_dropped'], rollover['inet_dropped']), ('0', '0'))
        self.assertNotEqual(rollover['collected_since'], first['collected_since'])
        self.write('/tmp/test-bridge', '5\n')
        self.write('/tmp/test-inet', '26\n')
        self.assertEqual((sample()['bridge_dropped'], sample()['inet_dropped']), ('3', '2'))
        (self.root / 'var/run/swfence/statistics').unlink()  # RAM state disappears on reboot.
        self.assertEqual(sample()['bridge_dropped'], '0')

    def test_statistics_collector_runs_without_a_panel(self):
        self.statistics_fixture()
        self.native('/bin/sh', '-c', '''
/bin/sh /usr/lib/swfence/collect-statistics.sh & collector=$!
trap 'kill "$collector" 2>/dev/null || true' EXIT
/bin/sleep 1
echo 107 > /tmp/test-bridge
echo 23 > /tmp/test-inet
/bin/sleep 5
kill "$collector"
wait "$collector" || true
''')
        fields = (self.root / 'var/run/swfence/statistics').read_text().split()
        self.assertEqual(fields[-2:], ['7', '3'])
        self.assertFalse((self.root / 'var/run/swfence/statistics.lock').exists())

    def test_invalid_and_example_settings_do_not_modify_uci(self):
        before = (self.root / 'etc/config/swfence').read_bytes()
        for changes in [dict(macs='02:7e:93:4c:a8:61'), dict(macs='bad'),
                        dict(router_ip='8.8.8.8'), dict(lan_subnet='0.0.0.0/0'),
                        dict(macs='02:00:00:00:00:11\nROUTER_IP=8.8.8.8')]:
            with self.subTest(changes=changes):
                result = self.settings(**changes)
                self.assertFalse(result['ok'], result)
                self.assertEqual((self.root / 'etc/config/swfence').read_bytes(), before)

    def test_exception_settings_validation_and_old_client_compatibility(self):
        self.assertTrue(self.settings(allowed_ips='1.1.1.1', allowed_domains='example.com')['ok'])
        self.assertTrue(self.settings()['ok'], 'Old clients must preserve existing exceptions')
        current = json.loads(self.native('/usr/sbin/swfence', 'status').stdout)
        self.assertEqual(current['config']['allowed_ips'], ['1.1.1.1'])
        self.assertEqual(current['config']['allowed_domains'], ['example.com'])
        before = (self.root / 'etc/config/swfence').read_bytes()
        for changes in [dict(allowed_ips='192.168.50.1'), dict(allowed_domains='*.example.com'),
                        dict(allowed_domains='good.example\nALLOWED_IPS=8.8.8.8')]:
            self.assertFalse(self.settings(**changes)['ok'])
            self.assertEqual((self.root / 'etc/config/swfence').read_bytes(), before)
        self.assertTrue(self.settings(allowed_ips='', allowed_domains='')['ok'])
        current = json.loads(self.native('/usr/sbin/swfence', 'status').stdout)
        self.assertEqual(current['config']['allowed_domains'], [])
        self.assertNotIn('SWFence explicit IPv4 exception', (self.root / 'etc/nftables.d/90-swfence.nft').read_text())

    def domain_fixture(self):
        self.assertTrue(self.settings(allowed_domains='ALLOWED.EXAMPLE missing.example')['ok'])
        self.write('/usr/bin/nslookup', '''#!/bin/sh
printf '%s\\n' "$*" >> /tmp/domain-queries
case "$*" in *missing.example*) exit 1 ;; esac
printf 'Server: 192.168.50.1\\nAddress: 192.168.50.1#53\\n\\nName: allowed.example\\nAddress 1: 203.0.113.88 allowed.example\\nAddress: 192.168.50.2\\nAddress: 127.0.0.1\\nAddress: 2001:db8::1\\n'
''')
        self.write('/usr/sbin/nft', '''#!/bin/sh
if [ "$1" = -f ]; then
 [ ! -f /tmp/fail-nft ] || { echo 'Injected nft failure' >&2; exit 1; }
 cat "$2" > /tmp/domain-update.nft
 exit 0
fi
[ "$1" != list ] || echo 'chain test { counter packets 7 bytes 700 drop; }'
''')

    def test_domain_refresh_filters_answers_and_fails_closed(self):
        self.domain_fixture()
        self.native('/bin/sh', '/usr/lib/swfence/refresh-allowlist.sh', 'once')
        hosts = self.root / 'var/run/swfence/allowed-hosts'
        self.assertEqual(hosts.read_text(), '203.0.113.88 allowed.example\n')
        rules = (self.root / 'tmp/domain-update.nft').read_text()
        for family, table in [('inet', 'fw4'), ('bridge', 'swfence')]:
            self.assertIn(f'flush set {family} {table} swfence_domain_v4', rules)
            self.assertIn(f'add element {family} {table} swfence_domain_v4 {{ 203.0.113.88 }}', rules)
        current = json.loads(self.native('/usr/sbin/swfence', 'status').stdout)
        self.assertEqual(current['domain_status']['state'], 'updated')
        self.assertEqual((current['domain_status']['resolved'], current['domain_status']['unresolved']), ('1', '1'))
        for query in (self.root / 'tmp/domain-queries').read_text().splitlines():
            self.assertTrue(query.endswith('192.168.50.1'))
            self.assertIn('-type=A', query)
        self.write('/usr/bin/nslookup', '#!/bin/sh\nexit 1\n')
        self.native('/bin/sh', '/usr/lib/swfence/refresh-allowlist.sh', 'once')
        self.assertEqual(hosts.read_text(), '')
        self.assertNotIn('add element', (self.root / 'tmp/domain-update.nft').read_text())
        self.assertFalse((self.root / 'var/lock/swfence-apply').exists())

    def test_domain_refresh_nft_failure_keeps_previous_records(self):
        self.domain_fixture()
        hosts = self.root / 'var/run/swfence/allowed-hosts'
        hosts.write_text('203.0.113.9 previous.example\n')
        (self.root / 'tmp/fail-nft').touch()
        result = self.native('/bin/sh', '/usr/lib/swfence/refresh-allowlist.sh', 'once', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(hosts.read_text(), '203.0.113.9 previous.example\n')
        current = json.loads(self.native('/usr/sbin/swfence', 'status').stdout)
        self.assertEqual(current['domain_status']['state'], 'error')
        self.assertIn('Injected nft failure', current['domain_status']['error'])

    def test_domain_refresh_discards_results_after_settings_change(self):
        self.domain_fixture()
        self.write('/usr/bin/nslookup', '''#!/bin/sh
echo '# changed during lookup' >> /etc/swfence/active.env
printf 'Name: allowed.example\\nAddress: 203.0.113.88\\n'
''')
        self.native('/bin/sh', '/usr/lib/swfence/refresh-allowlist.sh', 'once')
        self.assertFalse((self.root / 'tmp/domain-update.nft').exists())
        self.assertEqual((self.root / 'var/run/swfence/allowed-hosts').read_text(), '')

    def test_repository_footer_url_validation(self):
        self.write('/etc/swfence/repository', 'example/SWFence\n')
        current = json.loads(self.native('/usr/sbin/swfence', 'status').stdout)
        self.assertEqual(current['project_url'], 'https://github.com/example/SWFence')
        self.write('/etc/swfence/repository', 'javascript:alert(1)\n')
        current = json.loads(self.native('/usr/sbin/swfence', 'status').stdout)
        self.assertEqual(current['project_url'], '')

    def test_check_and_reload_failures_restore_previous_rules(self):
        self.assertTrue(self.settings()['ok'])
        rule = self.root / 'etc/nftables.d/90-swfence.nft'
        before = rule.read_bytes()
        old = (self.root / 'etc/config/swfence').read_bytes()
        for kind in ['check', 'reload']:
            (self.root / ('tmp/fail-' + kind)).touch()
            result = self.settings(macs='02:00:00:00:00:12')
            self.assertFalse(result['ok'], result)
            self.assertEqual(rule.read_bytes(), before)
            self.assertEqual((self.root / 'etc/config/swfence').read_bytes(), old)

    def test_rollback_and_rpc_whitelist(self):
        self.assertTrue(self.settings()['ok'])
        self.assertTrue(self.settings(macs='02:00:00:00:00:12')['ok'])
        self.native('/usr/sbin/swfence', 'rollback')
        s = json.loads(self.native('/usr/sbin/swfence', 'status').stdout)
        self.assertEqual(s['config']['macs'], ['02:00:00:00:00:11'])
        methods = json.loads(self.native('/usr/libexec/rpcd/swfence', 'list').stdout)
        self.assertEqual(set(methods), {'status', 'diagnostics', 'configure'})
        bad = self.native('/usr/libexec/rpcd/swfence', 'call', 'exec', check=False)
        self.assertNotEqual(bad.returncode, 0)

    def test_pending_configuration_does_not_claim_applied(self):
        self.assertTrue(self.settings()['ok'])
        self.native('/sbin/uci', 'set', 'swfence.main.router_ip=192.168.50.2')
        self.native('/sbin/uci', 'commit', 'swfence')
        s = json.loads(self.native('/usr/sbin/swfence', 'status').stdout)
        self.assertFalse(s['config_matches'])
        self.assertTrue(s['guard_present'])

    def test_diagnostics_are_local_and_console_test_stays_manual(self):
        self.assertTrue(self.settings()['ok'])
        self.write('/usr/bin/nslookup', '''#!/bin/sh
printf '%s\\n' "$*" >> /tmp/dns-targets
case "$*" in *swfence-unlisted.invalid*) echo NXDOMAIN; exit 1 ;; esac
printf 'Name: ctest.cdn.nintendo.net\\nAddress: 192.168.50.1\\n'
''')
        self.write('/bin/uclient-fetch', '''#!/bin/sh
while [ "$#" -gt 0 ]; do
 if [ "$1" = -O ]; then shift; printf ok > "$1"; fi
 shift
done
''')
        report = json.loads(self.native('/usr/sbin/swfence', 'diagnostics').stdout)
        checks = {x['name']: x['result'] for x in report['checks']}
        self.assertEqual(checks['console_external_isolation'], 'manual')
        self.assertEqual(checks['dns_local_answer'], 'pass')
        self.assertEqual(checks['dns_external_A'], 'pass')
        self.assertEqual(checks['dns_external_AAAA'], 'pass')
        self.assertEqual(checks['http_connection_check'], 'pass')
        self.assertIn('Router-local', report['scope'])
        for query in (self.root / 'tmp/dns-targets').read_text().splitlines():
            self.assertTrue(query.endswith('192.168.50.1'))
            self.assertIn('-port=5357', query)

    def bootstrap_fixture(self, valid_hash=True):
        self.write('/tmp/installer.sh', (ROOT / 'install.sh').read_text())
        assets = self.root / 'tmp/assets'
        assets.mkdir()
        names = ['swfence-24.10.ipk', 'luci-app-swfence-24.10.ipk']
        for name in names: (assets / name).write_bytes(b'mocked package; never actually installed')
        manifest = ''.join(f'{hashlib.sha256((assets / name).read_bytes()).hexdigest() if valid_hash else "0" * 64}  {name}\n' for name in names)
        (assets / 'SHA256SUMS').write_text(manifest)
        self.write('/bin/uclient-fetch', '''#!/bin/sh
while [ "$#" -gt 0 ]; do
 case "$1" in -O) shift; output=$1 ;; https://*) url=$1 ;; esac
 shift
done
cp "/tmp/assets/${url##*/}" "$output"
''')
        self.write('/bin/opkg', '#!/bin/sh\nprintf "%s\\n" "$*" >> /tmp/package-actions\n')
        self.write('/usr/sbin/swfence', '#!/bin/sh\nprintf "%s\\n" "$*" >> /tmp/setup-actions\n')

    def test_bootstrap_verifies_assets_before_package_install(self):
        self.bootstrap_fixture()
        self.native('/bin/sh', '/tmp/installer.sh', 'example/SWFence', 'v0.3.0')
        actions = (self.root / 'tmp/package-actions').read_text()
        self.assertIn('install ./swfence-24.10.ipk ./luci-app-swfence-24.10.ipk', actions)
        self.assertEqual((self.root / 'tmp/setup-actions').read_text().strip(), 'setup')
        self.assertEqual((self.root / 'etc/swfence/repository').read_text(), 'example/SWFence\n')

    def test_bootstrap_bad_checksum_never_installs(self):
        self.bootstrap_fixture(valid_hash=False)
        result = self.native('/bin/sh', '/tmp/installer.sh', 'example/SWFence', 'v0.3.0', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'tmp/package-actions').exists())
        self.assertFalse((self.root / 'tmp/setup-actions').exists())


if __name__ == '__main__': unittest.main(verbosity=2)
