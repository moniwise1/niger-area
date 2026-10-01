// Shared by the game (index.html) and the owner dashboard (admin.html).
const SUPABASE_URL = 'https://hmbgkmbtdhgoafbqafej.supabase.co';
const SUPABASE_KEY = 'sb_publishable_i3_UjySn15NGFpg7lWIh3A_W3lKhhJi';   // publishable: safe in the browser
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

const fmt = n => Math.round(Number(n) || 0).toLocaleString('en-NG');
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const val = id => document.getElementById(id)?.value ?? '';
const tone = v => v >= 60 ? 'g' : v >= 35 ? 'w' : 'b';
const bar = v => `<div class="bar ${tone(v)}"><i style="width:${clamp(+v || 0, 0, 100)}%"></i></div>`;
const initials = n => String(n || '?').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('').toUpperCase();
const AV_COLORS = ['#008751', '#B07A18', '#3478C4', '#C2185B', '#6B3FA0', '#0E8C8C', '#D2412F', '#546E1A'];
function avatar(url, name, size = '') {
  if (url) return `<img class="av ${size}" src="${esc(url)}" alt="" loading="lazy">`;
  const c = AV_COLORS[[...String(name || '')].reduce((a, ch) => a + ch.charCodeAt(0), 0) % AV_COLORS.length];
  return `<span class="av ${size}" style="background:${c}" aria-hidden="true">${esc(initials(name))}</span>`;
}
function ago(ts) {
  const s = (Date.now() - new Date(ts).getTime()) / 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return Math.floor(s / 60) + 'm ago';
  if (s < 86400) return Math.floor(s / 3600) + 'h ago';
  return Math.floor(s / 86400) + 'd ago';
}
const watTime = ts => new Date(ts).toLocaleString('en-NG', { timeZone: 'Africa/Lagos', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

function toast(msg, err) {
  let t = document.getElementById('toast');
  if (!t) { t = document.createElement('div'); t.id = 'toast'; t.setAttribute('role', 'status'); document.body.appendChild(t); }
  t.className = 'toast' + (err ? ' err' : ''); t.textContent = msg;
  clearTimeout(toast.t); toast.t = setTimeout(() => t.remove(), 3800);
}
async function q(p) { const { data, error } = await p; if (error) throw error; return data; }

// Time until the next game day (midnight West Africa Time).
function untilMidnightWAT() {
  const now = new Date();
  const lagos = new Date(now.toLocaleString('en-US', { timeZone: 'Africa/Lagos' }));
  const next = new Date(lagos); next.setHours(24, 0, 0, 0);
  const m = Math.round((next - lagos) / 60000);
  return `${Math.floor(m / 60)}h ${m % 60}m`;
}

const ICONS = {
  today: '<path d="M12 3v2M12 19v2M5 12H3M21 12h-2M6.3 6.3 4.9 4.9M19.1 19.1l-1.4-1.4M6.3 17.7l-1.4 1.4M19.1 4.9l-1.4 1.4"/><circle cx="12" cy="12" r="4"/>',
  vote: '<path d="M4 11h16v9H4z"/><path d="m9 7 3 3 5-6"/><path d="M8 15h8"/>',
  gist: '<path d="M4 5h16v11H8l-4 4z"/>',
  chat: '<path d="M7 9h10M7 13h6"/><path d="M4 4h16v13H9l-5 4z"/>',
  me: '<circle cx="12" cy="8" r="4"/><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6"/>',
  wallet: '<rect x="3" y="6" width="18" height="13" rx="2"/><path d="M16 12h2"/><path d="M3 9h18"/>',
  home: '<path d="m3 11 9-7 9 7"/><path d="M5 10v10h14V10"/><path d="M10 20v-5h4v5"/>',
  party: '<path d="M5 21V4"/><path d="M5 4h11l-2 4 2 4H5"/>',
  office: '<path d="M3 21h18"/><path d="M5 21V10l7-5 7 5v11"/><path d="M9 21v-6h6v6"/>',
  nation: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.5 3 14.5 0 18M12 3c-3 3.5-3 14.5 0 18"/>',
  news: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 8h10M7 12h10M7 16h6"/>',
  more: '<circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>',
  board: '<path d="M6 20V10M12 20V4M18 20v-7"/>',
  shield: '<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/>'
};
const icon = k => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[k] || ''}</svg>`;
