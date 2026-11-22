'use strict';

// MySQL / MariaDB connection (mysql2 connection pool). Creates the tables on first start and loads the initial menu.
// Every helper returns a Promise, so use them with await.
//
// Settings (environment variables, see .env.example):
//   DB_HOST  DB_PORT  DB_USER  DB_PASSWORD  DB_NAME
//   DB_SSL=true|false          TLS to the database. Default: ON in production (NODE_ENV=production), OFF otherwise.
//   DB_SSL_CA=<PEM text or path>   optional CA certificate of the provider (needed by some hosts)
//   DB_SSL_REJECT_UNAUTHORIZED=false   last resort if the provider's certificate chain cannot be verified
//   DB_AUTO_SCHEMA=false       skip the CREATE TABLE IF NOT EXISTS step (when you imported schema.sql yourself and the app user has no CREATE right)
const mysql = require('mysql2/promise'), fs = require('fs'), path = require('path');
const { AsyncLocalStorage } = require('async_hooks');

const PROD = process.env.NODE_ENV === 'production';
const wantSsl = process.env.DB_SSL ? /^(1|true|yes|on)$/i.test(process.env.DB_SSL) : PROD;

let ssl;
if (wantSsl) {
    ssl = { minVersion: 'TLSv1.2', rejectUnauthorized: !/^(0|false|no|off)$/i.test(process.env.DB_SSL_REJECT_UNAUTHORIZED || '') };
    const ca = process.env.DB_SSL_CA;
    if (ca)
        ssl.ca = ca.includes('BEGIN CERTIFICATE') ? ca.replace(/\\n/g, '\n') : fs.readFileSync(ca, 'utf8');
}

const pool = mysql.createPool({
    host: process.env.DB_HOST || '127.0.0.1',
    port: Number(process.env.DB_PORT) || 3306,
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'cafeteria_preorder',
    ssl,
    connectionLimit: 5, // small managed plans allow only a few connections in total
    waitForConnections: true,
    queueLimit: 0,
    charset: 'utf8mb4',
    decimalNumbers: true, // DECIMAL columns (price, total) come back as numbers, as the browser code expects
    dateStrings: true, // DATETIME comes back as 'YYYY-MM-DD HH:MM:SS' text (UTC, see below)
    enableKeepAlive: true,
    connectTimeout: 15000
});

pool.pool.on('connection', c => c.query("SET time_zone='+00:00'")); // CURRENT_TIMESTAMP is always UTC

// A transaction keeps its own connection; every query made inside it (even in nested helper functions) uses that connection.
const tx = new AsyncLocalStorage();
const conn = () => tx.getStore() || pool;
const clean = a => a.map(v => v === undefined ? null : v);

const one = async (sql, ...a) => (await conn().execute(sql, clean(a)))[0][0];
const all = async (sql, ...a) => (await conn().execute(sql, clean(a)))[0];
const run = async (sql, ...a) => {
    const r = (await conn().execute(sql, clean(a)))[0];
    return { lastInsertRowid: r.insertId, changes: r.affectedRows };
};

// All-or-nothing transaction wrapper; nested calls join the outer transaction.
// When two transactions lock the same rows in opposite order, MySQL cancels one of them (ER_LOCK_DEADLOCK).
// That is normal, so the whole transaction is simply tried again (up to 4 times).
const transaction = fn => async (...a) => {
    if (tx.getStore())
        return fn(...a);
    for (let attempt = 1; ; attempt++) {
        const c = await pool.getConnection();
        try {
            await c.beginTransaction();
            const r = await tx.run(c, () => fn(...a));
            await c.commit();
            return r;
        }
        catch (e) {
            try {
                await c.rollback();
            }
            catch { }
            if (e.code !== 'ER_LOCK_DEADLOCK' || attempt >= 4)
                throw e;
            await new Promise(r => setTimeout(r, 20 * attempt + Math.random() * 40));
        }
        finally {
            c.release();
        }
    }
};

// Run a .sql file made of several statements (statements are split on ";" at the end of a line; no ";" inside text values).
const runFile = async f => {
    const sql = fs.readFileSync(path.join(__dirname, f), 'utf8').replace(/^\s*--.*$/gm, '');
    for (const st of sql.split(/;\s*(?:\r?\n|$)/).map(s => s.trim()).filter(Boolean))
        await pool.query(st);
};

// Called once before the server starts listening: schema, first menu, extra dishes.
async function init() {
    if (!/^(0|false|no|off)$/i.test(process.env.DB_AUTO_SCHEMA || ''))
        await runFile('schema.sql');
    if (!await one('SELECT 1 FROM menu_items LIMIT 1'))
        await runFile('seed.sql');

    // 25 extra dishes (balanced across the 4 categories). Added only when a dish with the same name is missing, so it never duplicates.
    const add = JSON.parse(fs.readFileSync(path.join(__dirname, 'menu-add.json'), 'utf8'));
    for (const m of add) {
        if (!await one('SELECT 1 FROM menu_items WHERE name=?', m.name))
            await run('INSERT INTO menu_items(name,category,price,stock,prep_minutes,description,ingredients,allergens,rating,image) VALUES(?,?,?,?,?,?,?,?,?,?)', m.name, m.category, m.price, m.stock, m.prep_minutes, m.description, m.ingredients, m.allergens, m.rating, m.image);
    }
}

module.exports = { pool, one, all, run, transaction, init };
