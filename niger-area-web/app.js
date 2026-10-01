// Niger Area: the player app. Every action goes through a server function (supabase.rpc);
// this file only reads data and renders it.

const STATS = [['roads', 'Roads'], ['power', 'Power'], ['health', 'Health'], ['edu', 'Education'], ['security', 'Security'], ['economy', 'Economy']];
const PROJECT = { roads: 'Fix the roads', power: 'Install transformers', health: 'Equip health centres', edu: 'Renovate schools', security: 'Fund community security', economy: 'Grants for traders' };
const CHARGES = ['Inciting violence', 'Vote buying', 'Fraud', 'Cybercrime', 'Thuggery', 'Defamation', 'Breach of public peace'];
const BLURB = { rally: 'Canopies, DJ, wide stage.', posters: 'Your face on every electric pole.', influencers: 'Trending by evening. Can backfire.', debate: 'Free. 2 energy. +1 reputation.', ruler: 'Needs reputation 10 for an audience.', rice: '"Stomach infrastructure". Raises scandal.', buy: 'Works. EFCC is watching.' };
const NEWS_KINDS = [['all', 'All'], ['election', 'Elections'], ['party', 'Parties'], ['law', 'Law & order'], ['government', 'Government'], ['announcement', 'Announcements'], ['general', 'Citizens']];
const MAIN = [['today', 'Today'], ['elections', 'Elections'], ['gist', 'Gist'], ['chats', 'Chats'], ['me', 'Me']];
const MORE = [['wallet', 'Wallet'], ['home', 'Household'], ['party', 'Party'], ['office', 'Office'], ['nation', 'Nation'], ['leaders', 'Leaderboard'], ['news', 'News']];
const ICON_FOR = { today: 'today', elections: 'vote', gist: 'gist', chats: 'chat', me: 'me', wallet: 'wallet', home: 'home', party: 'party', office: 'office', nation: 'nation', leaders: 'board', news: 'news' };

let user = null, R = null, D = null, V = {}, page = 'today', busy = false, authMode = 'signup', sheet = null;
let names = {}, newsKind = 'all', gistRoom = 'national', chatWith = null, rt = null;
let dataSaver = false; try { dataSaver = localStorage.getItem('na.datasaver') === '1'; } catch (_) {}
try { const p = localStorage.getItem('na.page'); if (p) page = p; } catch (_) {}

/* ================= data ================= */
async function loadRefs() {
  const r = await Promise.all([
    q(sb.from('states').select('*').order('name')), q(sb.from('lgas').select('*').order('name')),
    q(sb.from('office_rules').select('*')), q(sb.from('shop_items').select('*').order('cost')),
    q(sb.from('hustles').select('*').order('min_pay')), q(sb.from('campaign_actions').select('*').order('base_cost')),
    q(sb.from('decrees').select('*')), q(sb.from('achievements').select('*').order('sort')), q(sb.from('coin_packs').select('*').order('kobo'))
  ]);
  R = { states: r[0], lgas: r[1], rules: Object.fromEntries(r[2].map(x => [x.type, x])), items: r[3], hustles: r[4], actions: r[5], decrees: r[6], ach: r[7], packs: r[8] };
}
async function loadCore() {
  const uid = user.id;
  const [clock, me] = await Promise.all([q(sb.from('game_clock').select('*').single()), q(sb.from('citizens').select('*').eq('id', uid).maybeSingle())]);
  D = { clock, me };
  if (!me) { D.isAdmin = !!(await sb.rpc('is_admin')).data; return; }
  const r = await Promise.all([
    q(sb.from('wallets').select('*').eq('citizen_id', uid).single()),
    q(sb.from('daily_limits').select('*').eq('citizen_id', uid).eq('day', clock.day).maybeSingle()),
    q(sb.from('parties').select('*').order('created_at')),
    q(sb.from('party_members').select('citizen_id,party_id,role')),
    q(sb.from('offices').select('*')),
    q(sb.from('citizen_items').select('*').eq('citizen_id', uid)),
    q(sb.from('election_registrations').select('election_id').eq('citizen_id', uid)),
    q(sb.from('votes').select('election_id,candidate_id').eq('voter_id', uid)),
    q(sb.from('connections').select('*')),
    q(sb.from('proposals').select('*')),
    q(sb.from('marriages').select('*').is('ended_at', null)),
    q(sb.from('citizen_achievements').select('achievement_id').eq('citizen_id', uid)),
    q(sb.from('sanctions').select('*').eq('citizen_id', uid).order('id', { ascending: false }).limit(1)),
    sb.rpc('my_conversations').then(x => x.data || []),
    q(sb.from('news').select('body').order('id', { ascending: false }).limit(1)),
    sb.rpc('is_admin').then(x => !!x.data),
    q(sb.from('policies').select('*')),
    q(sb.from('office_rules').select('*'))
  ]);
  Object.assign(D, {
    wallet: r[0], limits: r[1] || { claimed: false, ads: 0, hustles: 0, trivia_done: false, civic: false, posted: false, tasks_claimed: false, gifted: 0 },
    parties: r[2], members: r[3], offices: r[4], myItems: Object.fromEntries(r[5].map(i => [i.item_id, i.qty])),
    regs: new Set(r[6].map(x => x.election_id)), myVotes: Object.fromEntries(r[7].map(v => [v.election_id, v.candidate_id])),
    conns: r[8], proposals: r[9], marriage: r[10][0] || null, myAch: new Set(r[11].map(a => a.achievement_id)),
    lastSanction: r[12][0] || null, convs: r[13], headline: r[14][0]?.body || '', isAdmin: r[15],
    policies: Object.fromEntries(r[16].map(p => [p.id, p]))
  });
  R.rules = Object.fromEntries(r[17].map(x => [x.type, x]));
}
async function ensureNames(ids) {
  const need = [...new Set(ids.filter(id => id && !names[id]))];
  for (let i = 0; i < need.length; i += 100) {
    const rows = await q(sb.from('citizens').select('id,display_name,avatar_url,state_id,lga_id').in('id', need.slice(i, i + 100)));
    rows.forEach(c => { names[c.id] = c; });
  }
}
const nm = id => names[id]?.display_name || 'Citizen';
const SHORT = { LG: 'Chairman', SEN: 'Senator', GOV: 'Governor', PRES: 'President' };
const tick = id => { const o = D?.offices?.find(x => x.holder_id === id); return o ? `<span class="verified" title="${esc(officeName(o.key))}">✔ ${SHORT[typeOf(o.key)]}</span>` : ''; };
const years = d => `${Math.round(d / 30)}-year`;
const taxes = () => ({ vat: Number(D.policies?.nation?.vat || 0), stax: Number(D.policies?.[D.me.state_id]?.state_tax || 0) });
const priceOf = cost => { const t = taxes(); return cost + Math.round(cost * t.vat) + Math.round(cost * t.stax); };
const feeFor = k => { const t = typeOf(k), r = R.rules[t]; const m = Number(D.policies?.[t === 'LG' ? k.split(':')[1] : 'nation']?.fee_mult ?? 1); return Math.round(r.fee * m); };
const pct = v => `${Math.round(Number(v) * 1000) / 10}%`;
const pic = (id, size) => avatar(dataSaver ? null : names[id]?.avatar_url, nm(id), size);
const personBtn = (id, size = 'sm') => `<button class="linkish who" data-act="profile" data-a="${id}">${pic(id, size)}<span class="n">${esc(nm(id))}</span>${tick(id)}</button>`;

/* ================= derived ================= */
const typeOf = k => k.split(':')[0];
const stateName = id => R.states.find(s => s.id === id)?.name || id;
const lgaName = id => R.lgas.find(l => l.id === id)?.name || id;
function place(k, j) {
  const [t, s, l] = k.split(':');
  if (t === 'PRES') return 'Niger Area';
  if (t === 'LG') return lgaName(l) + ' LGA';
  return stateName(s) + (t === 'SEN' ? ' District' : ' State');
}
const officeName = k => R.rules[typeOf(k)].title + (typeOf(k) === 'PRES' ? ' of Niger Area' : ', ' + place(k));
const party = id => D.parties.find(p => p.id === id);
const membership = cid => D.members.find(m => m.citizen_id === cid);
const memberCount = id => D.members.filter(m => m.party_id === id).length;
const strength = id => memberCount(id) / (D.members.length || 1) * 100;
const chip = id => { const p = party(id); return p ? `<span class="chip"><span class="dot" style="background:${esc(p.color)}"></span>${esc(p.abbr)}</span>` : '<span class="chip">No party</span>'; };
const myOffice = () => D.offices.find(o => o.holder_id === D.me.id);
const officeOf = cid => D.offices.find(o => o.holder_id === cid);
const energy = () => D.me.energy_day < D.clock.day ? 8 : D.me.energy;
const rep = c => Math.floor(Number(c.rep));
function myKeys() {
  const m = D.me, ks = ['LG:' + m.state_id + ':' + m.lga_id, 'SEN:' + m.state_id];
  if (R.states.find(s => s.id === m.state_id)?.has_governor) ks.push('GOV:' + m.state_id);
  ks.push('PRES'); return ks;
}
function statusOf(items, giftStatus, isChair) {
  const pts = R.items.reduce((a, it) => a + (items[it.id] || 0) * it.status_points, 0);
  return Math.min(20, Math.floor(pts + Number(giftStatus || 0) + (isChair ? 5 : 0)));
}
const myStatus = () => statusOf(D.myItems, D.me.gift_status, membership(D.me.id)?.role === 'chair');
const influenceOf = (c, status) => status + rep(c) + c.offices_held * 6;
function approval(j) { const b = STATS.reduce((a, [s]) => a + Number(j[s]), 0) / 6; return clamp(Math.round(b + Number(j.mood)), 0, 100); }
const unread = () => D.convs.reduce((a, c) => a + Number(c.unread), 0);
const pendingIn = () => D.conns.filter(c => c.addressee_id === D.me.id && c.status === 'pending');
const proposalsIn = () => D.proposals.filter(p => p.target_id === D.me.id);
const spouseId = () => D.marriage ? (D.marriage.a_id === D.me.id ? D.marriage.b_id : D.marriage.a_id) : null;
const connWith = id => D.conns.find(c => (c.requester_id === id && c.addressee_id === D.me.id) || (c.addressee_id === id && c.requester_id === D.me.id));
const tasksDone = l => [l.claimed, l.hustles > 0, l.trivia_done, l.civic, l.posted];

/* ================= actions ================= */
async function rpc(fn, args, okMsg, after) {
  if (busy) return; busy = true;
  try {
    const { data, error } = await sb.rpc(fn, args || {});
    if (error) throw error;
    if (okMsg) toast(typeof okMsg === 'function' ? okMsg(data) : okMsg);
    await loadCore(); if (after) await after(data); await loadPage(); render();
  } catch (e) { toast(e.message || String(e), true); }
  finally { busy = false; }
}
function go(p) { page = p; sheet = null; try { localStorage.setItem('na.page', p); } catch (_) {} loadPage().then(render); window.scrollTo(0, 0); }

