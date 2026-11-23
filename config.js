const db = supabase.createClient('https://qyeawqakvfapezprggws.supabase.co', 'sb_publishable_fxU1FTE51djh8wW0AjQQpQ_RhSjZBdt');
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmt = d => new Date(d + 'T00:00:00').toLocaleDateString('en-US', { month: 'long', day: 'numeric' }).toUpperCase();
const SEP = '+'.repeat(50);
/* Teks ini bisa langsung ditempel di kotak grup pada web bracket */
function toTxt(f, rs) {
  const T = rs.filter(r => r.kind !== 'solo'), S = rs.filter(r => r.kind === 'solo');
  const teams = T.map(r => SEP + '\n' + [
    'Nama Tim : ' + r.team_name, 'Nama Leader : ' + r.leader, 'No. WhatsApp : ' + r.whatsapp, 'ID Game Leader : ' + r.leader_game_id,
    ...[0, 1, 2, 3, 4].map(k => 'Nickname Pemain ' + (k + 1) + ' : ' + (r.players[k] || '')),
    'Cadangan : ' + (r.substitutes || []).join(', ')
  ].join('\n'));
  const solos = S.map(r => SEP + '\n' + ['Nama : ' + r.leader, 'ID Game : ' + r.leader_game_id, 'No. WhatsApp : ' + r.whatsapp].join('\n'));
  let out = f.title + '\n\n' + teams.join('\n\n');
  if (S.length) out += (T.length ? '\n\n' : '') + 'SOLO\n\n' + solos.join('\n\n');
  return out + '\n';
}
function save(name, blob) { const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; a.click(); URL.revokeObjectURL(a.href); }
