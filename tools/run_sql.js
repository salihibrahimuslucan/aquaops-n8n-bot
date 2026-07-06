// Kullanim: node tools/run_sql.js <baglanti-stringi> <sql-dosyasi>
// pg modulu n8n kurulumuyla gelir (hoisted); yoksa n8n/node_modules altindan dener.
const fs = require('fs');
const path = require('path');
let pg;
try { pg = require('pg'); }
catch { pg = require(path.join(__dirname, '..', 'node_modules', 'n8n', 'node_modules', 'pg')); }

const [conn, sqlFile] = process.argv.slice(2);
if (!conn || !sqlFile) { console.error('kullanim: node run_sql.js <conn> <dosya.sql>'); process.exit(1); }
const sql = fs.readFileSync(sqlFile, 'utf8');

(async () => {
  const client = new pg.Client({ connectionString: conn, ssl: { rejectUnauthorized: false } });
  await client.connect();
  try {
    const res = await client.query(sql);
    const results = Array.isArray(res) ? res : [res];
    for (const r of results) {
      if (r.command) console.log(`OK: ${r.command} (${r.rowCount ?? 0} satir)`);
      if (r.rows && r.rows.length) console.log(JSON.stringify(r.rows, null, 1));
    }
  } finally { await client.end(); }
})().catch(e => { console.error('HATA:', e.message); process.exit(2); });
