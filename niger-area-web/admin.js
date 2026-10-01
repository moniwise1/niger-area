// Niger Area owner dashboard. Every call is an admin_* server function that refuses non-owners.
const TABS = [['overview', 'Overview'], ['players', 'Players'], ['reports', 'Reports'], ['gist', 'Gist'], ['network', 'Network & custody'],
  ['redemptions', 'Airtime'], ['log', 'Sanctions log'], ['settings', 'Settings'], ['security', 'Security']];
const KINDS = [['warn', 'Warn'], ['mute', 'Mute (days)'], ['suspend', 'Suspend (days)'], ['fine', 'Fine (coins)'], ['grant', 'Grant coins'],
  ['remove_office', 'Remove from office'], ['disqualify', 'Disqualify from ballot'], ['reset_rep', 'Reset reputation'], ['ban', 'Ban'],
  ['unmute', 'Unmute'], ['unsuspend', 'Unsuspend'], ['unban', 'Unban']];
let user = null, ok = false, tab = 'overview', A = {}, busy = false, detail = null, search = '', gate = null, idle = Date.now();

async function call(fn, args) {
  const { data, error } = await sb.rpc(fn, args || {});
  if (error) { if (/Owner password required/.test(error.message)) { await checkGate(); render(); } throw error; }
  return data;
}
async function checkGate() { try { gate = (await sb.rpc('admin_password_status')).data; } catch (_) { gate = null; } }
async function load() {
  try {
    if (tab === 'overview') A.dash = await call('admin_dashboard');
    if (tab === 'players') A.players = await call('admin_players', { p_search: search, p_limit: 200 });
    if (tab === 'reports') A.reports = await call('admin_reports');
    if (tab === 'gist') A.posts = await call('admin_posts', { p_limit: 150 });
    if (tab === 'network') A.net = await call('admin_ip_report');
    if (tab === 'redemptions') A.red = await call('admin_redemptions');
    if (tab === 'log') A.log = await call('admin_sanctions_log', { p_limit: 200 });
    if (tab === 'settings') A.dash = A.dash || await call('admin_dashboard');
    if (tab === 'security') A.logins = await call('admin_login_history');
  } catch (e) { toast(e.message, true); }
}
async function act(fn, args, msg) {
  if (busy) return; busy = true;
  try { await call(fn, args); toast(msg); if (detail) detail.data = await call('admin_player', { p_id: detail.id }); await load(); render(); }
  catch (e) { toast(e.message, true); } finally { busy = false; }
}

/* ---------- charts: single series, one hue, hover readout, table view ---------- */
function columns(rows, label) {
  const max = Math.max(1, ...rows.map(r => r.n)), total = rows.reduce((a, r) => a + r.n, 0);
  const d = s => new Date(s).toLocaleDateString('en-NG', { day: 'numeric', month: 'short' });
  return `<div class="cols" role="img" aria-label="${esc(label)}: ${total} in total">${rows.map(r => `<div class="c" tabindex="0"><i style="height:${r.n / max * 100}%"></i><span class="tip">${d(r.d)}: ${fmt(r.n)}</span></div>`).join('')}</div>
    <div class="axis"><span>${d(rows[0].d)}</span><span>peak ${fmt(max)}</span><span>${d(rows[rows.length - 1].d)}</span></div>
    <details><summary>Show as table</summary><div class="table-wrap"><table style="min-width:0"><tbody>${rows.slice().reverse().map(r => `<tr><td>${d(r.d)}</td><td class="num">${fmt(r.n)}</td></tr>`).join('')}</tbody></table></div></details>`;
}
function hbars(rows, neg) {
  if (!rows.length) return '<div class="empty">Nothing yet today.</div>';
  const max = Math.max(...rows.map(r => Math.abs(r.total)));
  return rows.map(r => `<div class="hbar ${neg ? 'neg' : ''}"><span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(r.reason.replace(/_/g, ' '))}</span><div class="t"><i style="width:${Math.abs(r.total) / max * 100}%"></i></div><span class="num">${fmt(Math.abs(r.total))}</span></div>`).join('');
}

