'use strict';
'require baseclass';
'require rpc';
'require uci';
var ABOUT_REPO_URL = 'https://github.com/wzdddyy/iStoreOS-NN6000';
var ABOUT_DONATE_IMG = 'Author.png';	

function showDonate(ev) {
	ev.preventDefault();
	ev.stopPropagation();

	var old = document.getElementById('nn6000-donate-pop');
	if (old) {
		old.parentNode.removeChild(old);
		return;
	}

	var img = E('img', {
		src: L.resource(ABOUT_DONATE_IMG),
		alt: _('Donation QR Code'),
		style: 'width:260px;height:auto;background:#fff;border-radius:50%;padding:10px;box-shadow:0 10px 40px rgba(0,0,0,.55)'
	});
	img.addEventListener('click', function(e) { e.stopPropagation(); }, false);

	var pop = E('div', {
		id: 'nn6000-donate-pop',
		style: 'position:fixed;top:0;left:0;right:0;bottom:0;z-index:9999;background:rgba(0,0,0,.65);display:flex;align-items:center;justify-content:center'
	}, [ img ]);

	pop.addEventListener('click', function() { pop.parentNode.removeChild(pop); }, false);
	document.body.appendChild(pop);
}

function aboutLinks(buildstamp) {
	var style = 'display:inline-block;cursor:pointer;color:#2e7d32';
	var sepStyle = 'display:inline-block;margin:0 10px;color:#999';

	function link(url, text, handler) {
		var a = E('a', { style: style }, [ text ]);

		a.addEventListener('click', handler || function(ev) {
			ev.preventDefault();
			window.open(url, '_blank');
		}, false);

		return a;
	}

	function sep() {
		return E('span', { style: sepStyle }, [ '·' ]);
	}

	var items = [
		link(ABOUT_REPO_URL, 'Firmware Source'),
		sep(),
		link(ABOUT_REPO_URL + '/issues', 'Bug Report'),
		sep(),
		link(null, 'Support Author', showDonate)
	];

	if (buildstamp) {
		items.push(sep());
		items.push(E('span', { style: 'display:inline-block;color:#666' }, [ 'Build: ' + buildstamp ]));
	}

	return items;
}

var callGetUnixtime = rpc.declare({
	object: 'luci',
	method: 'getUnixtime',
	expect: { result: 0 }
});
var callLuciVersion = rpc.declare({
	object: 'luci',
	method: 'getVersion'
});
var callSystemBoard = rpc.declare({
	object: 'system',
	method: 'board'
});
var callSystemInfo = rpc.declare({
	object: 'system',
	method: 'info'
});
var callCPUInfo = rpc.declare({
	object: 'luci',
	method: 'getCPUInfo'
});
var callCPUUsage = rpc.declare({
	object: 'luci',
	method: 'getCPUUsage'
});
var callTempInfo = rpc.declare({
	object: 'luci',
	method: 'getTempInfo'
});
var callBuildTime = rpc.declare({
	object: 'luci',
	method: 'getBuildTime'
});
return baseclass.extend({
	title: _('System'),
	load: function() {
		return Promise.all([
			L.resolveDefault(callSystemBoard(), {}),
			L.resolveDefault(callSystemInfo(), {}),
			L.resolveDefault(callLuciVersion(), { revision: _('unknown version'), branch: 'LuCI' }),
			L.resolveDefault(callGetUnixtime(), 0),
			L.resolveDefault(callCPUInfo(), {}),
			L.resolveDefault(callCPUUsage(), {}),
			L.resolveDefault(callTempInfo(), {}),
			L.resolveDefault(callBuildTime(), {}),
			uci.load('system')
		]);
	},
	render: function(data) {
		var boardinfo   = data[0],
		    systeminfo  = data[1],
		    luciversion = data[2],
		    unixtime    = data[3],
		    cpuinfo     = data[4],
		    cpuusage    = data[5],
		    tempinfo    = data[6],
		    buildtime   = data[7].buildtime;
		luciversion = luciversion.branch + ' ' + luciversion.revision;
		var buildstamp = buildtime || null;
		var datestr = null;
		if (unixtime) {
			var date = new Date(unixtime * 1000),
				zn = uci.get('system', '@system[0]', 'zonename')?.replaceAll(' ', '_') || 'UTC',
				ts = uci.get('system', '@system[0]', 'clock_timestyle') || 0,
				hc = uci.get('system', '@system[0]', 'clock_hourcycle') || 0;
			datestr = new Intl.DateTimeFormat(undefined, {
				dateStyle: 'medium',
				timeStyle: (ts == 0) ? 'long' : 'full',
				hourCycle: (hc == 0) ? undefined : hc,
				timeZone: zn
			}).format(date);
		}
		var fields = [
			_('Hostname'),         boardinfo.hostname,
			_('Model'),            boardinfo.model,
			_('Architecture'),     cpuinfo.cpuinfo || boardinfo.system,
			_('Target Platform'),  (L.isObject(boardinfo.release) ? boardinfo.release.target : ''),
			_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || '') + ' / build by TheJoker',
			_('Kernel Version'),   boardinfo.kernel,
			_('Local Time'),       datestr,
			_('Uptime'),           systeminfo.uptime ? '%t'.format(systeminfo.uptime) : null,
			_('Load Average'),     Array.isArray(systeminfo.load) ? '%.2f, %.2f, %.2f'.format(
				systeminfo.load[0] / 65535.0,
				systeminfo.load[1] / 65535.0,
				systeminfo.load[2] / 65535.0
			) : null,
			_('CPU usage (%)'),    cpuusage.cpuusage,
			_('About'),            aboutLinks(buildstamp)
		];
		if (tempinfo.tempinfo) {
			fields.splice(6, 0, _('Temperature'));
			fields.splice(7, 0, tempinfo.tempinfo);
		}
		var table = E('table', { 'class': 'table' });
		for (var i = 0; i < fields.length; i += 2) {
			var value = (fields[i + 1] != null) ? fields[i + 1] : '?';
			var cell = E('td', { 'class': 'td left' });

			if (Array.isArray(value)) {
				for (var j = 0; j < value.length; j++)
					cell.appendChild((value[j] instanceof Node) ? value[j] : document.createTextNode(String(value[j])));
			}
			else if (value instanceof Node) {
				cell.appendChild(value);
			}
			else {
				cell.appendChild(document.createTextNode(String(value)));
			}

			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [ fields[i] ]),
				cell
			]));
		}
		return table;
	}
});