const ACT = {
  go, more() { sheet = { type: 'more' }; render(); }, close() { sheet = null; if (adTimer) clearInterval(adTimer); render(); },
  authmode(a) { authMode = a; render(); },
  forgot() { sendReset(val('au-email').trim()); },
  async auth() {
    const email = val('au-email').trim(), password = val('au-pass');
    if (!email || password.length < 6) return toast('Enter your email and a password of at least 6 characters.', true);
    const { data, error } = authMode === 'signup' ? await sb.auth.signUp({ email, password }) : await sb.auth.signInWithPassword({ email, password });
    if (error) return toast(error.message, true);
    if (authMode === 'signup' && !data.session) { authMode = 'signin'; render(); toast('Check your email to confirm your account, then sign in.'); }
  },
  async signout() { sheet = null; await sb.auth.signOut(); toast('Signed out.'); },
  register() {
    const n = val('su-name').trim();
    if (n.length < 2) return toast('Enter your name, at least 2 letters.', true);
    rpc('register_citizen', { p_name: n, p_lga: val('su-lga') }, 'Welcome to Niger Area! 10,000 coins added to your wallet.');
  },
  datasaver() { dataSaver = !dataSaver; try { localStorage.setItem('na.datasaver', dataSaver ? '1' : '0'); } catch (_) {} setupRealtime(); render(); toast(dataSaver ? 'Data saver on: pictures hidden, fewer updates.' : 'Data saver off.'); },
  // Today
  claim() { rpc('claim_daily', {}, d => `+2,000 coins. Day ${d.streak} streak${d.bonus ? ` · +${fmt(d.bonus)} streak bonus!` : ''}`); },
  async ad() {
    try { const { error } = await sb.rpc('start_ad'); if (error) throw error; } catch (e) { return toast(e.message, true); }
    sheet = { type: 'ad', left: 15 }; render();
    adTimer = setInterval(async () => {
      if (!sheet || sheet.type !== 'ad') return clearInterval(adTimer);
      sheet.left--; if (sheet.left > 0) return render();
      clearInterval(adTimer); sheet = null; rpc('finish_ad', {}, '+400 coins. Thanks for watching.');
    }, 1000);
  },
  hustle(id) { rpc('do_hustle', { p_hustle: id }, n => `You earned ${fmt(n)} coins. Hard work pays!`); },
  trivia(i) { rpc('answer_trivia', { p_choice: +i }, r => r.correct ? 'Correct! +500 coins and +0.5 reputation.' : `Not quite. The answer was "${V.trivia.options[r.answer]}".`, r => { V.triviaResult = r; }); },
  tasks() { rpc('claim_tasks', {}, 'Perfect day! +1,500 coins.'); },
  // Wallet
  stash() { rpc('stash_coins', { p_amount: Math.floor(+val('amt-stash')) }, 'Moved to your campaign stash.'); },
  unstash() { rpc('unstash_coins', { p_amount: Math.floor(+val('amt-stash')) }, 'Withdrawn, minus the 10% party levy.'); },
  gift() { rpc('gift_coins', { p_to: sheet?.id, p_amount: Math.floor(+val('amt-gift')) }, 'Coins sent.', () => { sheet = null; }); },
  redeem(cp) { rpc('redeem_cp', { p_cp: +cp, p_phone: val('rd-phone').trim() }, 'Request sent. It is reviewed before airtime is sent.'); },
  async buycoins(pack) {
    const { data, error } = await sb.functions.invoke('create-checkout', { body: { pack_id: pack } });
    if (error) { let m = error.message; try { m = (await error.context.json()).error || m; } catch (_) {} return toast(m, true); }
    location.href = data.authorization_url;
  },
  buy(id) { rpc('buy_item', { p_item: id }, 'Bought!'); },
  // Party
  join(id) { rpc('join_party', { p_party: id }, 'Welcome to the party! +500 coins for your first membership.'); },
  leave() { rpc('leave_party', {}, 'You decamped.'); },
  create() { rpc('create_party', { p_name: val('np-name').trim(), p_abbr: val('np-abbr').trim().toUpperCase(), p_color: val('np-color') }, 'Party registered with INEC.'); },
  partyview(id) { V.partyView = id; loadPage().then(render); },
  // Elections
  reval(id) { rpc('revalidate_card', { p_election: id }, 'PVC revalidated for this election.'); },
  declare(k) { rpc('declare_candidacy', { p_key: k }, 'You are on the ballot!'); },
  vote(a) { const [e, c] = a.split('|'); rpc('cast_vote', { p_election: e, p_candidate: c }, 'Vote cast. +200 coins. Your finger is inked!'); },
  camp(id) { rpc('campaign', { p_action: id }, d => `${d >= 0 ? '+' : ''}${Number(d).toFixed(1)} popularity.`); },
  withdraw() { rpc('withdraw_candidacy', {}, 'You withdrew from the race.'); },
  campost() { rpc('post_campaign', { p_body: val('cp-body') }, 'Campaign message posted on Gist.'); },
  // Office
  project(s) { rpc('start_project', { p_stat: s }, 'Contract awarded. Ready in 3 days.'); },
  townhall() { rpc('town_hall', {}, d => `Town hall went well. Rapport +${d}.`); },
  salaries() { rpc('pay_salaries', {}, 'Salaries paid. Workers dey happy.'); },
  decree(id) { rpc('make_decree', { p_decree: id }, 'Your order has been announced.'); },
  async arrestsearch() {
    const term = val('ar-q').trim(), off = myOffice(); if (!off || term.length < 2) return;
    const j = V.jur; let qq = sb.from('citizens').select('id,display_name,avatar_url,state_id,lga_id,scandal').ilike('display_name', `%${term}%`).neq('id', D.me.id).limit(10);
    if (j.type === 'LG') qq = qq.eq('lga_id', j.lga_id); else if (j.type === 'GOV') qq = qq.eq('state_id', j.state_id);
    V.arrestHits = await q(qq); V.arrestHits.forEach(c => names[c.id] = c); render();
  },
  arrest(id) { sheet = { type: 'arrest', id }; render(); },
  doarrest() { rpc('order_arrest', { p_target: sheet.id, p_charge: val('ar-charge') }, 'The police have been dispatched.', () => { sheet = null; }); },
  bail() { rpc('post_bail', {}, 'You are free. Walk with your chest out.'); },
  // Gist
  room(r) { gistRoom = r; loadPage().then(render); },
  post() { rpc('post_gist', { p_channel: gistRoom, p_body: val('gist-body') }, 'Posted.'); },
  like(id) { rpc('toggle_like', { p_post: +id }); },
  // Social
  async profile(id) { sheet = { type: 'profile', id, loading: true }; render(); await loadProfile(id); render(); },
  connect(id) { rpc('request_connection', { p_target: id }, r => r === 'accepted' ? 'You are now connected.' : 'Connection request sent.', () => loadProfile(id)); },
  accept(id) { rpc('respond_connection', { p_requester: id, p_accept: true }, 'Connected!'); },
  decline(id) { rpc('respond_connection', { p_requester: id, p_accept: false }, 'Request declined.'); },
  unconnect(id) { rpc('remove_connection', { p_other: id }, 'Connection removed.', () => loadProfile(id)); },
  message(id) { sheet = null; chatWith = id; go('chats'); },
  async send() {
    const body = val('msg-body').trim(); if (!body || !chatWith) return;
    const { error } = await sb.rpc('send_message', { p_to: chatWith, p_body: body });
    if (error) return toast(error.message, true);
    document.getElementById('msg-body').value = ''; await loadThread(); render(); scrollThread();
  },
  openchat(id) { chatWith = id; loadPage().then(() => { render(); scrollThread(); }); },
  backchats() { chatWith = null; render(); },
  propose(id) { sheet = { type: 'propose', id }; render(); },
  dopropose() { rpc('propose', { p_target: sheet.id, p_note: val('pr-note') }, 'Proposal sent! 6,000 coins held for the wedding. Refunded if they say no.', () => { sheet = null; }); },
  answerprop(a) { const [id, yes] = a.split('|'); rpc('answer_proposal', { p_proposer: id, p_accept: yes === '1' }, yes === '1' ? 'Congratulations! You are married.' : 'Proposal declined.'); },
  withdrawprop() { rpc('withdraw_proposal', {}, 'Proposal withdrawn and refunded.'); },
  divorce() { sheet = { type: 'confirm', text: 'End your marriage? Your spouse will be notified in the news if you both show your spouse.', act: 'dodivorce' }; render(); },
  dodivorce() { sheet = null; rpc('divorce', {}, 'You are now single.'); },
  showspouse() { rpc('set_show_spouse', { p_show: !D.me.show_spouse }, D.me.show_spouse ? 'Spouse hidden from your profile.' : 'Spouse shown on your profile.'); },
  report(id) { sheet = { type: 'report', id }; render(); },
  doreport() { rpc('report_citizen', { p_target: sheet.id, p_reason: val('rp-reason') }, 'Report sent to the Niger Area team.', () => { sheet = null; }); },
  giftto(id) { sheet = { type: 'gift', id }; render(); },
  saveprofile() { rpc('update_profile', { p_bio: val('pf-bio'), p_dm_policy: val('pf-dm') }, 'Profile saved.'); },
  pickphoto() { document.getElementById('pf-photo')?.click(); },
  newskind(k) { newsKind = k; loadPage().then(render); },
  setnational() { rpc('set_national_policy', { p_vat: (+val('pol-vat')) / 100, p_fee_mult: (+val('pol-fee')) / 100 }, 'National policy announced.'); },
  setstate() { rpc('set_state_policy', { p_tax: (+val('pol-stax')) / 100, p_fee_mult: (+val('pol-sfee')) / 100 }, 'State policy announced.'); },
  setsalary(t) { rpc('set_salary', { p_type: t, p_amount: Math.floor(+val('sal-' + t)) }, 'Salary set.'); },
  settenure() { rpc('set_presidential_tenure', { p_days: Math.round(+val('pol-tenure') * 30) }, 'Tenure changed.'); }
};
let adTimer = null;

