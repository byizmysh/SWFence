'use strict';
'require view';
'require form';
'require rpc';
'require poll';
'require ui';
'require dom';

var getStatus = rpc.declare({ object: 'swfence', method: 'status', expect: {} });
var runDiagnostics = rpc.declare({ object: 'swfence', method: 'diagnostics', expect: {} });
var configure = rpc.declare({
	object: 'swfence', method: 'configure',
	params: [ 'enabled', 'macs', 'router_ip', 'lan_subnet', 'local_host', 'local_port', 'allowed_ips', 'allowed_domains' ],
	expect: {}
});

function statusText(s) {
	if (!s.configuration_valid) return _('Invalid saved configuration');
	if (s.last_error) return _('Last apply failed');
	if (!s.config_matches) return _('Settings not applied');
	if (!s.configured_enabled) return s.guard_present ? _('Guard still loaded — inspect rules') : _('Protection disabled');
	if (!s.guard_present) return _('Guard rules missing');
	if (!s.dns_running || !s.http_running) return _('Rules loaded — local service unavailable');
	return _('Rules loaded — verify console isolation');
}

function counterChange(current, previous) {
	if (!current || !current.available) return _('Daily statistics unavailable');
	if (!previous) return _('Waiting for next update');
	if (current.day !== previous.day) return _('New day');
	if (current.collected_since !== previous.collected_since) return _('Collection restarted');
	var bridge = Number(current.bridge_dropped), routed = Number(current.inet_dropped);
	var oldBridge = Number(previous.bridge_dropped), oldRouted = Number(previous.inet_dropped);
	if (![ bridge, routed, oldBridge, oldRouted ].every(function(n) { return Number.isSafeInteger(n) && n >= 0; }))
		return _('Counter change unavailable');
	if (bridge < oldBridge || routed < oldRouted) return _('Counters reset');
	return _('Bridge') + ': +' + (bridge - oldBridge) + ' / ' + _('Routed') + ': +' + (routed - oldRouted);
}

function summary(s, previous) {
	var today = s.daily_counters || {};
	var domains = s.domain_status || { state: 'not_configured' };
	var rows = [
		[ _('Status'), statusText(s) ],
		[ _('Isolated DNS / local HTTP'), (s.dns_running ? _('Running') : _('Stopped')) + ' / ' + (s.http_running ? _('Running') : _('Stopped')) ],
		[ _('Domain exceptions'), domains.state === 'not_configured' ? _('None') : domains.state === 'updated' ?
			String(domains.resolved) + ' ' + _('resolved') + ' / ' + String(domains.unresolved) + ' ' + _('unresolved') :
			({ pending: _('Waiting for DNS resolution'), expired: _('Expired — awaiting refresh'), error: _('Refresh failed') }[domains.state] || _('Unavailable')) ],
		[ _('Dropped today on bridge'), today.available ? String(today.bridge_dropped) : '—' ],
		[ _('Dropped today on routed path'), today.available ? String(today.inet_dropped) : '—' ],
		[ _('Drop counter change'), counterChange(today, previous && previous.daily_counters) ],
		[ _('Statistics day (router time)'), (today.day || '—') + ' · ' + (today.timezone || '—') ],
		[ _('Last status update'), new Date().toLocaleTimeString() ]
	];
	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, _('Status')),
		E('table', { 'class': 'table' }, rows.map(function(row) {
			return E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td' }, row[0]), E('td', { 'class': 'td' }, E('strong', {}, row[1])) ]);
		})),
		s.last_error ? E('p', { 'class': 'alert-message warning' }, s.last_error) : E('span'),
		domains.error ? E('p', { 'class': 'alert-message warning' }, domains.error) : E('span'),
		E('p', {}, _('Updates every 5 seconds. Daily statistics restart at midnight in the router timezone and after a router reboot. Counter changes show observed drops, not proof of complete console isolation.')),
		E('p', {}, _('Collected since: ') + (today.available ? today.collected_since_local : '—'))
	]);
}

function diagnosticRows(report) {
	var names = {
		configuration: _('Configuration'), firewall_syntax: _('Firewall syntax'),
		firewall_hooks: _('Firewall hooks'), applied_configuration: _('Applied settings'),
		dns_configuration: _('DNS configuration'), dns_local_answer: _('Local DNS answer'),
		dns_external_A: _('External DNS (IPv4)'), dns_external_AAAA: _('External DNS (IPv6)'),
		http_connection_check: _('Local connection check'), console_external_isolation: _('Console internet isolation')
	};
	return report.checks.map(function(c) {
		return E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, names[c.name] || c.name),
			E('td', { 'class': 'td' }, E('strong', {}, c.result === 'manual' ? _('ON CONSOLE') : c.result.toUpperCase())),
			E('td', { 'class': 'td' }, c.result === 'manual' ? _('Verify on the console that only your exceptions can access the internet. Live counters show observed drops.') : c.detail)
		]);
	});
}

