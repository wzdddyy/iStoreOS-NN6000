'use strict';
'require view';
'require rpc';
'require uci';
'require ui';

var callStatus = rpc.declare({ object: 'wzupdate', method: 'status' });
var callCheck = rpc.declare({ object: 'wzupdate', method: 'check' });
var callCancel = rpc.declare({ object: 'wzupdate', method: 'cancel' });
var callReboot = rpc.declare({ object: 'wzupdate', method: 'reboot' });

var STAGES = [ _('检查更新'), _('下载固件'), _('完整性校验'), _('写入备份分区'), _('写入校验'), _('等待重启') ];

var UI_VERSION = '1.0.0-34';

var PARTITION_URL = 'https://raw.githubusercontent.com/wzdddyy/iStoreOS-NN6000/main/partition/NN6000_UBOOT.bin';

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callStatus(), {}),
			L.resolveDefault(uci.load('wzupdate'), null)
		]);
	},

	render: function(data) {
		var st = data[0] || {};
		var self = this;

		this._refs = {};

		var href = L.resource('view/wzupdate/style.css') + '?v=' + UI_VERSION;
		if (!document.querySelector('link[href="' + href + '"]'))
			document.head.appendChild(E('link', { rel: 'stylesheet', href: href }));

		var page = E('div', { id: 'wzupdate-page' }, [
			E('div', { 'class': 'wz-head' }, [
				E('div', {}, [
					E('h2', { 'class': 'wz-title' }, [ _('在线更新') ]),
					E('div', { 'class': 'wz-sub' }, [ _('wzdddyy/iStoreOS-NN6000固件在线更新') ])
				]),
				E('div', { 'class': 'wz-actions' }, [
					this._refs.check = E('button', {
						'class': 'wz-btn',
						'click': function() {
							self._check();
						}
					}, [ _('检查更新') ]),
					this._refs.reboot = E('button', {
						'class': 'wz-btn primary',
						'click': function() { self._reboot(); }
					}, [ _('重启更新') ]),
					this._refs.cancel = E('button', {
						'class': 'wz-btn danger',
						'click': function() { self._cancel(); }
					}, [ _('撤回更新') ])
				])
			]),

			E('div', { 'class': 'wz-grid' }, [
				this._renderLocal(),
				this._renderRemote()
			]),

			this._renderFlow(),
			this._renderSettings()
		]);

		this._root = page;
		this._apply(st);

		this._startPolling();

		return page;
	},

	_renderLocal: function() {
		var r = this._refs;
		return E('div', { 'class': 'wz-card' }, [
			E('div', { 'class': 'wz-card-head' }, [
				E('div', { 'class': 'wz-card-title' }, [ _('本地固件') ]),
				r.localBadge = E('span', { 'class': 'wz-badge ok' }, [ E('i', { 'class': 'wz-dot' }), _('当前系统运行中') ])
			]),
			r.localVer = E('div', { 'class': 'wz-ver' }),
			E('div', { style: 'margin-top:10px' }, [
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('设备') ]), r.device = E('b') ]),
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('提交') ]), r.target = E('b') ]),
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('内核版本') ]), r.localKernel = E('b', { 'class': 'mono' }) ]),
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('编译时间') ]), r.localBuild = E('b', { 'class': 'mono' }) ]),
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('版本备份') ]), r.rollback = E('b') ]),
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('运行时长') ]), r.uptime = E('b') ])
			]),
			r.chips = E('div', { 'class': 'wz-chips' })
		]);
	},

	_renderRemote: function() {
		var r = this._refs;
		return E('div', { 'class': 'wz-card' }, [
			E('div', { 'class': 'wz-card-head' }, [
				E('div', { 'class': 'wz-card-title' }, [ _('在线版本') ]),
				r.remoteBadge = E('span', { 'class': 'wz-badge' }, [ E('i', { 'class': 'wz-dot' }), _('未检查') ])
			]),
			r.remoteVer = E('div', { 'class': 'wz-ver' }),
			E('div', { style: 'margin-top:10px' }, [
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('设备') ]), r.remoteDevice = E('b') ]),
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('提交') ]), r.remoteCommit = E('b', { 'class': 'mono' }) ]),
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('内核版本') ]), r.remoteKernel = E('b', { 'class': 'mono' }) ]),
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('编译时间') ]), r.remoteBuild = E('b', { 'class': 'mono' }) ]),
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('文件大小') ]), r.remoteSize = E('b') ]),
				E('div', { 'class': 'wz-kv' }, [ E('span', {}, [ _('上次检查') ]), r.checked = E('b') ])
			]),
			r.imageWarn = E('div', { 'class': 'wz-warnbar' }, [
				_('已选择无 WiFi 版：该固件不含无线驱动，更新后无线功能将不可用。')
			]),
			r.notes = E('ul', { 'class': 'wz-notes' })
		]);
	},

	_renderFlow: function() {
		var r = this._refs;
		var steps = [];
		for (var i = 0; i < STAGES.length; i++) {
			if (i > 0)
				steps.push(E('div', { 'class': 'wz-step-line' }));
			steps.push(E('div', { 'class': 'wz-step' }, [
				E('i', {}, [ String(i + 1) ]),
				E('span', {}, [ STAGES[i] ])
			]));
		}
		r.steps = steps;
		return E('div', { 'class': 'wz-card' }, [
			E('div', { 'class': 'wz-card-head', style: 'justify-content:flex-end' }, [
				r.flowBadge = E('span', { 'class': 'wz-badge' }, [ _('空闲') ])
			]),
			r.stepper = E('div', { 'class': 'wz-stepper' }, steps),
			r.progressFill = E('div', { 'class': 'wz-progress-fill' }),
			E('div', { 'class': 'wz-progress' }, [ r.progressFill ]),
			E('div', { 'class': 'wz-progress-meta' }, [
				E('span', {}, [ _('当前：'), r.stage = E('b', {}, [ _('空闲') ]) ]),
				r.progressExtra = E('span', {}, [ '—' ]),
				r.percent = E('b', {}, [ '0%' ])
			]),
			r.log = E('pre', { 'class': 'wz-log' })
		]);
	},

	_renderSettings: function() {
		var r = this._refs;
		var self = this;
		var s = 'wzupdate';

		r.enabled = E('input', {
			type: 'checkbox',
			checked: (uci.get(s, 'settings', 'enabled') === '1') ? '' : null,
			'change': function() { self._queueSave(); }
		});
		r.imageSel = E('select', {
			'class': 'wz-input',
			'change': function() { self._queueSave(); }
		}, [
			E('option', { value: 'auto' }, [ _('自动（推荐）') ]),
			E('option', { value: 'wifi' }, [ _('WiFi 版') ]),
			E('option', { value: 'nowifi' }, [ _('无 WiFi 版') ])
		]);
		r.imageSel.value = uci.get(s, 'settings', 'image') || 'auto';

		r.channelSel = E('select', {
			'class': 'wz-input',
			'change': function() { self._queueSave(); }
		}, [
			E('option', { value: 'auto' }, [ _('自动（直连失败走镜像）') ]),
			E('option', { value: 'github' }, [ _('仅 GitHub') ]),
			E('option', { value: 'mirror' }, [ _('仅镜像加速') ])
		]);
		r.channelSel.value = uci.get(s, 'settings', 'channel') || 'auto';

		r.keepConfig = E('input', {
			type: 'checkbox',
			checked: (uci.get(s, 'settings', 'keep_config') !== '0') ? '' : null,
			'change': function() { self._queueSave(); }
		});

		return r.settingsCard = E('div', { 'class': 'wz-card' }, [
			E('div', { 'class': 'wz-section' }, [ _('更新设置') ]),
			E('div', { 'class': 'wz-field' }, [
				E('div', {}, [
					E('div', { 'class': 'wz-field-label' }, [ _('启用自动更新') ]),
					E('div', { 'class': 'wz-field-help' }, [ _('每小时检测新版本，自动下载、校验并写入备份分区，重启后生效') ])
				]),
				E('div', { 'class': 'wz-field-control' }, [
					E('label', { 'class': 'wz-switch' }, [ r.enabled, E('span') ])
				])
			]),
			E('div', { 'class': 'wz-field' }, [
				E('div', {}, [
					E('div', { 'class': 'wz-field-label' }, [ _('更新固件类型') ]),
					E('div', { 'class': 'wz-field-help' }, [ _('默认与当前设备一致；无 WiFi 版不含无线驱动，仅在不需要无线功能时选择') ])
				]),
				E('div', { 'class': 'wz-field-control' }, [ r.imageSel ])
			]),
			E('div', { 'class': 'wz-field' }, [
				E('div', {}, [
					E('div', { 'class': 'wz-field-label' }, [ _('下载通道') ]),
					E('div', { 'class': 'wz-field-help' }, [ _('直连失败时自动尝试镜像地址；下载中断会从断点续传，写入前校验固件完整性') ])
				]),
				E('div', { 'class': 'wz-field-control' }, [ r.channelSel ])
			]),
			E('div', { 'class': 'wz-field' }, [
				E('div', {}, [
					E('div', { 'class': 'wz-field-label' }, [ _('更新保留配置') ]),
					E('div', { 'class': 'wz-field-help' }, [ _('默认保留当前配置；关闭后重启更新时会清空配置文件与已安装插件') ])
				]),
				E('div', { 'class': 'wz-field-control' }, [
					E('label', { 'class': 'wz-switch' }, [ r.keepConfig, E('span') ])
				])
			])
		]);
	},

	_apply: function(st) {
		var r = this._refs;
		if (this._root)
			this._root.classList.toggle('wz-dark', this._isDark());
		var local = st.local || {};
		var remote = st.remote || null;
		this._remoteChecked = (remote && remote.checked) ? remote.checked : null;
		var prog = st.progress || {};
		var pending = st.pending || null;
		var settings = st.settings || {};

		var phase = prog.phase || 'idle';
		var percent = parseInt(prog.percent, 10) || 0;
		var state = this._deriveState(st);

		r.localVer.innerHTML = '';
		r.localVer.appendChild(document.createTextNode(local.release || 'iStoreOS'));
		r.device.textContent = local.device
			? local.device + '(' + (local.firmware === 'nowifi' ? 'NOWIFI' : 'WIFI') + ')'
			: '—';
		r.target.textContent = local.commit || '—';
		r.localKernel.textContent = local.kernel || '—';
		r.localBuild.textContent = this._stamp(local.version) || '—';
		r.uptime.textContent = local.uptime || '—';
		r.rollback.textContent = pending
			? _('保留当前版本，可撤回本次更新')
			: _('备用分区随下次更新覆盖');
		r.localBadge.className = 'wz-badge ok';
		r.localBadge.innerHTML = '';
		r.localBadge.appendChild(E('i', { 'class': 'wz-dot' }));
		r.localBadge.appendChild(document.createTextNode(_('当前系统运行中')));

		r.chips.innerHTML = '';
		if (local.ab) {
			var keepCfg = settings.keepConfig !== false;
			r.chips.appendChild(E('span', { 'class': 'wz-chip ok' }, [ _('双分区安全更新') ]));
			r.chips.appendChild(E('span', { 'class': keepCfg ? 'wz-chip ok' : 'wz-chip err' }, [
				keepCfg ? _('更新保留配置') : _('更新不保留配置')
			]));
			r.chips.appendChild(E('span', { 'class': 'wz-chip ok' }, [ _('写入前校验固件') ]));
		}
		else {
			r.chips.appendChild(E('span', { 'class': 'wz-chip err' }, [ _('分区不支持安全更新') ]));
			r.chips.appendChild(E('span', { 'class': 'wz-chip err' }, [ _('在线更新已禁用') ]));
			r.chips.appendChild(E('a', {
				'class': 'wz-chip link',
				href: PARTITION_URL,
				target: '_blank',
				rel: 'noopener'
			}, [ _('下载支持分区 NN6000_UBOOT.bin') ]));
		}

		var hasRemote = !!remote;
		r.remoteVer.innerHTML = '';
		r.remoteVer.appendChild(document.createTextNode(
			hasRemote && remote.branch
				? remote.branch.replace(/^istoreos-/, 'iStoreOS ')
				: (hasRemote && remote.version ? this._stamp(remote.version) : (local.ab ? _('未检查') : _('不可用')))
		));
		var remoteFwLabel = settings.image === 'nowifi' ? 'NOWIFI' :
			(settings.image === 'wifi' ? 'WIFI' : (local.firmware === 'nowifi' ? 'NOWIFI' : 'WIFI'));
		r.remoteDevice.textContent = local.device
			? local.device + '(' + remoteFwLabel + ')'
			: '—';
		r.remoteCommit.textContent = hasRemote && remote.commit ? remote.commit : '—';
		r.remoteKernel.textContent = hasRemote && remote.kernel ? remote.kernel : '—';
		r.remoteBuild.textContent = hasRemote
			? (remote.build || this._stamp(remote.version) || '—')
			: '—';
		r.remoteSize.textContent = hasRemote && remote.size > 0 ? this._size(remote.size) : '—';
		r.checked.textContent = hasRemote && remote.checked ? remote.checked : '—';
		r.imageWarn.style.display = (settings.image === 'nowifi') ? '' : 'none';

		r.notes.innerHTML = '';
		var notes = [];
		if (!local.ab) {
			notes.push(_('当前分区表没有可用的备份分区，无法安全写入新固件。'));
			if (local.abMissing)
				notes.push(_('未识别的分区：') + local.abMissing);
			if (local.labels)
				notes.push(_('已识别的分区：') + local.labels);
			notes.push(_('请先刷入支持双分区更新的分区镜像后再使用在线更新。'));
		}
		else if (hasRemote && remote.notes) {
			notes.push(remote.notes);
		}
		else if (hasRemote) {
			notes.push(_('在线版本信息已获取。'));
		}
		else {
			notes.push(_('尚未检查在线版本，点击「检查更新」开始。'));
		}
		notes.push(_('写入完成并校验通过后，需要手动重启才会切换到新版本。'));
		notes.forEach(function(n) { r.notes.appendChild(E('li', {}, [ n ])); });

		var badge = { text: _('空闲'), kind: '' };
		if (state === 'unsupported')
			badge = { text: _('不支持在线更新'), kind: 'err' };
		else if (state === 'failed')
			badge = { text: _('更新失败'), kind: 'err' };
		else if (state === 'busy')
			badge = { text: _('正在更新'), kind: 'info' };
		else if (state === 'pending')
			badge = { text: _('已就绪，待重启'), kind: 'warn' };
		else if (state === 'available')
			badge = { text: _('发现新版本'), kind: 'info' };
		else if (phase === 'idle')
			badge = { text: hasRemote ? _('已是最新') : _('未检查'), kind: hasRemote ? 'ok' : '' };

		r.remoteBadge.className = 'wz-badge ' + badge.kind;
		r.remoteBadge.innerHTML = '';
		r.remoteBadge.appendChild(E('i', { 'class': 'wz-dot' }));
		r.remoteBadge.appendChild(document.createTextNode(badge.text));

		var stage = this._stageOf(state, phase, percent);
		var steps = r.stepper.querySelectorAll('.wz-step');
		for (var i = 0; i < steps.length; i++) {
			steps[i].classList.toggle('done', stage.index >= 0 && i < stage.index);
			steps[i].classList.toggle('active', i === stage.index);
		}
		r.progressFill.style.width = Math.max(0, Math.min(100, percent)) + '%';
		r.percent.textContent = Math.round(percent) + '%';
		r.stage.textContent = stage.index >= 0 ? STAGES[stage.index] : _('空闲');

		var flow = { text: _('空闲'), kind: '' };
		if (state === 'unsupported')
			flow = { text: _('不可用'), kind: 'err' };
		else if (state === 'failed')
			flow = { text: _('失败'), kind: 'err' };
		else if (state === 'pending')
			flow = { text: _('待重启'), kind: 'warn' };
		else if (state === 'available')
			flow = { text: _('待开始'), kind: 'info' };
		else if (state === 'busy')
			flow = { text: STAGES[stage.index] + ' ' + Math.round(percent) + '%', kind: 'info' };
		r.flowBadge.className = 'wz-badge ' + flow.kind;
		r.flowBadge.textContent = flow.text;

		r.progressExtra.textContent = prog.message || '—';

		var logs = st.log || [];
		r.log.textContent = logs.length ? logs.join('\n') : _('暂无日志');
		r.log.scrollTop = r.log.scrollHeight;

		var busy = (state === 'busy');
		var supported = !!local.ab;
		r.check.textContent = _('检查更新');
		r.check.disabled = busy || state === 'pending' || !supported;
		if (this._checking) {
			r.check.textContent = _('检查中…');
			r.check.disabled = true;
		}
		r.check.style.display = (state === 'pending') ? 'none' : '';
		r.reboot.style.display = (state === 'pending') ? '' : 'none';
		r.cancel.style.display = (state === 'pending') ? '' : 'none';

		r.enabled.disabled = !supported;
		r.imageSel.disabled = !supported;
		r.channelSel.disabled = !supported;
		r.keepConfig.disabled = !supported;
		r.settingsCard.classList.toggle('wz-off', !supported);

	},

	_startPolling: function() {
		var self = this;

		if (this._timer)
			clearInterval(this._timer);

		this._timer = setInterval(function() {
			if (!self._root || !document.body.contains(self._root)) {
				clearInterval(self._timer);
				self._timer = null;
				return;
			}

			L.resolveDefault(callStatus(), null).then(function(s) {
				if (s)
					self._apply(s);
			});
		}, 3000);
	},

	_isDark: function() {
		var root = document.documentElement;
		var mode = root.getAttribute('data-argon-mode') || root.getAttribute('data-darkmode');
		if (mode === 'dark' || mode === 'true')
			return true;
		if (mode === 'light' || mode === 'false')
			return false;
		if (document.body.classList.contains('dark'))
			return true;

		var parse = function(value) {
			var m = /rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+))?/.exec(value || '');
			if (!m)
				return null;
			return {
				lum: (0.299 * +m[1] + 0.587 * +m[2] + 0.114 * +m[3]) / 255,
				alpha: (m[4] === undefined) ? 1 : parseFloat(m[4])
			};
		};

		var probes = [
			document.querySelector('.main-right'),
			document.getElementById('maincontent'),
			document.body
		];
		for (var i = 0; i < probes.length; i++) {
			if (!probes[i])
				continue;
			var bg = parse(window.getComputedStyle(probes[i]).backgroundColor);
			if (bg && bg.alpha > 0.1)
				return bg.lum < 0.5;
		}

		var fg = parse(window.getComputedStyle(document.body).color);
		if (fg)
			return fg.lum > 0.6;
		return false;
	},

	_deriveState: function(st) {
		var local = st.local || {};
		var prog = st.progress || {};
		var phase = prog.phase || 'idle';
		if (!local.ab)
			return 'unsupported';
		if (st.pending)
			return 'pending';
		if (phase === 'error')
			return 'failed';
		if (phase === 'checking' || phase === 'downloading' || phase === 'verifying' || phase === 'writing')
			return 'busy';
		if (st.remote && st.remote.newer)
			return 'available';
		return 'latest';
	},

	_stageOf: function(state, phase, percent) {
		if (state === 'unsupported')
			return { index: -1 };
		if (state === 'pending')
			return { index: 5 };
		if (state === 'busy') {
			if (phase === 'checking')
				return { index: 0 };
			if (phase === 'downloading')
				return { index: 1 };
			if (phase === 'verifying')
				return { index: 2 };
			if (phase === 'writing')
				return { index: percent >= 88 ? 4 : 3 };
		}
		if (state === 'failed')
			return { index: phase === 'verifying' ? 2 : (phase === 'writing' ? 4 : -1) };
		return { index: -1 };
	},

	_stamp: function(value) {
		return (value || '').replace(/-/g, '.').replace(/:/g, '.').replace(' ', '_');
	},

	_size: function(bytes) {
		if (!bytes)
			return '—';
		if (bytes >= 1048576)
			return (bytes / 1048576).toFixed(1) + ' MB';
		if (bytes >= 1024)
			return (bytes / 1024).toFixed(0) + ' KB';
		return bytes + ' B';
	},

	_check: function() {
		var self = this;
		if (this._checking)
			return Promise.resolve();

		this._checking = true;
		this._refs.check.disabled = true;
		this._refs.check.textContent = _('检查中…');

		var done = function() {
			self._checking = false;
			return L.resolveDefault(callStatus(), null).then(function(s) {
				if (s)
					self._apply(s);
			});
		};

		return callCheck().catch(function() {
			ui.addNotification(null, E('p', {}, [ _('检查更新失败，请查看日志') ]), 'error');
		}).then(function() {
			return self._waitCheck();
		}).then(done, done);
	},

	_waitCheck: function() {
		var before = this._remoteChecked;
		var start = Date.now();
		var seen = false;

		return new Promise(function(resolve) {
			var tick = function() {
				L.resolveDefault(callStatus(), null).then(function(s) {
					var phase = (s && s.progress) ? (s.progress.phase || 'idle') : 'idle';

					if (phase === 'checking')
						seen = true;

					if ((seen && phase !== 'checking') || phase === 'error' ||
						(!seen && s && s.remote && s.remote.checked && s.remote.checked !== before))
						return resolve();

					if (Date.now() - start > 120000 || (!seen && Date.now() - start > 10000))
						return resolve();

					setTimeout(tick, 800);
				});
			};

			setTimeout(tick, 800);
		});
	},

	_reboot: function() {
		var self = this;
		if (!window.confirm(_('确认重启并切换到新版本？重启期间网络会中断。')))
			return;
		return callReboot().then(function(r) {
			if (!r || r.ok)
				self._waitReboot();
		});
	},

	_cancel: function() {
		if (!window.confirm(_('确认撤回已写入的更新？')))
			return;
		return callCancel();
	},

	_waitReboot: function() {
		if (this._waiting)
			return;
		this._waiting = true;

		if (this._timer) {
			clearInterval(this._timer);
			this._timer = null;
		}

		var tip = E('div', { 'class': 'wz-reboot-tip' },
			[ _('设备正在重启，页面会自动刷新，请稍候…') ]);
		this._root.insertBefore(tip, this._root.firstChild);

		// 先等设备下线，再等它重新上线，避免重启还没开始就刷新页面
		var down = false, tries = 0;
		var timer = setInterval(function() {
			if (++tries > 120) {
				clearInterval(timer);
				tip.textContent = _('等待设备超时，请手动刷新页面');
				return;
			}

			L.resolveDefault(callStatus(), null).then(function(s) {
				if (!s) {
					down = true;
					return;
				}
				if (down) {
					clearInterval(timer);
					location.reload();
				}
			});
		}, 3000);
	},

	_queueSave: function() {
		var self = this;
		if (this._saveTimer)
			clearTimeout(this._saveTimer);
		this._saveTimer = setTimeout(function() { self._persist(); }, 300);
	},

	_persist: function() {
		var self = this;
		var s = 'wzupdate';
		var want = this._refs.enabled.checked;
		uci.set(s, 'settings', 'enabled', want ? '1' : '0');
		uci.set(s, 'settings', 'auto', want ? '1' : '0');
		uci.set(s, 'settings', 'image', this._refs.imageSel.value);
		uci.set(s, 'settings', 'channel', this._refs.channelSel.value);
		uci.set(s, 'settings', 'keep_config', this._refs.keepConfig.checked ? '1' : '0');
		return uci.save().then(function() {
			return uci.apply();
		}).then(function() {
			if (ui.changes && typeof ui.changes.init === 'function')
				ui.changes.init();

			return L.resolveDefault(callStatus(), null).then(function(st) {
				if (!st || !st.settings)
					throw new Error('status failed');
				if (!!st.settings.enabled !== want) {
					self._refs.enabled.checked = !!st.settings.enabled;
					throw new Error('verify failed');
				}
				ui.addNotification(null, E('p', {}, [ _('设置已保存并生效') ]), 'info');
			});
		}).catch(function() {
			ui.addNotification(null, E('p', {}, [ _('设置保存失败，请重试') ]), 'error');
		});
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