async function uploadPhoto(file) {
  if (!file) return;
  if (!/^image\//.test(file.type)) return toast('Choose a picture.', true);
  try {
    const img = await createImageBitmap(file);
    const s = Math.min(img.width, img.height), c = document.createElement('canvas'); c.width = c.height = 256;
    c.getContext('2d').drawImage(img, (img.width - s) / 2, (img.height - s) / 2, s, s, 0, 0, 256, 256);
    const blob = await new Promise(r => c.toBlob(r, 'image/webp', 0.82)) || await new Promise(r => c.toBlob(r, 'image/jpeg', 0.85));
    const ext = blob.type === 'image/webp' ? 'webp' : 'jpg', path = `${user.id}/${Date.now()}.${ext}`;
    const { error } = await sb.storage.from('avatars').upload(path, blob, { contentType: blob.type });
    if (error) throw error;
    const url = sb.storage.from('avatars').getPublicUrl(path).data.publicUrl;
    delete names[user.id];
    await rpc('set_avatar', { p_url: url }, 'Profile picture updated.');
  } catch (e) { toast(e.message || 'Upload failed.', true); }
}

/* ================= page loaders ================= */
async function loadPage() {
  if (!D?.me) return;
  try {
    if (page === 'today') {
      if (!V.trivia || V.triviaDay !== D.clock.day) { V.trivia = (await sb.rpc('get_trivia')).data; V.triviaDay = D.clock.day; V.triviaResult = null; }
    }
    if (page === 'elections') {
      const keys = myKeys();
      const els = await q(sb.from('elections').select('*').in('key', keys).eq('status', 'open'));
      const recent = await q(sb.from('elections').select('*').eq('status', 'closed').gt('turnout', 0).order('poll_day', { ascending: false }).limit(10));
      const ids = [...els, ...recent].map(e => e.id);
      const cands = ids.length ? await q(sb.from('candidates').select('*').in('election_id', ids)) : [];
      const jur = await q(sb.from('jurisdictions').select('key,lga_id,state_id').in('key', keys));
      await ensureNames([...cands.map(c => c.citizen_id), ...D.offices.filter(o => keys.includes(o.key)).map(o => o.holder_id)]);
      V.els = els; V.recent = recent; V.cands = cands; V.jurs = jur;
    }
    if (page === 'gist') {
      const posts = await q(sb.from('posts').select('*').eq('channel', gistRoom).order('id', { ascending: false }).limit(60));
      const liked = posts.length ? await q(sb.from('post_likes').select('post_id').in('post_id', posts.map(p => p.id))) : [];
      const elIds = [...new Set(posts.map(p => p.election_id).filter(Boolean))];
      V.postEls = elIds.length ? Object.fromEntries((await q(sb.from('elections').select('*').in('id', elIds))).map(e => [e.id, e])) : {};
      await ensureNames(posts.map(p => p.author_id));
      V.posts = posts; V.liked = new Set(liked.map(l => l.post_id));
    }
    if (page === 'chats') {
      D.convs = (await sb.rpc('my_conversations')).data || [];
      D.convs.forEach(c => { names[c.id] = names[c.id] || { id: c.id, display_name: c.name, avatar_url: c.avatar_url }; });
      if (chatWith) { await ensureNames([chatWith]); await loadThread(); }
    }
    if (page === 'me') {
      const ids = [...D.conns.flatMap(c => [c.requester_id, c.addressee_id]), ...D.proposals.flatMap(p => [p.proposer_id, p.target_id]), spouseId(), D.me.id];
      await ensureNames(ids);
      V.myEls = await q(sb.from('elections').select('*').in('key', myKeys()).eq('status', 'open'));
    }
    if (page === 'wallet') V.ledger = await q(sb.from('ledger').select('*').eq('citizen_id', user.id).order('id', { ascending: false }).limit(30));
    if (page === 'party') {
      const pid = V.partyView || membership(D.me.id)?.party_id;
      V.partyMembers = pid ? D.members.filter(m => m.party_id === pid) : [];
      V.partyView = pid || null;
      await ensureNames(V.partyMembers.map(m => m.citizen_id).concat(D.parties.map(p => p.chair_id)));
    }
    if (page === 'office') {
      const off = myOffice();
      if (off) {
        V.jur = await q(sb.from('jurisdictions').select('*').eq('key', off.key).single());
        V.projects = await q(sb.from('projects').select('*').eq('key', off.key).eq('done', false));
        V.decreeLog = await q(sb.from('decree_log').select('*').eq('key', off.key).order('day', { ascending: false }).limit(30));
      }
    }
    if (page === 'nation') {
      V.jurAll = Object.fromEntries((await q(sb.from('jurisdictions').select('key,roads,power,health,edu,security,economy,mood').in('type', ['PRES', 'GOV', 'SEN']))).map(j => [j.key, j]));
      await ensureNames(D.offices.filter(o => !o.key.startsWith('LG')).map(o => o.holder_id));
      V.arrests = await q(sb.from('arrests').select('*').order('id', { ascending: false }).limit(10));
      await ensureNames(V.arrests.flatMap(a => [a.by_id, a.target_id]));
    }
    if (page === 'leaders') V.board = (await sb.rpc('leaderboard')).data;
    if (page === 'news') {
      let qq = sb.from('news').select('*').order('id', { ascending: false }).limit(100);
      if (newsKind !== 'all') qq = qq.eq('kind', newsKind);
      V.news = await q(qq);
    }
  } catch (e) { toast(e.message, true); }
}
async function loadThread() {
  const me = D.me.id, o = chatWith;
  V.thread = await q(sb.from('messages').select('*').or(`and(sender_id.eq.${me},recipient_id.eq.${o}),and(sender_id.eq.${o},recipient_id.eq.${me})`).order('id', { ascending: false }).limit(80));
  V.thread.reverse();
  if (V.thread.some(m => m.recipient_id === me && !m.read_at)) { await sb.rpc('mark_read', { p_other: o }); D.convs = (await sb.rpc('my_conversations')).data || []; }
}
function scrollThread() { const t = document.getElementById('thread'); if (t) t.scrollTop = t.scrollHeight; }
async function loadProfile(id) {
  const [c, items, ach, spouse, terms] = await Promise.all([
    q(sb.from('citizens').select('id,display_name,avatar_url,bio,state_id,lga_id,rep,streak,best_streak,offices_held,gift_status,votes_cast,trivia_correct,hustles_total,created_at,dm_policy,detained_until,detained_charge,banned').eq('id', id).single()),
    q(sb.from('citizen_items').select('*').eq('citizen_id', id)),
    q(sb.from('citizen_achievements').select('achievement_id,earned_at').eq('citizen_id', id)),
    sb.rpc('public_spouse', { p_citizen: id }).then(x => x.data),
    q(sb.from('office_terms').select('*').eq('citizen_id', id))
  ]);
  names[id] = c; if (spouse) names[spouse.id] = { id: spouse.id, display_name: spouse.name, avatar_url: spouse.avatar_url };
  if (sheet?.type === 'profile' && sheet.id === id) Object.assign(sheet, { loading: false, c, items: Object.fromEntries(items.map(i => [i.item_id, i.qty])), ach: new Set(ach.map(a => a.achievement_id)), spouse, terms });
}

/* ================= views ================= */
function vAuth() {
  const up = authMode === 'signup';
  return `<div class="setup">
    <div class="stack"><span class="stamp">Naija politics, your way</span><h1>Niger Area</h1>
      <p class="lede">One country, real players. Collect your PVC, hustle, join or found a party, and run for LG Chairman, Senator, Governor or President against other citizens.</p></div>
    <div class="features"><div>36 states and Abuja, real LGAs</div><div>10,000 coins to start, 2,000 every day</div><div>Vote, campaign, get elected, govern</div><div>Arrests, decrees, EFCC, tribunals of public opinion</div></div>
    <form class="panel hero" onsubmit="event.preventDefault();ACT.auth()">
      <h3>${up ? 'Create an account' : 'Sign in'}</h3>
      <label class="f">Email<input id="au-email" type="email" autocomplete="email" required></label>
      <label class="f">Password<input id="au-pass" type="password" autocomplete="${up ? 'new-password' : 'current-password'}" minlength="6" required></label>
      <div class="row"><button class="btn primary" type="submit">${up ? 'Create account' : 'Sign in'}</button>
      <button class="btn" type="button" data-act="authmode" data-a="${up ? 'signin' : 'signup'}">${up ? 'I already have an account' : 'Create a new account'}</button></div>
      ${up ? '' : '<button class="linkish small" type="button" data-act="forgot">Forgot password?</button>'}
      <p class="small muted">One person, one voter's card: only one citizen can register per network.</p>
    </form></div>`;
}
function vRegister() {
  const sid = vRegister.sid || 'lagos';
  return `<div class="setup">
    <div class="stack"><span class="stamp">PVC registration</span><h1>Niger Area</h1><p class="lede">Where do you live? You can only vote and run for local and state offices where you are registered.</p></div>
    <div class="panel hero">
      <label class="f">Your name, as other citizens will see it<input id="su-name" type="text" maxlength="40" autocomplete="name"></label>
      <label class="f">State<select id="su-state">${R.states.map(s => `<option value="${s.id}"${s.id === sid ? ' selected' : ''}>${esc(s.name)}</option>`).join('')}</select></label>
      <label class="f">Local government<select id="su-lga">${R.lgas.filter(l => l.state_id === sid).map(l => `<option value="${l.id}">${esc(l.name)}</option>`).join('')}</select></label>
      <div class="row"><button class="btn primary" data-act="register">Collect my PVC</button><button class="btn" data-act="signout">Sign out</button></div>
    </div></div>`;
}
function vBlocked() {
  const m = D.me, detained = m.detained_until && new Date(m.detained_until) > new Date();
  if (detained) {
    const by = officeOf(m.detained_by);
    return `<div class="custody"><div class="panel alert" style="max-width:480px">
      <span class="eyebrow">Niger Area Police Force</span><h2>You are in custody</h2>
      <p>Charge: <b>${esc(m.detained_charge)}</b>${by ? ` · on the orders of the ${esc(officeName(by.key))}` : ''}.</p>
      <p class="muted">Release: ${watTime(m.detained_until)} WAT. Until then you cannot claim, vote, campaign, chat or post.</p>
      <div class="row"><button class="btn primary" data-act="bail">Post bail</button><button class="btn" data-act="signout">Sign out</button></div>
      <p class="small muted">Bail is 3,000 coins plus 1,000 for each rank of the office that ordered the arrest.</p></div></div>`;
  }
  const banned = m.banned, until = m.suspended_until;
  return `<div class="custody"><div class="panel alert" style="max-width:480px">
    <span class="eyebrow">Niger Area authorities</span><h2>${banned ? 'Account banned' : 'Account suspended'}</h2>
    <p>${banned ? esc(m.ban_reason || 'You broke the rules.') : `You can play again from ${watTime(until)} WAT.`}</p>
    ${D.lastSanction ? `<p class="muted small">Reason: ${esc(D.lastSanction.reason)}</p>` : ''}
    <div><button class="btn" data-act="signout">Sign out</button></div></div></div>`;
}

function topbar() {
  const w = D.wallet;
  return `<header class="topbar"><div class="topbar-in">
    <div class="brand"><span class="flag"><i></i><i></i><i></i></span><div>Niger Area<small>Day ${D.clock.day} · ${esc(lgaName(D.me.lga_id))}, ${esc(stateName(D.me.state_id))}</small></div></div>
    <div class="meters">
      <div class="meter"><b>${fmt(w.coins)}</b><span>Coins</span></div>
      <div class="meter"><b>${fmt(w.stash)}</b><span>Stash</span></div>
      <div class="meter"><b>${energy()}/8</b><span>Energy</span></div>
      <div class="meter"><b>${rep(D.me)}</b><span>Rep</span></div>
    </div></div>
    <div class="ticker"><em>NEWS</em>${esc(D.headline)}</div></header>`;
}
function badgeFor(p) {
  if (p === 'chats') { const n = unread(); return n ? `<span class="dotbadge">${n}</span>` : ''; }
  if (p === 'me') { const n = pendingIn().length + proposalsIn().length; return n ? `<span class="dotbadge">${n}</span>` : ''; }
  if (p === 'today') { const n = 5 - tasksDone(D.limits).filter(Boolean).length; return n && !D.limits.claimed ? '<span class="dotbadge">!</span>' : ''; }
  return '';
}
function nav() {
  const side = `<nav class="side" aria-label="Sections">${MAIN.map(([p, l]) => `<button data-act="go" data-a="${p}" ${page === p ? 'aria-current="page"' : ''}>${icon(ICON_FOR[p])}${l}${badgeFor(p)}</button>`).join('')}<hr>
    ${MORE.map(([p, l]) => `<button data-act="go" data-a="${p}" ${page === p ? 'aria-current="page"' : ''}>${icon(ICON_FOR[p])}${l}</button>`).join('')}<hr>
    ${D.isAdmin ? `<button onclick="location.href='admin.html'">${icon('shield')}Owner dashboard</button>` : ''}
    <button data-act="signout">${icon('logout')}Sign out</button></nav>`;
  const inMore = MORE.some(([p]) => p === page);
  const bottom = `<nav class="bottomnav" aria-label="Sections">${MAIN.slice(0, 4).map(([p, l]) => `<button data-act="go" data-a="${p}" ${page === p ? 'aria-current="page"' : ''}>${icon(ICON_FOR[p])}${l}${badgeFor(p)}</button>`).join('')}
    <button data-act="more" ${inMore || page === 'me' ? 'aria-current="page"' : ''}>${icon('more')}More${badgeFor('me')}</button></nav>`;
  return side + bottom;
}

/* ----- Today ----- */
function vToday() {
  const l = D.limits, done = tasksDone(l), t = V.trivia, tr = V.triviaResult;
  const labels = ['Claim your daily bonus', 'Do a hustle', 'Answer the trivia', 'Vote or campaign', 'Post on Gist'];
  const notice = D.lastSanction && D.lastSanction.kind === 'warn' && Date.now() - new Date(D.lastSanction.created_at) < 3 * 86400000
    ? `<div class="banner"><b>Warning from the authorities:</b> ${esc(D.lastSanction.reason)}</div>` : '';
  return `<div class="stack"><span class="eyebrow">Day ${D.clock.day} · next day in ${untilMidnightWAT()}</span><h2>Good day, ${esc(D.me.display_name.split(' ')[0])}</h2></div>
  ${notice}${D.clock.playtest ? '<div class="banner"><b>Playtest.</b> Your phone counts as verified while we test. Days change at midnight WAT, like real life.</div>' : ''}
  <div class="grid">
    <div class="panel hero"><div class="row between"><span class="eyebrow">Daily bonus</span><span class="chip pill-good">🔥 ${D.me.streak}-day streak</span></div>
      <div class="big">+2,000</div>
      <button class="btn primary" data-act="claim" ${l.claimed ? 'disabled' : ''}>${l.claimed ? 'Claimed today. Come back tomorrow' : 'Claim 2,000 coins'}</button>
      <p class="small muted">Every 7th day in a row pays an extra 3,000. Best streak: ${D.me.best_streak} days.</p></div>
    <div class="panel"><span class="eyebrow">Watch &amp; earn</span><div class="big">${l.ads}/5</div>
      <button class="btn primary" data-act="ad" ${l.ads >= 5 ? 'disabled' : ''}>${l.ads >= 5 ? 'All ads watched today' : 'Watch an ad · +400'}</button>
      <p class="small muted">Up to 2,000 more coins a day. Each ad is 15 seconds.</p></div>
    <div class="panel"><div class="row between"><span class="eyebrow">Daily checklist</span><span class="num small">${done.filter(Boolean).length}/5</span></div>
      <div>${labels.map((x, i) => `<div class="li"><span>${done[i] ? '✅' : '⬜'} ${x}</span></div>`).join('')}</div>
      <button class="btn primary" data-act="tasks" ${l.tasks_claimed || !done.every(Boolean) ? 'disabled' : ''}>${l.tasks_claimed ? 'Bonus collected' : 'Collect 1,500 bonus'}</button></div>
  </div>
  <div class="panel"><div class="row between"><h3>Hustles</h3><span class="small muted">${l.hustles}/3 today · energy ${energy()}/8</span></div>
    <div class="grid3">${R.hustles.map(h => { const need = h.needs_item && !D.myItems[h.needs_item];
      return `<div class="action"><b>${esc(h.label)}</b><p>${esc(h.blurb)}</p><p class="num">${fmt(h.min_pay)}–${fmt(h.max_pay)} coins · ${h.energy} energy</p>
      <div><button class="btn primary sm" data-act="hustle" data-a="${h.id}" ${l.hustles >= 3 || energy() < h.energy || need ? 'disabled' : ''}>${need ? 'Needs ' + esc(R.items.find(i => i.id === h.needs_item)?.label || 'item') : 'Go'}</button></div></div>`; }).join('')}</div></div>
  ${t ? `<div class="panel"><div class="row between"><h3>Naija trivia</h3><span class="small muted">+500 coins if correct</span></div>
    <p><b>${esc(t.question)}</b></p>
    <div class="grid3">${t.options.map((o, i) => `<button class="btn ${tr ? (i === tr.answer ? 'primary' : '') : ''}" data-act="trivia" data-a="${i}" ${l.trivia_done ? 'disabled' : ''}>${esc(o)}</button>`).join('')}</div>
    ${l.trivia_done && !tr ? '<p class="small muted">You answered today. New question tomorrow.</p>' : ''}</div>` : ''}`;
}

/* ----- Elections ----- */
function vElections() {
  if (!V.els) return '<div class="empty">Loading elections…</div>';
  const mine = V.cands.find(c => c.citizen_id === D.me.id && c.votes === null), m = membership(D.me.id), r = rep(D.me);
  let camp = '';
  if (mine) {
    const e = V.els.find(x => x.id === mine.election_id), o = R.rules[typeOf(e.key)], spent = +mine.spent, cap = +o.spend_cap;
    camp = `<div class="panel hero"><div class="row between"><div><span class="eyebrow">Your campaign</span><h3>${esc(officeName(e.key))}</h3></div><span class="small num">Stash ${fmt(D.wallet.stash)} · Energy ${energy()}/8</span></div>
      <div class="stat" style="grid-template-columns:auto 1fr auto"><span class="small">Spent</span><div class="bar ${spent / cap > .85 ? 'b' : spent / cap > .6 ? 'w' : 'g'}"><i style="width:${Math.min(100, spent / cap * 100)}%"></i></div><span class="num small">${fmt(spent)} / ${fmt(cap)}</span></div>
      <div class="grid3">${R.actions.map(a => { const cost = a.base_cost * o.cost_mult; return `<div class="action"><b>${esc(a.label)}</b><p>${BLURB[a.id] || ''}</p><div><button class="btn sm ${a.scandal > 0 ? 'warn' : 'primary'}" data-act="camp" data-a="${a.id}" ${energy() < a.energy || spent + cost > cap ? 'disabled' : ''}>${cost ? fmt(cost) + ' coins' : 'Free'}</button></div></div>`; }).join('')}</div>
      <label class="f">Campaign post on Gist (with a Vote button)<textarea id="cp-body" maxlength="280" placeholder="Vote ${esc(D.me.display_name)} for ${esc(place(e.key))}! Light, roads and jobs."></textarea></label>
      <div class="row"><button class="btn primary" data-act="campost">Post campaign message</button><button class="btn warn" data-act="withdraw">Withdraw from race</button></div></div>`;
  }
  const races = myKeys().map(k => {
    const e = V.els.find(x => x.key === k); if (!e) return '';
    const o = R.rules[typeOf(k)], left = e.poll_day - D.clock.day, off = D.offices.find(x => x.key === k);
    const cs = V.cands.filter(c => c.election_id === e.id).sort((a, b) => b.real_votes - a.real_votes || b.popularity - a.popularity);
    const totalReal = cs.reduce((a, c) => a + c.real_votes, 0), max = Math.max(1, ...cs.map(c => c.real_votes));
    const valid = D.regs.has(e.id), canReval = D.clock.day <= e.poll_day - 2, voted = D.myVotes[e.id];
    const card = valid ? '<span class="chip pill-good">PVC valid ✓</span>' : canReval ? `<button class="btn sm primary" data-act="reval" data-a="${e.id}">Revalidate PVC</button>` : '<span class="chip pill-bad">Revalidation closed</span>';
    const why = !m ? 'Join a party first' : mine ? (mine.election_id === e.id ? '' : 'Already running elsewhere') : !valid ? 'Revalidate your PVC first' : r < o.min_rep ? `Needs reputation ${o.min_rep} (you have ${r})` : D.wallet.stash < feeFor(k) ? `Stash ${fmt(feeFor(k))} coins first` : '';
    return `<div class="panel${mine?.election_id === e.id ? ' hero' : ''}">
      <div class="row between"><div><span class="eyebrow">${o.title} · ${years(o.term_days)} term (${o.term_days} days)</span><h3>${esc(place(k))}</h3></div>
        <span class="chip ${left <= 2 ? 'pill-bad' : left <= 7 ? 'pill-warn' : ''}">Polls Day ${e.poll_day} · ${left === 1 ? 'tomorrow' : left + ' days'}</span></div>
      <div class="row small muted">Holder: ${off?.holder_id ? personBtn(off.holder_id) + chip(off.holder_party) : 'Caretaker committee'}</div>
      <div class="row">${card}${voted ? '<span class="chip pill-info">You voted</span>' : ''}</div>
      ${cs.length ? `<div class="row between"><span class="eyebrow">Live count · ${fmt(totalReal)} citizen vote${totalReal === 1 ? '' : 's'}</span></div>
        <div>${cs.map(c => `<div class="cand${c.citizen_id === D.me.id ? ' me' : ''}">${pic(c.citizen_id, 'sm')}
          <div class="row" style="gap:6px"><button class="linkish" data-act="profile" data-a="${c.citizen_id}">${esc(nm(c.citizen_id))}</button>${chip(c.party_id)}</div>
          <div class="row" style="gap:6px"><span class="num small">${fmt(c.real_votes)}</span>${valid && !voted && left > 0 && c.citizen_id !== D.me.id ? `<button class="btn sm primary" data-act="vote" data-a="${e.id}|${c.citizen_id}">Vote</button>` : ''}${voted === c.citizen_id ? '<span title="Your vote">🗳️</span>' : ''}</div>
          ${bar(c.real_votes / max * 100)}</div>`).join('')}</div>` : '<div class="empty">No candidates yet. If nobody files, a caretaker committee takes over.</div>'}
      ${mine?.election_id === e.id ? '' : `<div class="row"><button class="btn primary" data-act="declare" data-a="${k}" ${why ? 'disabled' : ''}>Declare candidacy · ${fmt(feeFor(k))}</button><span class="small muted">${why}</span></div>`}
      <p class="small muted">Spending limit ${fmt(o.spend_cap)} · each citizen vote counts heavily on polling day.</p></div>`;
  }).join('');
  const res = V.recent.map(e => { const w = V.cands.filter(c => c.election_id === e.id).sort((a, b) => b.votes - a.votes)[0];
    return w ? `<div class="li"><div class="grow"><b>${esc(officeName(e.key))}</b><div class="small muted">Day ${e.poll_day} · turnout ${fmt(e.turnout)}</div></div><div class="row">${personBtn(w.citizen_id)}${chip(w.party_id)}<span class="num small">${fmt(w.votes)}</span></div></div>` : ''; }).join('');
  return `<div class="stack"><h2>Elections</h2><p class="lede">Revalidate your PVC at least 2 days before polling day, then vote. To run: join a party, stash the fee, and campaign within the legal spending limit.</p></div>
    ${camp}<div class="grid">${races}</div>
    ${res ? `<div class="panel"><h3>Latest results</h3><div>${res}</div></div>` : ''}`;
}

/* ----- Gist ----- */
function vGist() {
  const m = membership(D.me.id), mp = m && party(m.party_id);
  const rooms = [['national', 'National'], ...(mp ? [[mp.id, mp.abbr + ' room']] : [])];
  const posts = V.posts || [];
  return `<div class="stack"><h2>Gist</h2><p class="lede">Talk politics with the whole country, or plan quietly in your party's room.</p></div>
  <div class="tabs">${rooms.map(([id, l]) => `<button data-act="room" data-a="${id}" aria-pressed="${gistRoom === id}">${esc(l)}</button>`).join('')}</div>
  <div class="panel"><label class="f">What's happening?<textarea id="gist-body" maxlength="280" placeholder="Wetin dey happen for your area?"></textarea></label>
    <div><button class="btn primary" data-act="post">Post</button></div></div>
  <div class="panel">${posts.length ? posts.map(p => { const e = p.election_id && V.postEls[p.election_id];
    const canVote = e && e.status === 'open' && D.regs.has(e.id) && !D.myVotes[e.id] && e.poll_day > D.clock.day && p.author_id !== D.me.id;
    return `<div class="li" style="align-items:flex-start;flex-wrap:nowrap">${pic(p.author_id)}
      <div class="grow stack" style="gap:4px"><div class="row" style="gap:6px"><button class="linkish" data-act="profile" data-a="${p.author_id}">${esc(nm(p.author_id))}</button><span class="tiny muted">${ago(p.created_at)}</span>${e ? `<span class="chip pill-warn">Campaign · ${esc(place(e.key))}</span>` : ''}</div>
        <div style="white-space:pre-wrap;word-wrap:break-word">${esc(p.body)}</div>
        <div class="row"><button class="btn sm" data-act="like" data-a="${p.id}">${V.liked.has(p.id) ? '💚' : '🤍'} ${p.likes}</button>${canVote ? `<button class="btn sm primary" data-act="vote" data-a="${e.id}|${p.author_id}">Vote for ${esc(nm(p.author_id).split(' ')[0])}</button>` : ''}</div></div></div>`; }).join('')
    : '<div class="empty">No posts yet. Start the conversation.</div>'}</div>`;
}

/* ----- Chats ----- */
function vChats() {
  const list = D.convs.length ? D.convs.map(c => `<button class="conv" data-act="openchat" data-a="${c.id}" aria-current="${chatWith === c.id}">${avatar(dataSaver ? null : c.avatar_url, c.name)}
      <div class="grow" style="min-width:0"><div class="row between"><b class="n">${esc(c.name)}</b>${+c.unread ? `<span class="dotbadge" style="position:static">${c.unread}</span>` : ''}</div>
      <div class="small muted" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(c.last_body)}</div></div></button>`).join('')
    : '<div class="empty">No chats yet. Open anyone\'s profile and tap Message.</div>';
  const thread = chatWith ? `<div class="panel" style="align-content:stretch">
      <div class="row between"><div class="row"><button class="btn sm" data-act="backchats" aria-label="Back">←</button>${personBtn(chatWith, '')}</div></div>
      <div class="thread" id="thread">${(V.thread || []).map(m => `<div class="bubble ${m.sender_id === D.me.id ? 'me' : 'them'}">${esc(m.body)}<time>${ago(m.created_at)}</time></div>`).join('') || '<div class="empty">Say hello 👋</div>'}</div>
      <form class="row" onsubmit="event.preventDefault();ACT.send()" style="flex-wrap:nowrap"><input id="msg-body" type="text" maxlength="1000" placeholder="Type a message" autocomplete="off"><button class="btn primary" type="submit">Send</button></form></div>` : '';
  const narrow = window.matchMedia('(max-width: 759px)').matches;
  return `<div class="stack"><h2>Chats</h2></div>
    <div class="chatwrap">${narrow && chatWith ? '' : `<div class="panel convs">${list}</div>`}${thread || (narrow ? '' : '<div class="empty">Choose a chat.</div>')}</div>`;
}

/* ----- Me: PVC, profile, connections, marriage ----- */
function pvc() {
  const m = D.me, ps = (V.myEls || []).filter(e => D.regs.has(e.id));
  const pu = `PU ${String(parseInt(m.vin.slice(-4), 16) % 900 + 100).padStart(3, '0')}`;
  return `<div class="pvc" role="img" aria-label="Permanent Voter Card">
    <div class="hd"><div><b>Permanent Voter Card</b>Niger Area Electoral Commission</div><span class="flag" style="border-color:#fff"><i></i><i></i><i></i></span></div>
    <div class="body"><div class="photo">${!dataSaver && m.avatar_url ? `<img src="${esc(m.avatar_url)}" alt="">` : esc(initials(m.display_name))}</div>
      <dl><dt>Name</dt><dd>${esc(m.display_name)}</dd><dt>State</dt><dd>${esc(stateName(m.state_id))}</dd><dt>LGA</dt><dd>${esc(lgaName(m.lga_id))}</dd>
      <dt>Polling unit</dt><dd>${pu}</dd><dt>Issued</dt><dd>${new Date(m.created_at).toLocaleDateString('en-NG')}</dd></dl></div>
    <div class="row between"><span class="vin">${esc(m.vin.match(/.{1,4}/g).join(' '))}</span><span class="chipgold"></span></div>
  </div>`;
}
function vMe() {
  const m = D.me, sp = spouseId(), status = myStatus(), inf = influenceOf(m, status);
  const els = V.myEls || [];
  const myOut = D.proposals.find(p => p.proposer_id === m.id);
  const conns = D.conns.filter(c => c.status === 'accepted').map(c => c.requester_id === m.id ? c.addressee_id : c.requester_id);
  return `<div class="stack"><h2>Me</h2></div>
  <div class="grid">
    <div class="stack">${pvc()}
      <div class="panel"><h3>PVC validity</h3>${els.map(e => { const ok = D.regs.has(e.id), can = D.clock.day <= e.poll_day - 2;
        return `<div class="li"><div class="grow"><b>${esc(officeName(e.key))}</b><div class="small muted">Polls Day ${e.poll_day}</div></div>${ok ? '<span class="chip pill-good">Valid</span>' : can ? `<button class="btn sm primary" data-act="reval" data-a="${e.id}">Revalidate</button>` : '<span class="chip pill-bad">Closed</span>'}</div>`; }).join('') || '<div class="empty">No elections open.</div>'}
        <p class="small muted">INEC stops revalidation 2 days before each polling day.</p></div></div>
    <div class="panel hero"><div class="row">${avatar(dataSaver ? null : m.avatar_url, m.display_name, 'lg')}<div class="stack" style="gap:2px"><h3>${esc(m.display_name)}</h3><span class="small muted">${esc(lgaName(m.lga_id))}, ${esc(stateName(m.state_id))}</span>
        <button class="btn sm" data-act="pickphoto">Change photo</button><input id="pf-photo" type="file" accept="image/*" hidden></div></div>
      <div class="grid3" style="grid-template-columns:repeat(3,1fr)"><div><div class="num big" style="font-size:22px">${inf}</div><span class="tiny muted">Influence</span></div><div><div class="num big" style="font-size:22px">${rep(m)}</div><span class="tiny muted">Reputation</span></div><div><div class="num big" style="font-size:22px">${status}/20</div><span class="tiny muted">Status</span></div></div>
      <label class="f">Bio<textarea id="pf-bio" maxlength="160" placeholder="Tell Niger Area who you are">${esc(m.bio || '')}</textarea></label>
      <label class="f">Who can message me<select id="pf-dm"><option value="everyone"${m.dm_policy === 'everyone' ? ' selected' : ''}>Everyone</option><option value="connections"${m.dm_policy === 'connections' ? ' selected' : ''}>Connections only</option><option value="nobody"${m.dm_policy === 'nobody' ? ' selected' : ''}>Nobody</option></select></label>
      <div class="row"><button class="btn primary" data-act="saveprofile">Save profile</button><button class="btn" data-act="profile" data-a="${m.id}">View my public profile</button></div>
      <label class="row small"><input type="checkbox" ${dataSaver ? 'checked' : ''} data-act="datasaver"> Data saver (hide pictures, fewer live updates)</label></div>
  </div>
  <div class="grid">
    <div class="panel"><h3>Marriage</h3>
      ${sp ? `<div class="row between">${personBtn(sp, '')}<span class="chip pill-good">Married</span></div>
        <label class="row small"><input type="checkbox" ${m.show_spouse ? 'checked' : ''} data-act="showspouse"> Show my spouse on my profile</label>
        <div><button class="btn warn sm" data-act="divorce">Divorce</button></div>`
      : `<p class="small muted">Single. Open a citizen's profile to propose. The wedding costs 6,000 coins, refunded if they say no.</p>`}
      ${proposalsIn().map(p => `<div class="li"><div class="grow">${personBtn(p.proposer_id)}<div class="small muted">${esc(p.note || 'Will you marry me?')}</div></div><div class="row"><button class="btn sm primary" data-act="answerprop" data-a="${p.proposer_id}|1">Accept</button><button class="btn sm" data-act="answerprop" data-a="${p.proposer_id}|0">Decline</button></div></div>`).join('')}
      ${myOut ? `<div class="li"><div class="grow small">You proposed to ${personBtn(myOut.target_id)}</div><button class="btn sm" data-act="withdrawprop">Withdraw</button></div>` : ''}</div>
    <div class="panel"><h3>Connections · ${conns.length}</h3>
      ${pendingIn().map(c => `<div class="li"><div class="grow">${personBtn(c.requester_id)}<span class="tiny muted">wants to connect</span></div><div class="row"><button class="btn sm primary" data-act="accept" data-a="${c.requester_id}">Accept</button><button class="btn sm" data-act="decline" data-a="${c.requester_id}">Decline</button></div></div>`).join('')}
      ${conns.map(id => `<div class="li">${personBtn(id)}<button class="btn sm" data-act="message" data-a="${id}">Message</button></div>`).join('') || (pendingIn().length ? '' : '<div class="empty">No connections yet. Find people on Gist, in your party, or on the leaderboard.</div>')}</div>
  </div>
  <div class="panel"><h3>Badges · ${D.myAch.size}/${R.ach.length}</h3><div class="grid3">${R.ach.map(a => `<div class="action" style="${D.myAch.has(a.id) ? '' : 'opacity:.45'}"><b>${D.myAch.has(a.id) ? '🏅' : '🔒'} ${esc(a.label)}</b><p>${esc(a.blurb)}${a.reward ? ` · +${fmt(a.reward)}` : ''}</p></div>`).join('')}</div></div>
  <div class="row"><button class="btn" data-act="signout">Sign out</button></div>`;
}

/* ----- Wallet ----- */
function vWallet() {
  const w = D.wallet;
  return `<div class="stack"><h2>Wallet</h2><p class="lede">Coins are for playing and can't be cashed out. Buy more with Paystack. Civic points, earned only by playing, turn into airtime.</p></div>
  <div class="grid">
    <div class="panel hero"><span class="eyebrow">Coins</span><div class="big">${fmt(w.coins)}</div>
      <span class="eyebrow">Buy coins</span><div class="row">${R.packs.map(p => `<button class="btn" data-act="buycoins" data-a="${p.id}">${fmt(p.coins)} · ₦${fmt(p.kobo / 100)}</button>`).join('')}</div>
      <p class="small muted">Paid securely with Paystack. Bought coins can't be withdrawn, earn no civic points, and still count toward each race's spending limit.</p></div>
    <div class="panel"><span class="eyebrow">Campaign stash</span><div class="big">${fmt(w.stash)}</div>
      <p class="small muted">Nomination fees and campaign spending come from here. Withdrawing costs a 10% party levy.</p>
      <div class="row" style="flex-wrap:nowrap"><input id="amt-stash" type="number" inputmode="numeric" min="1" placeholder="Amount"><button class="btn primary" data-act="stash">Stash</button><button class="btn" data-act="unstash">Withdraw</button></div></div>
    <div class="panel"><span class="eyebrow">Civic points</span><div class="big">${fmt(w.cp)}</div>
      <label class="f">Airtime number<input id="rd-phone" type="text" inputmode="tel" placeholder="+2348012345678"></label>
      <div class="row"><button class="btn" data-act="redeem" data-a="500" ${w.cp < 500 ? 'disabled' : ''}>₦100 · 500 pts</button><button class="btn" data-act="redeem" data-a="2000" ${w.cp < 2000 ? 'disabled' : ''}>₦400 · 2,000 pts</button></div>
      <p class="small muted">Needs an ID check (NIN or BVN). Limit 2,500 points a week. To send coins to someone, open their profile.</p></div>
  </div>
  <div class="panel"><h3>Transactions</h3><div>${(V.ledger || []).map(x => `<div class="li"><div class="grow small">${esc(x.reason.replace(/_/g, ' ').replace(/^campaign:/, 'campaign: '))}${x.cur !== 'coins' ? ` <span class="muted">(${x.cur === 'cp' ? 'civic points' : 'stash'})</span>` : ''}<div class="tiny muted">${ago(x.created_at)}</div></div><div class="num small" style="color:var(--${x.delta >= 0 ? 'good' : 'bad'})">${x.delta >= 0 ? '+' : ''}${fmt(x.delta)}</div></div>`).join('') || '<div class="empty">Nothing yet.</div>'}</div></div>`;
}

/* ----- Household ----- */
function vHome() {
  const groups = [['house', 'Where you live'], ['car', 'How you move'], ['extra', 'Around the house'], ['family', 'Family'], ['business', 'Businesses']];
  const card = it => {
    if (it.id === 'spouse') return `<div class="action"><b>Marriage</b><p>Marry another citizen: open their profile and propose.</p><div>${spouseId() ? '<span class="chip pill-good">Married</span>' : `<button class="btn sm" data-act="go" data-a="me">See proposals</button>`}</div></div>`;
    const have = D.myItems[it.id] || 0, locked = it.requires && !D.myItems[it.requires], maxed = have >= it.max_qty;
    return `<div class="action"><b>${esc(it.label)}${it.max_qty > 1 ? ` × ${have}` : ''}</b><p>+${it.status_points} status${it.daily_income ? ` · +${it.daily_income} coins a day` : ''}${locked ? (it.requires === 'spouse' ? ' · get married first' : ' · buy the previous one first') : ''}</p>
      <div>${maxed && it.max_qty === 1 ? '<span class="chip pill-good">Owned</span>' : `<button class="btn sm primary" data-act="buy" data-a="${it.id}" ${locked || maxed ? 'disabled' : ''}>Buy · ${fmt(priceOf(it.cost))}</button>`}</div></div>`;
  };
  return `<div class="stack"><h2>Household</h2><p class="lede">Your home, ride and family raise your status (max 20). Businesses pay you every day at midnight.</p></div>
    <div class="banner">Status ${myStatus()}/20 · prices include ${pct(taxes().vat)} VAT set by the President${taxes().stax ? ` and ${pct(taxes().stax)} ${esc(stateName(D.me.state_id))} state tax` : ''}.</div>
    ${groups.map(([k, t]) => `<div class="panel"><h3>${t}</h3><div class="grid3">${R.items.filter(i => i.kind === k).map(card).join('')}</div></div>`).join('')}`;
}

/* ----- Party ----- */
function vParty() {
  const m = membership(D.me.id), view = V.partyView && party(V.partyView);
  const list = `<div class="panel"><h3>Registered parties</h3><div>${[...D.parties].sort((a, b) => memberCount(b.id) - memberCount(a.id)).map(p => `<div class="li">
    <button class="linkish grow" data-act="partyview" data-a="${p.id}" style="display:grid;gap:2px"><span class="row"><span class="dot" style="background:${esc(p.color)}"></span>${esc(p.name)} <span class="muted">${esc(p.abbr)}</span></span>
      <span class="small muted num" style="font-weight:400">${memberCount(p.id)} member${memberCount(p.id) === 1 ? '' : 's'} · ${strength(p.id).toFixed(1)}% · ${D.offices.filter(o => o.holder_party === p.id).length} offices</span></button>
    ${m?.party_id === p.id ? '<span class="chip pill-good">Your party</span>' : !m ? `<button class="btn sm" data-act="join" data-a="${p.id}">Join · 200</button>` : ''}</div>`).join('')}</div></div>`;
  const members = view ? `<div class="panel ${m?.party_id === view.id ? 'hero' : ''}">
      <div class="row between"><div class="row"><span class="dot" style="background:${esc(view.color)};width:14px;height:14px"></span><h3>${esc(view.name)}</h3></div><span class="chip">${esc(view.abbr)}</span></div>
      <div class="num small">${V.partyMembers.length} member${V.partyMembers.length === 1 ? '' : 's'} · ${strength(view.id).toFixed(1)}% national strength</div>${bar(strength(view.id))}
      <div>${V.partyMembers.map(x => `<div class="li">${personBtn(x.citizen_id)}<div class="row">${x.role === 'chair' ? '<span class="chip pill-warn">Chairman</span>' : ''}${officeOf(x.citizen_id) ? `<span class="chip pill-info">${esc(R.rules[typeOf(officeOf(x.citizen_id).key)].title)}</span>` : ''}${x.citizen_id !== D.me.id ? `<button class="btn sm" data-act="message" data-a="${x.citizen_id}">Message</button>` : ''}</div></div>`).join('') || '<div class="empty">No members yet. Be the first.</div>'}</div>
      ${m?.party_id === view.id && m.role !== 'chair' ? '<div><button class="btn warn sm" data-act="leave">Decamp</button> <span class="small muted">You lose any ticket you hold.</span></div>' : ''}</div>` : '';
  const create = !m ? `<div class="panel"><h3>Form your own party</h3><p class="small muted">5,000 coins. You become National Chairman.</p>
      <label class="f">Party name<input id="np-name" type="text" maxlength="40"></label>
      <div class="row" style="flex-wrap:nowrap"><label class="f" style="flex:1">Abbreviation<input id="np-abbr" type="text" maxlength="6"></label>
      <label class="f" style="flex:1">Colour<select id="np-color"><option value="#6B3FA0">Purple</option><option value="#0E8C8C">Teal</option><option value="#C2185B">Magenta</option><option value="#546E1A">Olive</option><option value="#1A237E">Navy</option></select></label></div>
      <div><button class="btn primary" data-act="create">Register with INEC · 5,000</button></div></div>` : '';
  return `<div class="stack"><h2>Party</h2><p class="lede">No party, no ticket. Tap any party to see its members.</p></div>${members}<div class="grid">${list}${create}</div>`;
}

/* ----- Office ----- */
function vOffice() {
  const off = myOffice();
  if (!off) return `<div class="stack"><h2>Office</h2><p class="lede">You don't hold office yet. Win an election to make decisions: issue decrees, award contracts, pay salaries and, as an executive, order arrests.</p></div><div><button class="btn primary" data-act="go" data-a="elections">See elections</button></div>`;
  const j = V.jur; if (!j) return '<div class="empty">Loading…</div>';
  const k = off.key, t = typeOf(k), o = R.rules[t], ap = approval(j), left = off.term_ends_day - D.clock.day, unpaid = D.clock.day - j.last_salary_day;
  const lastDecree = id => V.decreeLog.find(d => d.decree_id === id)?.day;
  return `<div class="stack"><span class="eyebrow">${o.title} · term ends Day ${off.term_ends_day} (${left} days)</span><h2>${esc(officeName(k))}</h2><p class="lede">Salary ${fmt(o.salary)} coins a day. Monthly FAAC allocation ${fmt(o.alloc)}.</p></div>
  <div class="grid">
    <div class="panel hero"><div class="row between"><span class="eyebrow">Approval</span><span class="chip pill-${tone(ap) === 'g' ? 'good' : tone(ap) === 'w' ? 'warn' : 'bad'}">${ap >= 60 ? 'Popular' : ap >= 35 ? 'Restless' : 'Angry'}</span></div>
      <div class="big">${ap}%</div>${bar(ap)}<p class="small muted">Treasury <span class="num">${fmt(j.treasury)}</span> · salaries paid ${unpaid} day${unpaid === 1 ? '' : 's'} ago · 60%+ earns 50 civic points a day</p></div>
    <div class="panel"><span class="eyebrow">Your people</span>${STATS.map(([s, l]) => `<div class="stat"><span>${l}</span>${bar(+j[s])}<span class="num small">${Math.round(j[s])}</span></div>`).join('')}</div>
  </div>
  <div class="panel"><h3>Decisions</h3><div class="grid3">${R.decrees.filter(d => d.office === t).map(d => { const last = lastDecree(d.id), cd = last != null && D.clock.day - last < d.cooldown_days;
    const eff = Object.entries(d.effects).map(([s, v]) => `${s === 'mood' ? 'rapport' : s} ${v > 0 ? '+' : ''}${v}`).join(', ');
    return `<div class="action"><b>${esc(d.label)}</b><p>${esc(d.blurb)}</p><p class="tiny muted">${esc(eff)}${d.treasury_delta ? ` · treasury ${d.treasury_delta > 0 ? '+' : ''}${fmt(d.treasury_delta)}` : ''}</p>
      <div><button class="btn sm primary" data-act="decree" data-a="${d.id}" ${cd || energy() < 1 ? 'disabled' : ''}>${cd ? 'Again on Day ' + (last + d.cooldown_days) : 'Sign order'}</button></div></div>`; }).join('')}</div></div>
  ${t === 'PRES' ? vPresPowers() : t === 'GOV' ? vGovPowers(k) : ''}
  <div class="panel"><h3>Projects</h3><div class="grid3">${STATS.map(([s]) => `<div class="action"><b>${PROJECT[s]}</b><p>Ready in 3 days.</p><div><button class="btn sm primary" data-act="project" data-a="${s}" ${j.treasury < o.project_cost || energy() < 1 ? 'disabled' : ''}>Award · ${fmt(o.project_cost)}</button></div></div>`).join('')}</div>
    ${V.projects.length ? `<p class="small muted">Under construction: ${V.projects.map(p => `${PROJECT[p.stat]} (Day ${p.ready_day})`).join(', ')}</p>` : ''}</div>
  <div class="grid">
    <div class="panel"><h3>Town and workers</h3>
      <div class="li"><div class="grow"><b>Town hall meeting</b><div class="small muted">1 energy. +0.5 reputation.</div></div><button class="btn sm primary" data-act="townhall">Hold</button></div>
      <div class="li"><div class="grow"><b>Pay salaries</b><div class="small muted">${fmt(o.project_cost * 0.8)} from treasury. Skip 30 days and workers strike.</div></div><button class="btn sm primary" data-act="salaries">Pay</button></div></div>
    ${t === 'SEN' ? '<div class="panel"><h3>Arrests</h3><p class="small muted">Senators make laws. Only LG Chairmen, Governors and the President can order arrests.</p></div>'
    : `<div class="panel"><h3>Order an arrest</h3><p class="small muted">One a day, within your jurisdiction. Arresting a clean citizen sparks outrage and raises your scandal.</p>
      <form class="row" style="flex-wrap:nowrap" onsubmit="event.preventDefault();ACT.arrestsearch()"><input id="ar-q" type="search" placeholder="Search a citizen by name"><button class="btn" type="submit">Find</button></form>
      <div>${(V.arrestHits || []).map(c => `<div class="li">${personBtn(c.id)}<button class="btn sm warn" data-act="arrest" data-a="${c.id}">Arrest</button></div>`).join('')}</div></div>`}
  </div>`;
}

function vPresPowers() {
  const n = D.policies.nation, cd = n.updated_day != null && D.clock.day - n.updated_day < 3;
  return `<div class="grid">
    <div class="panel"><h3>National policy</h3><p class="small muted">VAT is added to every purchase in Niger Area and paid into the federal treasury. Raising it angers people.</p>
      <div class="row" style="flex-wrap:nowrap"><label class="f" style="flex:1">VAT (0–25%)<input id="pol-vat" type="number" min="0" max="25" step="0.5" value="${Math.round(n.vat * 1000) / 10}"></label>
      <label class="f" style="flex:1">Nomination fees (50–200%)<input id="pol-fee" type="number" min="50" max="200" step="5" value="${Math.round(n.fee_mult * 100)}"></label></div>
      <div><button class="btn primary" data-act="setnational" ${cd ? 'disabled' : ''}>${cd ? 'Again on Day ' + (n.updated_day + 3) : 'Announce policy'}</button></div>
      <p class="small muted">Nomination fees apply to Senate, Governor and President races. Governors set LG fees.</p></div>
    <div class="panel"><h3>Salaries</h3><p class="small muted">Only you set them. Paid daily from each government's own treasury. Raising your own pay is unpopular.</p>
      ${['PRES', 'GOV', 'SEN', 'LG'].map(x => { const r = R.rules[x], c = r.salary_set_day != null && D.clock.day - r.salary_set_day < 3;
        return `<form class="row" style="flex-wrap:nowrap" onsubmit="event.preventDefault();ACT.setsalary('${x}')"><label class="f" style="flex:1">${r.title} (max ${x === 'PRES' ? '10,000' : '5,000'})<input id="sal-${x}" type="number" min="0" max="${x === 'PRES' ? 10000 : 5000}" value="${r.salary}"></label><button class="btn sm" type="submit" ${c ? 'disabled' : ''}>${c ? 'Day ' + (r.salary_set_day + 3) : 'Set'}</button></form>`; }).join('')}</div>
    <div class="panel"><h3>Presidential tenure</h3><p class="small muted">Between 3 and 5 years (one game month = one year). Changes your current term too. Extending it is unpopular.</p>
      <label class="f">Years<select id="pol-tenure">${[3, 4, 5].map(y => `<option value="${y}" ${Math.round(R.rules.PRES.term_days / 30) === y ? 'selected' : ''}>${y} years (${y * 30} days)</option>`).join('')}</select></label>
      <div><button class="btn warn" data-act="settenure">Change tenure</button></div></div></div>`;
}
function vGovPowers(k) {
  const sid = k.split(':')[1], p = D.policies[sid], cd = p.updated_day != null && D.clock.day - p.updated_day < 3;
  return `<div class="panel"><h3>State policy</h3><p class="small muted">State tax is added to purchases by ${esc(stateName(sid))} residents and paid into your state treasury. You also set LG nomination fees in your state.</p>
    <div class="row" style="flex-wrap:nowrap"><label class="f" style="flex:1">State tax (0–15%)<input id="pol-stax" type="number" min="0" max="15" step="0.5" value="${Math.round(p.state_tax * 1000) / 10}"></label>
    <label class="f" style="flex:1">LG nomination fees (50–200%)<input id="pol-sfee" type="number" min="50" max="200" step="5" value="${Math.round(p.fee_mult * 100)}"></label></div>
    <div><button class="btn primary" data-act="setstate" ${cd ? 'disabled' : ''}>${cd ? 'Again on Day ' + (p.updated_day + 3) : 'Announce policy'}</button></div></div>`;
}

/* ----- Nation ----- */
function vNation() {
  const holder = k => { const o = D.offices.find(x => x.key === k); return o?.holder_id ? `${personBtn(o.holder_id)} ${chip(o.holder_party)}` : '<span class="muted">Caretaker</span>'; };
  const ja = V.jurAll || {};
  return `<div class="stack"><h2>Niger Area</h2><p class="lede">36 states and the Federal Capital Territory. Who rules where, and how their people feel.</p></div>
  <div class="grid">
    <div class="panel hero"><span class="eyebrow">President · ${years(R.rules.PRES.term_days)} term</span><div>${holder('PRES')}</div><p class="small muted">VAT ${pct(D.policies.nation.vat)} · nomination fees ${Math.round(D.policies.nation.fee_mult * 100)}% · presidential salary ${fmt(R.rules.PRES.salary)} a day</p>${ja.PRES ? `<div class="stat"><span>Approval</span>${bar(approval(ja.PRES))}<span class="num small">${approval(ja.PRES)}</span></div>` : ''}</div>
    <div class="panel"><span class="eyebrow">Recent arrests</span><div>${(V.arrests || []).map(a => `<div class="li small"><div class="grow">${esc(nm(a.target_id))} · <span class="muted">${esc(a.charge)}</span></div><span class="tiny muted">by ${esc(nm(a.by_id))}</span></div>`).join('') || '<div class="empty">The police are quiet.</div>'}</div></div>
  </div>
  <div class="panel"><h3>States</h3><div class="table-wrap"><table><thead><tr><th>State</th><th>Governor</th><th>Senator</th><th>State tax</th><th>Approval</th></tr></thead><tbody>
    ${R.states.map(s => { const k = s.has_governor ? 'GOV:' + s.id : 'SEN:' + s.id, a = ja[k] ? approval(ja[k]) : 0;
      return `<tr${s.id === D.me.state_id ? ' style="font-weight:700"' : ''}><td>${esc(s.name)}</td><td>${s.has_governor ? holder('GOV:' + s.id) : '<span class="muted">FCT Minister</span>'}</td><td>${holder('SEN:' + s.id)}</td><td class="num">${D.policies[s.id] ? pct(D.policies[s.id].state_tax) : '—'}</td><td style="min-width:110px">${bar(a)}<span class="num small">${a}</span></td></tr>`; }).join('')}
  </tbody></table></div></div>`;
}

/* ----- Leaderboard ----- */
function vLeaders() {
  const b = V.board; if (!b) return '<div class="empty">Loading…</div>';
  b.richest.concat(b.respected, b.streaks).forEach(x => { names[x.id] = names[x.id] || { id: x.id, display_name: x.name }; });
  const table = (title, rows, valFn) => `<div class="panel"><h3>${title}</h3><div>${rows.map((r, i) => `<div class="li"><div class="row" style="flex-wrap:nowrap;min-width:0"><span class="num muted" style="width:22px">${i + 1}</span>${personBtn(r.id)}</div><span class="num small">${valFn(r)}</span></div>`).join('') || '<div class="empty">No one yet.</div>'}</div></div>`;
  return `<div class="stack"><h2>Leaderboard</h2></div><div class="grid">
    ${table('Richest', b.richest, r => fmt(r.coins))}${table('Most respected', b.respected, r => 'rep ' + r.rep)}${table('Longest streaks', b.streaks, r => '🔥 ' + r.streak)}
    <div class="panel"><h3>Parties</h3><div>${b.parties.map(p => `<div class="li"><span class="row"><span class="dot" style="background:${esc(p.color)}"></span>${esc(p.name)}</span><span class="num small">${p.members} · ${p.offices} offices</span></div>`).join('')}</div></div></div>`;
}

/* ----- News ----- */
function vNews() {
  const ICON_K = { election: '🗳️', party: '🚩', law: '🚔', government: '🏛️', announcement: '📢', general: '👤' };
  return `<div class="stack"><h2>Niger Area Times</h2><p class="lede">Who won, who joined, who decamped, who got arrested, and what the government decided.</p></div>
    <div class="tabs">${NEWS_KINDS.map(([k, l]) => `<button data-act="newskind" data-a="${k}" aria-pressed="${newsKind === k}">${l}</button>`).join('')}</div>
    <div class="panel">${(V.news || []).map(n => `<div class="li" style="flex-wrap:nowrap;align-items:flex-start"><span aria-hidden="true">${ICON_K[n.kind] || '•'}</span><div class="grow">${esc(n.body)}<div class="tiny muted">Day ${n.day} · ${ago(n.created_at)}</div></div></div>`).join('') || '<div class="empty">No news in this section yet.</div>'}</div>`;
}

/* ----- Sheets ----- */
function vSheet() {
  if (!sheet) return '';
  let h = '';
  if (sheet.type === 'more') h = `<h3>More</h3><div class="grid3" style="grid-template-columns:repeat(2,1fr)">
      ${[['me', 'Me & PVC'], ...MORE].map(([p, l]) => `<button class="btn" data-act="go" data-a="${p}" style="display:flex;gap:8px;align-items:center;justify-content:flex-start">${icon(ICON_FOR[p])}${l}${p === 'me' ? badgeFor('me') : ''}</button>`).join('')}
      ${D.isAdmin ? `<button class="btn" onclick="location.href='admin.html'" style="display:flex;gap:8px;align-items:center">${icon('shield')}Owner dashboard</button>` : ''}</div>
      <div class="row between"><button class="btn" data-act="close">Close</button><button class="btn warn" data-act="signout" style="display:flex;gap:8px;align-items:center">${icon('logout')}Sign out</button></div>`;
  else if (sheet.type === 'ad') h = `<span class="eyebrow">Sponsored</span><div class="adbox">Your brand could be here.<br>Advertise to Niger Area citizens.<br><span class="num">${sheet.left}s</span></div><p class="small muted">Stay on this screen to earn 400 coins.</p><button class="btn" data-act="close">Skip (no coins)</button>`;
  else if (sheet.type === 'profile') h = vProfile();
  else if (sheet.type === 'arrest') h = `<h3>Arrest ${esc(nm(sheet.id))}?</h3><label class="f">Charge<select id="ar-charge">${CHARGES.map(c => `<option>${c}</option>`).join('')}</select></label>
      <p class="small muted">They will be held for 24 hours unless they post bail. If they have a clean record, the public will turn on you.</p>
      <div class="row"><button class="btn warn" data-act="doarrest">Order arrest</button><button class="btn" data-act="close">Cancel</button></div>`;
  else if (sheet.type === 'propose') h = `<h3>Propose to ${esc(nm(sheet.id))}</h3><label class="f">Your words<textarea id="pr-note" maxlength="200" placeholder="You be my missing rib..."></textarea></label>
      <p class="small muted">6,000 coins for the wedding are held now and refunded if they decline.</p><div class="row"><button class="btn primary" data-act="dopropose">Propose 💍</button><button class="btn" data-act="close">Cancel</button></div>`;
  else if (sheet.type === 'report') h = `<h3>Report ${esc(nm(sheet.id))}</h3><label class="f">What happened?<textarea id="rp-reason" maxlength="500"></textarea></label>
      <p class="small muted">The Niger Area team reviews every report. They can read your conversation with this person when deciding.</p><div class="row"><button class="btn warn" data-act="doreport">Send report</button><button class="btn" data-act="close">Cancel</button></div>`;
  else if (sheet.type === 'gift') h = `<h3>Send coins to ${esc(nm(sheet.id))}</h3><label class="f">Amount<input id="amt-gift" type="number" inputmode="numeric" min="1" max="2000"></label>
      <p class="small muted">Up to 2,000 a day. Both accounts must be at least 7 days old.</p><div class="row"><button class="btn primary" data-act="gift">Send</button><button class="btn" data-act="close">Cancel</button></div>`;
  else if (sheet.type === 'confirm') h = `<p>${esc(sheet.text)}</p><div class="row"><button class="btn warn" data-act="${sheet.act}">Yes</button><button class="btn" data-act="close">No</button></div>`;
  return `<div class="scrim" data-scrim><div class="sheet" role="dialog" aria-modal="true">${h}</div></div>`;
}
function exTitles(terms, off) {
  const past = {};
  (terms || []).forEach(t => { if (off && t.key === off.key && t.end_day == null) return; (past[t.key] = past[t.key] || []).push(t); });
  const keys = Object.keys(past); if (!keys.length) return '';
  const rank = { PRES: 4, GOV: 3, SEN: 2, LG: 1 };
  keys.sort((a, b) => rank[typeOf(b)] - rank[typeOf(a)]);
  return `<div class="row">${keys.map(k => { const ts = past[k], n = ts.length, label = typeOf(k) === 'PRES' ? 'Ex-President' : 'Former ' + officeName(k);
    const last = ts.slice().sort((a, b) => (b.end_day || 0) - (a.end_day || 0))[0];
    return `<span class="chip" title="${esc(last.ended_how || '')}">🎖️ ${esc(label)} · ${n} term${n === 1 ? '' : 's'}</span>`; }).join('')}</div>`;
}
function vProfile() {
  const s = sheet; if (s.loading) return '<div class="empty">Loading profile…</div>';
  const c = s.c, me = c.id === D.me.id, mem = membership(c.id), off = officeOf(c.id);
  const status = statusOf(s.items, c.gift_status, mem?.role === 'chair'), inf = influenceOf(c, status);
  const cn = connWith(c.id), myOff = myOffice(), canArrest = myOff && !me && typeOf(myOff.key) !== 'SEN' && (typeOf(myOff.key) === 'PRES' || (typeOf(myOff.key) === 'GOV' ? c.state_id === myOff.key.split(':')[1] : c.lga_id === myOff.key.split(':')[2]));
  const detained = c.detained_until && new Date(c.detained_until) > new Date();
  const connBtn = me ? '' : !cn ? `<button class="btn" data-act="connect" data-a="${c.id}">Connect</button>`
    : cn.status === 'accepted' ? `<button class="btn" data-act="unconnect" data-a="${c.id}">Connected ✓</button>`
    : cn.requester_id === D.me.id ? '<button class="btn" disabled>Request sent</button>' : `<button class="btn primary" data-act="accept" data-a="${c.id}">Accept request</button>`;
  return `<div class="row" style="flex-wrap:nowrap">${avatar(dataSaver ? null : c.avatar_url, c.display_name, 'lg')}<div class="stack" style="gap:4px;min-width:0">
      <h3>${esc(c.display_name)}${off ? ' <span class="verified" style="font-size:18px">✔</span>' : ''}</h3>${off ? `<span class="verified" style="margin-left:0">${esc(officeName(off.key))} · until Day ${off.term_ends_day}</span>` : ''}<span class="small muted">${esc(lgaName(c.lga_id))}, ${esc(stateName(c.state_id))} · citizen since ${new Date(c.created_at).toLocaleDateString('en-NG', { month: 'short', year: 'numeric' })}</span>
      <div class="row">${mem ? chip(mem.party_id) : chip(null)}${mem?.role === 'chair' ? '<span class="chip pill-warn">Party chairman</span>' : ''}${off ? `<span class="chip pill-info">${esc(officeName(off.key))}</span>` : ''}${detained ? '<span class="chip pill-bad">In custody</span>' : ''}</div></div></div>
    ${c.bio ? `<p>${esc(c.bio)}</p>` : ''}
    ${exTitles(s.terms, off)}
    ${s.spouse ? `<div class="row small">💍 Married to ${personBtn(s.spouse.id)}</div>` : ''}
    <div class="grid3" style="grid-template-columns:repeat(4,1fr);gap:6px;text-align:center">
      <div><div class="num" style="font-size:20px;font-weight:700">${inf}</div><span class="tiny muted">Influence</span></div>
      <div><div class="num" style="font-size:20px;font-weight:700">${rep(c)}</div><span class="tiny muted">Reputation</span></div>
      <div><div class="num" style="font-size:20px;font-weight:700">${c.offices_held}</div><span class="tiny muted">Offices won</span></div>
      <div><div class="num" style="font-size:20px;font-weight:700">🔥${c.streak}</div><span class="tiny muted">Streak</span></div></div>
    <div><span class="eyebrow">Badges · ${s.ach.size}</span><div class="row" style="margin-top:6px">${R.ach.filter(a => s.ach.has(a.id)).map(a => `<span class="chip" title="${esc(a.blurb)}">🏅 ${esc(a.label)}</span>`).join('') || '<span class="small muted">No badges yet.</span>'}</div></div>
    ${me ? '<p class="small muted">This is how other citizens see you.</p>' : `<div class="row">${c.dm_policy !== 'nobody' ? `<button class="btn primary" data-act="message" data-a="${c.id}">Message</button>` : '<span class="chip">Not accepting messages</span>'}${connBtn}
      <button class="btn" data-act="giftto" data-a="${c.id}">Send coins</button>${!spouseId() ? `<button class="btn" data-act="propose" data-a="${c.id}">Propose 💍</button>` : ''}
      ${canArrest && !detained ? `<button class="btn warn" data-act="arrest" data-a="${c.id}">Order arrest</button>` : ''}<button class="btn warn" data-act="report" data-a="${c.id}">Report</button></div>`}
    <button class="btn" data-act="close">Close</button>`;
}

/* ================= render & wiring ================= */
function render() {
  const app = document.getElementById('app');
  if (recovering) { app.innerHTML = vRecovery(); return; }
  if (!user) { app.innerHTML = vAuth(); return; }
  if (!R || !D) { app.innerHTML = '<div class="setup"><span class="stamp">Loading</span><h1>Niger Area</h1></div>'; return; }
  if (!D.me && D.isAdmin) { app.innerHTML = `<div class="setup"><span class="stamp">Owner account</span><h1>Niger Area</h1>
      <p class="lede">This is an owner account. Owners run the backend and don't play as citizens.</p>
      <div class="row"><a class="btn primary" href="admin.html">Open the control room</a><button class="btn" data-act="signout">Sign out</button></div></div>`; return; }
  if (!D.me) { app.innerHTML = vRegister(); return; }
  const m = D.me;
  if (m.banned || (m.suspended_until && new Date(m.suspended_until) > new Date()) || (m.detained_until && new Date(m.detained_until) > new Date())) { app.innerHTML = vBlocked(); return; }
  const views = { today: vToday, elections: vElections, gist: vGist, chats: vChats, me: vMe, wallet: vWallet, home: vHome, party: vParty, office: vOffice, nation: vNation, leaders: vLeaders, news: vNews };
  const focus = document.activeElement?.id, keep = focus && document.getElementById(focus)?.value;
  app.innerHTML = `<div class="shell">${topbar()}${nav()}<main class="view" id="main">${(views[page] || vToday)()}</main></div>${vSheet()}`;
  if (focus && document.getElementById(focus)) { const el = document.getElementById(focus); if (keep != null && 'value' in el) el.value = keep; el.focus(); }
}

document.addEventListener('click', e => {
  if (e.target.matches('[data-scrim]')) { ACT.close(); return; }
  const b = e.target.closest('[data-act]'); if (!b || b.disabled) return;
  const f = ACT[b.dataset.act]; if (!f) return;
  if (b.tagName !== 'INPUT') e.preventDefault();
  f(b.dataset.a);
});
document.addEventListener('change', e => {
  if (e.target.id === 'su-state') { vRegister.sid = e.target.value; const n = val('su-name'); render(); document.getElementById('su-name').value = n; }
  if (e.target.id === 'pf-photo') uploadPhoto(e.target.files[0]);
});
document.addEventListener('keydown', e => { if (e.key === 'Escape' && sheet) ACT.close(); });

/* Live updates. Data saver turns these off and relies on the 2-minute refresh. */
function setupRealtime() {
  if (rt) { sb.removeChannel(rt); rt = null; }
  if (!user || !D?.me || dataSaver) return;
  rt = sb.channel('live')
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, async p => {
      const m = p.new;
      if (m.recipient_id === D.me.id) {
        if (page === 'chats' && chatWith === m.sender_id) { await loadThread(); render(); scrollThread(); }
        else { D.convs = (await sb.rpc('my_conversations')).data || []; await ensureNames([m.sender_id]); toast(`💬 ${nm(m.sender_id)}: ${m.body.slice(0, 60)}`); render(); }
      }
    })
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'news' }, p => { D.headline = p.new.body; if (page === 'news') loadPage().then(render); else render(); })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'posts' }, () => { if (page === 'gist') loadPage().then(render); })
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'candidates' }, () => { if (page === 'elections') loadPage().then(render); })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'connections' }, async () => { await loadCore(); render(); })
    .subscribe();
}

async function boot() {
  try {
    if (!R) await loadRefs();
    await loadCore();
    if (D.me) { sb.rpc('touch'); await loadPage(); setupRealtime(); }
  } catch (e) { toast(e.message, true); }
  render();
}
sb.auth.onAuthStateChange((_ev, session) => {
  if (_ev === 'PASSWORD_RECOVERY') { recovering = true; setTimeout(render, 0); }
  const was = user?.id; user = session?.user || null;
  if (!user) { D = null; if (rt) { sb.removeChannel(rt); rt = null; } render(); return; }
  if (was !== user.id) setTimeout(boot, 0);
});
setInterval(async () => {
  if (!user || !D?.me || busy || document.visibilityState !== 'visible' || sheet) return;
  try { await loadCore(); await loadPage(); render(); } catch (_) {}
}, dataSaver ? 120000 : 60000);
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && user && D?.me) { sb.rpc('touch'); } });
render();