function settingsMatch(expected, actual) {
	if (!actual) return false;
	var fields = [ 'enabled', 'router_ip', 'lan_subnet', 'local_host', 'local_port' ];
	function list(values) { return Array.from(new Set((values || []).map(function(v) { return String(v).toLowerCase(); }))).sort().join(' '); }
	return fields.every(function(key) { return String(expected[key] || '') === String(actual[key] || ''); }) &&
		[ 'macs', 'allowed_ips', 'allowed_domains' ].every(function(key) { return list(expected[key]) === list(actual[key]); });
}

return view.extend({
	load: function() { return getStatus(); },
	render: function(data) {
		var m = new form.JSONMap({ main: Object.assign({}, data.config, {
			macs: data.config.macs || [], allowed_ips: data.config.allowed_ips || [], allowed_domains: data.config.allowed_domains || []
		}) }, '', _('Local IPv4 access and optional internet exceptions. Other external traffic and IPv6 are blocked.'));
		var s = m.section(form.NamedSection, 'main', 'main', _('Protection settings'));
		s.addremove = false;
		var o = s.option(form.Flag, 'enabled', _('Enable protection'));
		o.rmempty = false;
		o = s.option(form.DynamicList, 'macs', _('Console MAC addresses'),
			_('Add Wi-Fi and every dock/Ethernet adapter you use. Random example MACs cannot be enabled.'));
		o.datatype = 'macaddr';
		o = s.option(form.Value, 'router_ip', _('Router LAN IPv4'),
			_('Enter this OpenWrt router\'s local IPv4 address on the console network, for example 192.168.1.1. Use this address in both console DNS fields.'));
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o = s.option(form.Value, 'lan_subnet', _('Allowed IPv4 subnet'), _('For example 192.168.1.0/24. Leave empty only for a strict single-service profile.'));
		o.datatype = 'cidr4';
		o = s.option(form.Value, 'local_host', _('Strict-profile host IPv4'));
		o.datatype = 'ip4addr';
		o.depends('lan_subnet', '');
		o = s.option(form.Value, 'local_port', _('Strict-profile TCP port'));
		o.datatype = 'port';
		o.depends('lan_subnet', '');
		o = s.option(form.DynamicList, 'allowed_domains', _('Allowed internet domains'),
			_('Optional. Add exact names such as example.com, without https://, paths or wildcards. Add required subdomains separately. Resolved IPv4 addresses refresh every 60 seconds and may be shared by other sites.'));
		o.datatype = 'hostname';
		o.placeholder = 'example.com';
		o = s.option(form.DynamicList, 'allowed_ips', _('Allowed internet IPv4 addresses'),
			_('Optional. Add individual IPv4 addresses, for example 1.1.1.1. All ports and protocols to these addresses are allowed; IPv6 remains blocked. Leave both lists empty to block all internet access.'));
		o.datatype = 'ip4addr';
		o.placeholder = '1.1.1.1';
		this.map = m;
		var live = E('div', {}, summary(data));
		var results = E('div');
		var previous = data;
		function updateStatus(s) {
			dom.content(live, summary(s, previous));
			previous = s;
		}
		poll.add(function() {
			return getStatus().then(updateStatus).catch(function(error) {
				previous = null;
				dom.content(live, E('p', { 'class': 'alert-message warning' }, _('Status unavailable: ') + error.message));
			});
		}, 5);
		var diagnosticsLive = false;
		var diagnosticsPending = null;
		function refreshDiagnostics() {
			if (diagnosticsPending) return diagnosticsPending;
			dom.content(diagnosticsState, _('Running local checks…'));
			results.setAttribute('aria-busy', 'true');
			diagnosticsPending = runDiagnostics().then(function(report) {
				dom.content(results, [ E('hr'), E('h3', {}, _('Diagnostics')), E('p', {}, report.scope),
					E('p', {}, _('Last check: ') + new Date().toLocaleTimeString()),
					E('table', { 'class': 'table' }, diagnosticRows(report)) ]);
			}).catch(function(error) {
				dom.content(results, [ E('hr'), E('h3', {}, _('Diagnostics')),
					E('p', { 'class': 'alert-message warning' }, _('Diagnostics unavailable: ') + error.message) ]);
			}).then(function() {
				diagnosticsPending = null;
				results.setAttribute('aria-busy', 'false');
				dom.content(diagnosticsState, diagnosticsLive ? _('Local checks refresh every 15 seconds while this page is open.') : _('Automatic diagnostics paused. Results show the last completed check.'));
			});
			return diagnosticsPending;
		}
		poll.add(function() { return diagnosticsLive ? refreshDiagnostics() : Promise.resolve(); }, 15);
		var diagnosticsButton = E('button', {
			'class': 'cbi-button',
			'click': ui.createHandlerFn(this, function() {
				diagnosticsLive = !diagnosticsLive;
				dom.content(diagnosticsButton, diagnosticsLive ? _('Stop live diagnostics') : _('Start live diagnostics'));
				dom.content(diagnosticsState, diagnosticsLive ? _('Local checks refresh every 15 seconds while this page is open.') : _('Automatic diagnostics paused. Results show the last completed check.'));
				return diagnosticsLive ? refreshDiagnostics() : Promise.resolve();
			})
		}, _('Start live diagnostics'));
		var diagnosticsState = E('p', {}, _('Start live diagnostics to refresh local checks every 15 seconds.'));
		var applyFeedback = E('div', { role: 'status', 'aria-live': 'polite', 'aria-atomic': 'true' });
		var settingsNode;
		var applyPending = null;
		function showApplyFeedback(title, detail) {
			dom.content(applyFeedback, E('p', {}, [ E('strong', {}, title), detail ? ' ' + detail : '' ]));
		}
		function setApplying(busy, label) {
			applyButton.disabled = busy || !L.hasViewPermission();
			applyButton.setAttribute('aria-busy', busy ? 'true' : 'false');
			applyButton.classList.toggle('spinning', busy);
			dom.content(applyButton, label);
			if (settingsNode) {
				if (busy) settingsNode.setAttribute('inert', '');
				else settingsNode.removeAttribute('inert');
			}
		}
		var applyButton = E('button', {
			'class': 'cbi-button',
			'disabled': !L.hasViewPermission(),
			'click': function() {
				if (!L.hasViewPermission()) return Promise.resolve();
				if (applyPending) return applyPending;
				var label = _('Apply protection settings');
				var accepted = false;
				var submitted = false;
				setApplying(true, _('Applying…'));
				showApplyFeedback(_('Applying settings…'), _('Please wait for the router to confirm.'));
				applyPending = Promise.resolve().then(function() { return m.save(function() {
					var c = m.data.get('json', 'main');
					var expected = {
						enabled: c.enabled || '0', router_ip: c.router_ip || '', lan_subnet: c.lan_subnet || '',
						local_host: c.local_host || '', local_port: c.local_port || '',
						macs: (c.macs || []).slice(), allowed_ips: (c.allowed_ips || []).slice(), allowed_domains: (c.allowed_domains || []).slice()
					};
					submitted = true;
					return configure(expected.enabled, expected.macs.join(' '), expected.router_ip,
						expected.lan_subnet, expected.local_host, expected.local_port,
						expected.allowed_ips.join(' '), expected.allowed_domains.join(' ')).then(function(result) {
						if (!result.ok) {
							label = _('Try again');
							showApplyFeedback(_('Settings were not applied.'), result.message);
							return getStatus().then(updateStatus).catch(function() {});
						}
						accepted = true;
						setApplying(true, _('Verifying…'));
						showApplyFeedback(_('Checking router status…'), _('The router accepted the settings.'));
						return getStatus().then(function(s) {
							updateStatus(s);
							if (!s.configuration_valid || !s.config_matches || s.last_error || !settingsMatch(expected, s.config)) {
								showApplyFeedback(_('Apply not confirmed.'), _('Refresh the page and check the router status.'));
								return;
							}
							if (!!s.guard_present !== (expected.enabled === '1') || (expected.enabled === '1' && (!s.dns_running || !s.http_running))) {
								showApplyFeedback(_('Settings saved; attention required.'), statusText(s));
								return;
							}
							label = _('Applied');
							showApplyFeedback(s.preview ? _('Preview settings applied.') : _('Settings applied.'),
								(s.preview ? _('Demo data only; no router was changed. ') : _('Confirmed by the router at ')) + new Date().toLocaleTimeString());
						});
					});
				}); }).catch(function(error) {
					label = _('Try again');
					showApplyFeedback(!submitted ? _('Settings were not sent.') : accepted ? _('Settings accepted; confirmation unavailable.') : _('Apply could not be confirmed.'),
						(error && error.message ? error.message + ' ' : '') + (!submitted ? _('Check the form fields and try again.') : _('Check the connection and router status before retrying.')));
				}).then(function() {
					applyPending = null;
					setApplying(false, label);
				});
				return applyPending;
			}
		}, _('Apply protection settings'));
		return m.render().then(function(node) {
			settingsNode = node;
			function markUnsaved() {
				if (applyPending) return;
				dom.content(applyButton, _('Apply protection settings'));
				showApplyFeedback(_('Unsaved changes.'), _('Apply to update protection.'));
			}
			settingsNode.addEventListener('input', markUnsaved);
			settingsNode.addEventListener('change', markUnsaved);
			var footer = [ E('span', {}, 'SWFence · ' + (data.version || '')) ];
			if (/^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(data.project_url || ''))
				footer.push(' · ', E('a', { href: data.project_url, target: '_blank', rel: 'noopener noreferrer' }, _('GitHub')));
			return E('div', {}, [
				E('h2', {}, E('strong', {}, _('SWFence'))),
				live, E('hr'), node,
				E('div', { 'class': 'cbi-page-actions' }, [ diagnosticsButton, ' ', applyButton ]),
				applyFeedback,
				diagnosticsState,
				results,
				E('p', { 'class': 'cbi-section-descr' }, _('Use the router LAN IPv4 in both console DNS fields and reconnect. Allow only a trusted local subnet.')),
				E('hr'), E('p', { 'class': 'cbi-section-descr' }, footer)
			]);
		});
	},
	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