/* ---------- views ---------- */
function vOverview() {
  const d = A.dash; if (!d) return '<div class="empty">Loading…</div>';
  const p = d.players, e = d.economy, g = d.engagement, rv = d.revenue;
  const k = (v, l) => `<div class="kpi"><b>${v}</b><span>${l}</span></div>`;
  return `<div class="row between"><div><span class="eyebrow">Game day ${d.game.day}${d.game.playtest ? ' · playtest mode on' : ''}</span><h2>Overview</h2></div><button class="btn" data-act="refresh">Refresh</button></div>
  <div class="kpis">${k(fmt(p.total), 'Citizens')}${k(fmt(p.today), 'Joined today')}${k(fmt(p.week), 'Joined this week')}${k(fmt(p.online_now), 'Online now')}
    ${k(fmt(p.active_today), 'Active today')}${k(fmt(p.active_week), 'Active this week')}${k(fmt(p.banned), 'Banned')}${k(fmt(p.suspended), 'Suspended')}</div>
  ${d.flags.length ? `<div class="panel alert"><h3>Needs attention · ${d.flags.length}</h3>${d.flags.map(f => `<div class="li flag-row"><div class="grow">${f.name ? `<b>${esc(f.name)}</b> · ` : ''}${esc(f.why)}</div>${f.id ? `<button class="btn sm" data-act="open" data-a="${f.id}">Open</button>` : ''}</div>`).join('')}</div>` : '<div class="banner">No suspicious activity flagged.</div>'}
  <div class="grid">
    <div class="panel"><h3>Sign-ups per day</h3><p class="small muted">Last 30 days, West Africa Time</p>${columns(d.signups_30d, 'Sign-ups per day')}</div>
    <div class="panel"><h3>Active players per day</h3><p class="small muted">Players with any coin activity, last 14 days</p>${columns(d.active_14d, 'Active players per day')}</div>
  </div>
  <div class="kpis">${k(fmt(e.coins), 'Coins in wallets')}${k(fmt(e.stash), 'Coins in stashes')}${k(fmt(e.cp), 'Civic points owed')}${k(fmt(e.bought), 'Coins ever bought')}
    ${k('₦' + fmt(rv.total_naira), 'Revenue, all time')}${k('₦' + fmt(rv.month_naira), 'Revenue, 30 days')}${k(fmt(rv.paid_count), 'Paid purchases')}${k(fmt(d.redemptions.pending), 'Airtime requests waiting')}</div>
  <div class="grid">
    <div class="panel"><h3>Where coins came from today</h3>${hbars(e.sources_today)}</div>
    <div class="panel"><h3>Where coins went today</h3>${hbars(e.sinks_today, true)}</div>
  </div>
  <div class="kpis">${k(fmt(g.posts_today), 'Gist posts today')}${k(fmt(g.hustles_today), 'Hustles today')}${k(fmt(g.trivia_today), 'Trivia answers today')}${k(fmt(g.votes_total), 'Citizen votes cast')}
    ${k(fmt(g.streak_7plus), 'On a 7+ day streak')}${k(fmt(g.parties), 'Parties')}${k(`${g.offices_held}/${g.offices_total}`, 'Offices held by players')}</div>
  <div class="panel"><h3>Next elections</h3><div class="table-wrap"><table><thead><tr><th>Office</th><th>Polls</th><th>Candidates</th><th>Citizen votes</th></tr></thead><tbody>
    ${d.upcoming.map(u => `<tr><td>${esc(u.place)}</td><td class="num">Day ${u.poll_day}</td><td class="num">${u.candidates}</td><td class="num">${u.votes}</td></tr>`).join('')}</tbody></table></div></div>`;
}
function vPlayers() {
  const rows = A.players || [];
  const st = p => p.banned ? '<span class="chip pill-bad">Banned</span>' : p.detained_until && new Date(p.detained_until) > new Date() ? '<span class="chip pill-bad">Custody</span>'
    : p.suspended_until && new Date(p.suspended_until) > new Date() ? '<span class="chip pill-warn">Suspended</span>' : p.muted_until && new Date(p.muted_until) > new Date() ? '<span class="chip pill-warn">Muted</span>' : '<span class="chip pill-good">Active</span>';
  return `<div class="stack"><h2>Players</h2><p class="lede">Search by name, email, IP address or VIN. Newest first.</p></div>
  <form class="row" style="flex-wrap:nowrap" onsubmit="event.preventDefault();ACT.search()"><input id="s" type="search" value="${esc(search)}" placeholder="Name, email, IP or VIN"><button class="btn primary" type="submit">Search</button></form>
  <div class="panel"><div class="table-wrap"><table><thead><tr><th>Citizen</th><th>Email</th><th>Location</th><th>Joined</th><th>Last seen</th><th>Coins</th><th>Rep</th><th>Status</th></tr></thead><tbody>
    ${rows.map(p => `<tr><td><button class="linkish" data-act="open" data-a="${p.id}">${esc(p.name)}</button><div class="tiny muted">${esc(p.party || 'No party')}${p.office ? ' · ' + esc(p.office) : ''}</div></td>
      <td class="small">${esc(p.email)}</td><td class="small">${esc(p.lga)}, ${esc(p.state)}</td><td class="small">${ago(p.created_at)}</td><td class="small">${p.last_seen ? ago(p.last_seen) : '—'}</td>
      <td class="num">${fmt(p.coins)}</td><td class="num">${p.rep}</td><td>${st(p)}</td></tr>`).join('') || '<tr><td colspan="8" class="muted">No players found.</td></tr>'}
  </tbody></table></div></div>`;
}
function vDetail() {
  if (!detail) return '';
  const d = detail.data; if (!d) return `<div class="scrim" data-scrim><div class="sheet"><div class="empty">Loading…</div></div></div>`;
  const c = d.citizen, w = d.wallet;
  return `<div class="scrim" data-scrim><div class="sheet" role="dialog" aria-modal="true" style="max-width:720px">
    <div class="row between"><div class="row">${avatar(c.avatar_url, c.display_name, 'lg')}<div><h3>${esc(c.display_name)}</h3><div class="small muted">${esc(c.email)} · VIN ${esc(c.vin)}</div>
      <div class="small muted">Signed up ${watTime(c.created_at)} · IP ${esc(c.signup_ip || '—')} · last IP ${esc(c.last_ip || '—')}</div></div></div><button class="btn sm" data-act="close">Close</button></div>
    <div class="kpis"><div class="kpi"><b>${fmt(w.coins)}</b><span>Coins</span></div><div class="kpi"><b>${fmt(w.stash)}</b><span>Stash</span></div><div class="kpi"><b>${fmt(w.cp)}</b><span>Civic pts</span></div>
      <div class="kpi"><b>${Math.floor(c.rep)}</b><span>Reputation</span></div><div class="kpi"><b>${Math.round(c.scandal)}</b><span>Scandal</span></div><div class="kpi"><b>${fmt(w.purchased_total)}</b><span>Coins bought</span></div></div>
    ${c.detained_until && new Date(c.detained_until) > new Date() ? `<div class="banner">In custody until ${watTime(c.detained_until)} for ${esc(c.detained_charge)}. <button class="btn sm" data-act="release" data-a="${c.id}">Release now</button></div>` : ''}
    <div class="panel"><h3>Take action</h3><p class="small muted">The player sees the reason. Most actions also appear in the news.</p>
      <div class="row" style="flex-wrap:nowrap"><label class="f" style="flex:2">Action<select id="sx-kind">${KINDS.map(([k, l]) => `<option value="${k}">${l}</option>`).join('')}</select></label>
        <label class="f" style="flex:1">Days / coins<input id="sx-n" type="number" min="1" placeholder="e.g. 3"></label></div>
      <label class="f">Reason<input id="sx-reason" type="text" maxlength="200" placeholder="e.g. Multiple accounts"></label>
      <div><button class="btn warn" data-act="sanction" data-a="${c.id}">Apply</button></div></div>
    <div class="grid">
      <div class="panel"><h3>Sanctions</h3>${d.sanctions.map(s => `<div class="li small"><div class="grow"><b>${esc(s.kind)}</b> · ${esc(s.reason)}</div><span class="tiny muted">${ago(s.created_at)}</span></div>`).join('') || '<div class="empty">Clean record.</div>'}</div>
      <div class="panel"><h3>Recent posts</h3>${d.posts.map(p => `<div class="li small"><div class="grow">${esc(p.body)}${p.deleted ? ' <span class="chip pill-bad">deleted</span>' : ''}</div><span class="tiny muted">${ago(p.created_at)}</span></div>`).join('') || '<div class="empty">No posts.</div>'}</div>
    </div>
    <div class="panel"><h3>Ledger</h3><div class="table-wrap"><table><thead><tr><th>When</th><th>What</th><th>Currency</th><th>Change</th><th>Balance</th></tr></thead><tbody>
      ${d.ledger.map(l => `<tr><td class="small">${ago(l.created_at)}</td><td class="small">${esc(l.reason.replace(/_/g, ' '))}</td><td class="small">${l.cur}</td><td class="num" style="color:var(--${l.delta >= 0 ? 'good' : 'bad'})">${l.delta >= 0 ? '+' : ''}${fmt(l.delta)}</td><td class="num">${fmt(l.balance_after)}</td></tr>`).join('')}</tbody></table></div></div>
  </div></div>`;
}
function vReports() {
  const r = A.reports || [];
  return `<div class="stack"><h2>Reports</h2><p class="lede">Players reporting other players. You can read only the conversation between the two people in a report.</p></div>
  ${r.map(x => `<div class="panel"><div class="row between"><div><b>${esc(x.reporter)}</b> reported <button class="linkish" data-act="open" data-a="${x.target_id}">${esc(x.target)}</button> <span class="chip ${x.times_reported > 2 ? 'pill-bad' : ''}">reported ${x.times_reported}×</span></div><span class="tiny muted">${ago(x.created_at)}</span></div>
    <p>${esc(x.reason)}</p>
    ${A.convo?.id === x.id ? `<div class="thread" style="max-height:260px">${A.convo.msgs.map(m => `<div class="bubble ${m.sender_id === x.target_id ? 'them' : 'me'}">${esc(m.body)}<time>${m.sender_id === x.target_id ? esc(x.target) : esc(x.reporter)} · ${ago(m.created_at)}</time></div>`).join('') || '<div class="empty">They have not messaged each other.</div>'}</div>` : ''}
    <div class="row"><button class="btn sm" data-act="convo" data-a="${x.id}">Read their conversation</button><button class="btn sm warn" data-act="open" data-a="${x.target_id}">Sanction ${esc(x.target)}</button><button class="btn sm" data-act="closereport" data-a="${x.id}">Close report</button></div></div>`).join('') || '<div class="empty">No open reports.</div>'}`;
}
function vGist() {
  return `<div class="stack"><h2>Gist moderation</h2><p class="lede">Latest posts across the national feed and party rooms.</p></div>
  <div class="panel">${(A.posts || []).map(p => `<div class="li" style="align-items:flex-start;${p.deleted ? 'opacity:.5' : ''}"><div class="grow"><div class="row small"><button class="linkish" data-act="open" data-a="${p.author_id}">${esc(p.name)}</button><span class="chip">${esc(p.room)}</span>${p.election_id ? '<span class="chip pill-warn">Campaign</span>' : ''}<span class="tiny muted">${ago(p.created_at)}</span></div><div style="white-space:pre-wrap">${esc(p.body)}</div></div>
    ${p.deleted ? '<span class="chip">Deleted</span>' : `<button class="btn sm warn" data-act="delpost" data-a="${p.id}">Delete</button>`}</div>`).join('') || '<div class="empty">No posts yet.</div>'}</div>`;
}
function vNetwork() {
  const n = A.net; if (!n) return '<div class="empty">Loading…</div>';
  return `<div class="stack"><h2>Network &amp; custody</h2><p class="lede">One citizen per IP address. Mobile networks in Nigeria often share one IP across many people, so allow an IP when the players are clearly different people.</p></div>
  <div class="grid">
    <div class="panel"><h3>Shared IP addresses</h3>${n.shared.map(s => `<div class="li"><div class="grow"><span class="num">${esc(s.ip)}</span> · ${s.accounts} accounts${s.allowed ? ' <span class="chip pill-good">allowed</span>' : ''}
      <div class="small">${s.players.map(p => `<button class="linkish" data-act="open" data-a="${p.id}">${esc(p.name)}</button>`).join(', ')}</div></div>${s.allowed ? '' : `<button class="btn sm" data-act="allow" data-a="${esc(s.ip)}">Allow</button>`}</div>`).join('') || '<div class="empty">No shared IPs.</div>'}
      <form class="row" style="flex-wrap:nowrap" onsubmit="event.preventDefault();ACT.allow(document.getElementById('ip-new').value)"><input id="ip-new" type="text" placeholder="Allow an IP before people sign up"><button class="btn" type="submit">Allow</button></form></div>
    <div class="panel"><h3>In custody now</h3><p class="small muted">${n.arrests_today} arrests and ${n.decrees_today} decrees today.</p>${n.detained.map(x => `<div class="li"><div class="grow"><button class="linkish" data-act="open" data-a="${x.id}">${esc(x.name)}</button> · ${esc(x.charge)}<div class="tiny muted">by ${esc(x.by || 'the owner')} · until ${watTime(x.detained_until)}</div></div><button class="btn sm" data-act="release" data-a="${x.id}">Release</button></div>`).join('') || '<div class="empty">Nobody is in custody.</div>'}</div>
  </div>
  <div class="panel"><h3>Allowed IPs</h3>${n.allowlist.map(a => `<div class="li small"><span class="num">${esc(a.ip)}</span><span class="muted">${esc(a.note || '')}</span></div>`).join('') || '<div class="empty">None.</div>'}</div>`;
}
function vRedemptions() {
  const r = A.red || [];
  return `<div class="stack"><h2>Airtime requests</h2><p class="lede">Send the airtime yourself, then mark it paid. Rejecting refunds the civic points.</p></div>
  <div class="panel"><div class="table-wrap"><table><thead><tr><th>Citizen</th><th>Phone</th><th>Amount</th><th>ID check</th><th>Asked</th><th></th></tr></thead><tbody>
    ${r.map(x => `<tr><td><button class="linkish" data-act="open" data-a="${x.citizen_id}">${esc(x.name)}</button></td><td class="num">${esc(x.phone)}</td><td class="num">₦${fmt(x.naira)}</td><td>${x.kyc_level >= 2 ? '<span class="chip pill-good">Verified</span>' : '<span class="chip pill-bad">Missing</span>'}</td><td class="small">${ago(x.created_at)}</td>
      <td><div class="row"><button class="btn sm primary" data-act="paid" data-a="${x.id}">Mark paid</button><button class="btn sm warn" data-act="reject" data-a="${x.id}">Reject</button></div></td></tr>`).join('') || '<tr><td colspan="6" class="muted">No requests waiting.</td></tr>'}
  </tbody></table></div></div>`;
}
function vLog() {
  return `<div class="stack"><h2>Sanctions log</h2></div><div class="panel"><div class="table-wrap"><table><thead><tr><th>When</th><th>Citizen</th><th>Action</th><th>Reason</th><th>Amount / until</th></tr></thead><tbody>
    ${(A.log || []).map(s => `<tr><td class="small">${watTime(s.created_at)}</td><td><button class="linkish" data-act="open" data-a="${s.citizen_id}">${esc(s.name)}</button></td><td>${esc(s.kind)}</td><td class="small">${esc(s.reason)}</td><td class="small">${s.amount ? fmt(s.amount) : s.until ? watTime(s.until) : ''}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">No sanctions yet.</td></tr>'}
  </tbody></table></div></div>`;
}
function vSettings() {
  const pt = A.dash?.game?.playtest;
  return `<div class="stack"><h2>Settings</h2></div>
  <div class="grid">
    <div class="panel"><h3>Announcement</h3><p class="small muted">Appears at the top of everyone's news ticker with 📢.</p>
      <label class="f">Message<textarea id="bc" maxlength="240"></textarea></label><div><button class="btn primary" data-act="broadcast">Publish announcement</button></div></div>
    <div class="panel"><h3>Playtest mode</h3><p class="small muted">While on, new players count as phone-verified. Turn it off once SMS verification is connected.</p>
      <p><span class="chip ${pt ? 'pill-warn' : 'pill-good'}">${pt ? 'On' : 'Off'}</span></p><div><button class="btn" data-act="playtest">${pt ? 'Turn off' : 'Turn on'}</button></div></div>
  </div>`;
}

function vGate() {
  if (!gate.has_password) return `<div class="setup"><span class="stamp">Owner only</span><h1>Control room</h1>
    <p class="lede">Create an owner password. You will need it, on top of your normal login, every time you open the control room.</p>
    <form class="panel hero" onsubmit="event.preventDefault();ACT.setpw()">
      <label class="f">New owner password<input id="pw-new" type="password" autocomplete="new-password" minlength="10" required></label>
      <label class="f">Type it again<input id="pw-again" type="password" autocomplete="new-password" minlength="10" required></label>
      <p class="small muted">At least 10 characters, with letters and numbers. Don't reuse your email password. It is stored scrambled and cannot be recovered, so keep it somewhere safe.</p>
      <div><button class="btn primary" type="submit">Create password</button></div></form></div>`;
  return `<div class="setup"><span class="stamp">Owner only</span><h1>Control room</h1>
    <p class="lede">Enter your owner password to unlock the control room on this device for 2 hours.</p>
    <form class="panel hero" onsubmit="event.preventDefault();ACT.unlock()">
      <label class="f">Owner password<input id="pw" type="password" autocomplete="current-password" required></label>
      ${gate.locked_until ? `<p class="small" style="color:var(--bad)">Locked after too many wrong attempts until ${watTime(gate.locked_until)} WAT.</p>` : ''}
      <div class="row"><button class="btn primary" type="submit">Unlock</button><button class="btn" type="button" data-act="signout">Sign out</button></div>
      <p class="small muted">5 wrong attempts lock owner access for 15 minutes. Every attempt is recorded with its IP address.</p></form></div>`;
}
function vSecurity() {
  return `<div class="stack"><h2>Security</h2><p class="lede">Unlocked until ${gate?.expires_at ? watTime(gate.expires_at) + ' WAT' : '—'}. The control room also locks itself after 15 minutes without activity.</p></div>
  <div class="grid">
    <form class="panel" onsubmit="event.preventDefault();ACT.changepw()"><h3>Change owner password</h3>
      <label class="f">Current password<input id="pw-old" type="password" autocomplete="current-password" required></label>
      <label class="f">New password<input id="pw-new" type="password" autocomplete="new-password" minlength="10" required></label>
      <label class="f">Type it again<input id="pw-again" type="password" autocomplete="new-password" minlength="10" required></label>
      <p class="small muted">Changing it signs out every other unlocked device.</p><div><button class="btn primary" type="submit">Change password</button></div></form>
    <div class="panel"><h3>Recent owner sign-ins</h3><div>${(A.logins || []).map(l => `<div class="li small"><div class="grow">${l.ok ? '✅' : '❌'} ${esc(l.what)} <span class="muted num">${esc(l.ip || 'unknown IP')}</span></div><span class="tiny muted">${watTime(l.at)}</span></div>`).join('') || '<div class="empty">No sign-ins yet.</div>'}</div>
      <p class="small muted">If you see an attempt you don't recognise, change this password and your email password.</p></div>
  </div>`;
}
function render() {
  const app = document.getElementById('app');
  if (recovering) { app.innerHTML = vRecovery(); return; }
  if (!user) { app.innerHTML = `<div class="setup"><span class="stamp">Owner only</span><h1>Control room</h1>
      <p class="lede">The Niger Area backend. Sign in with your owner account.</p>
      <form class="panel hero" onsubmit="event.preventDefault();ACT.signin()">
        <label class="f">Email<input id="si-email" type="email" autocomplete="username" required></label>
        <label class="f">Account password<input id="si-pass" type="password" autocomplete="current-password" required></label>
        <div class="row"><button class="btn primary" type="submit">Sign in</button><button class="linkish small" type="button" data-act="forgot">Forgot password?</button></div>
        <p class="small muted">After this you'll also need your owner password.</p></form></div>`; return; }
  if (!ok) { app.innerHTML = `<div class="setup"><span class="stamp">Owner only</span><h1>Control room</h1><p class="lede">You are signed in as <b>${esc(user.email)}</b>, which is not an owner account. Sign out and sign in with your owner email.</p><div><button class="btn" data-act="signout">Sign out</button></div></div>`; return; }
  if (!gate || !gate.unlocked) { app.innerHTML = gate ? vGate() : '<div class="setup"><span class="stamp">Loading</span></div>'; return; }
  const v = { overview: vOverview, players: vPlayers, reports: vReports, gist: vGist, network: vNetwork, redemptions: vRedemptions, log: vLog, settings: vSettings, security: vSecurity }[tab]();
  app.innerHTML = `<div class="shell"><header class="topbar"><div class="topbar-in"><div class="brand"><span class="flag"><i></i><i></i><i></i></span><div>Control room<small>Niger Area owner dashboard</small></div></div>
      <div class="meters"><button class="btn sm" data-act="lock" style="background:var(--on-danfo);color:var(--danfo);border-color:var(--on-danfo)">🔒 Lock</button><button class="btn sm" data-act="signout" style="background:var(--on-danfo);color:var(--danfo);border-color:var(--on-danfo)">Sign out</button></div></div></header>
    <nav class="side" aria-label="Dashboard">${TABS.map(([k, l]) => `<button data-act="tab" data-a="${k}" ${tab === k ? 'aria-current="page"' : ''}>${l}</button>`).join('')}</nav>
    <main class="view" style="padding-bottom:40px"><div class="tabs" style="${matchMedia('(min-width:900px)').matches ? 'display:none' : ''}">${TABS.map(([k, l]) => `<button data-act="tab" data-a="${k}" aria-pressed="${tab === k}">${l}</button>`).join('')}</div>${v}</main></div>${vDetail()}`;
}

const ACT = {
  tab(k) { tab = k; render(); load().then(render); },
  forgot() { sendReset(val('si-email').trim()); },
  async signin() {
    const { error } = await sb.auth.signInWithPassword({ email: val('si-email').trim(), password: val('si-pass') });
    if (error) toast(error.message, true);
  },
  async signout() { try { await sb.rpc('admin_lock'); } catch (_) {} await sb.auth.signOut(); A = {}; gate = null; render(); },
  async setpw() {
    const a = val('pw-new'), b = val('pw-again');
    if (a !== b) return toast('The two passwords do not match.', true);
    try { const r = await call('admin_set_password', { p_new: a }); if (!r.ok) return toast(r.message, true); }
    catch (e) { return toast(e.message, true); }
    await checkGate(); toast('Owner password created. Control room unlocked.'); await load(); render();
  },
  async unlock() {
    try { const r = await call('admin_unlock', { p_password: val('pw') }); if (!r.ok) { toast(r.message, true); await checkGate(); return render(); } }
    catch (e) { return toast(e.message, true); }
    idle = Date.now(); await checkGate(); await load(); render();
  },
  async lock() { await sb.rpc('admin_lock'); A = {}; detail = null; await checkGate(); render(); toast('Control room locked.'); },
  async changepw() {
    const a = val('pw-new'), b = val('pw-again');
    if (a !== b) return toast('The two new passwords do not match.', true);
    try { const r = await call('admin_set_password', { p_new: a, p_old: val('pw-old') }); if (!r.ok) return toast(r.message, true); }
    catch (e) { return toast(e.message, true); }
    await checkGate(); toast('Password changed. Other devices are signed out.'); await load(); render();
  },
  refresh() { load().then(render); },
  search() { search = val('s').trim(); load().then(render); },
  async open(id) { detail = { id, data: null }; render(); try { detail.data = await call('admin_player', { p_id: id }); } catch (e) { toast(e.message, true); detail = null; } render(); },
  close() { detail = null; render(); },
  sanction(id) {
    const kind = val('sx-kind'), n = +val('sx-n') || null, reason = val('sx-reason').trim();
    const money = kind === 'fine' || kind === 'grant';
    act('admin_sanction', { p_target: id, p_kind: kind, p_reason: reason, p_days: money ? null : n, p_amount: money ? n : null }, 'Done. The player has been notified.');
  },
  release(id) { act('admin_release', { p_target: id }, 'Released.'); },
  async convo(id) { try { A.convo = { id: +id, msgs: await call('admin_report_messages', { p_report: +id }) }; render(); } catch (e) { toast(e.message, true); } },
  closereport(id) { act('admin_close_report', { p_id: +id }, 'Report closed.'); },
  delpost(id) { act('admin_delete_post', { p_id: +id }, 'Post deleted.'); },
  allow(ip) { if (!ip || !ip.trim()) return; act('admin_allow_ip', { p_ip: ip.trim(), p_note: 'Allowed from dashboard' }, 'IP allowed.'); },
  paid(id) { act('admin_resolve_redemption', { p_id: +id, p_approve: true }, 'Marked as paid.'); },
  reject(id) { act('admin_resolve_redemption', { p_id: +id, p_approve: false }, 'Rejected and refunded.'); },
  broadcast() { act('admin_broadcast', { p_body: val('bc') }, 'Announcement published.'); },
  playtest() { act('admin_set_playtest', { p_on: !A.dash?.game?.playtest }, 'Playtest mode updated.').then(async () => { A.dash = await call('admin_dashboard'); render(); }); }
};
document.addEventListener('click', e => {
  if (e.target.matches('[data-scrim]')) return ACT.close();
  const b = e.target.closest('[data-act]'); if (!b || b.disabled) return;
  const f = ACT[b.dataset.act]; if (f) { e.preventDefault(); f(b.dataset.a); }
});
document.addEventListener('keydown', e => { if (e.key === 'Escape' && detail) ACT.close(); });

sb.auth.onAuthStateChange((_e, session) => {
  if (_e === 'PASSWORD_RECOVERY') recovering = true;
  user = session?.user || null;
  setTimeout(async () => { ok = user ? !!(await sb.rpc('is_admin')).data : false; if (ok) { await checkGate(); if (gate?.unlocked) await load(); } render(); }, 0);
});
setInterval(() => { if (ok && gate?.unlocked && tab === 'overview' && !detail && document.visibilityState === 'visible') load().then(render); }, 60000);
// Lock after 15 minutes without activity, and re-check the server-side unlock every minute.
['click', 'keydown', 'pointermove', 'touchstart'].forEach(ev => document.addEventListener(ev, () => { idle = Date.now(); }, { passive: true }));
setInterval(async () => {
  if (!ok || !gate?.unlocked) return;
  if (Date.now() - idle > 15 * 60000) { await ACT.lock(); return; }
  await checkGate(); if (!gate?.unlocked) render();
}, 60000);
render();
