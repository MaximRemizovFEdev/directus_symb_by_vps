import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const DB_CONTAINER = process.env.SYMBOLIKA_DB_CONTAINER || 'symbolika-db';
const DB_USER = process.env.SYMBOLIKA_DB_USER || 'directus';
const DB_NAME = process.env.SYMBOLIKA_DB_NAME || 'directus';
const EXPORT_DIR = resolve(process.cwd(), 'exports');

const args = new Set(process.argv.slice(2));
const includeAllPublic = args.has('--all-public');

const excludedTables = new Set([
  'spatial_ref_sys',
  'symbolika_push_subscriptions',
]);

function runPsql(sql) {
  const result = spawnSync(
    'docker',
    ['exec', DB_CONTAINER, 'psql', '-U', DB_USER, '-d', DB_NAME, '-At', '-c', sql],
    {
      encoding: 'utf8',
      maxBuffer: 256 * 1024 * 1024,
    },
  );

  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || 'psql failed').trim());
  }

  return result.stdout.replace(/\r\n/g, '\n');
}

function runCopy(tableName) {
  const sql = `COPY (SELECT * FROM public.${quoteIdent(tableName)}) TO STDOUT WITH CSV HEADER`;
  const result = spawnSync(
    'docker',
    ['exec', DB_CONTAINER, 'psql', '-U', DB_USER, '-d', DB_NAME, '-c', sql],
    {
      encoding: 'utf8',
      maxBuffer: 256 * 1024 * 1024,
    },
  );

  if (result.status !== 0) {
    throw new Error(`Failed to export ${tableName}: ${(result.stderr || result.stdout).trim()}`);
  }

  return result.stdout.replace(/\r\n/g, '\n');
}

function quoteIdent(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let value = '';
  let quoted = false;

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    const next = text[i + 1];

    if (quoted) {
      if (char === '"' && next === '"') {
        value += '"';
        i += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        value += char;
      }
      continue;
    }

    if (char === '"') {
      quoted = true;
    } else if (char === ',') {
      row.push(value);
      value = '';
    } else if (char === '\n') {
      row.push(value);
      rows.push(row);
      row = [];
      value = '';
    } else {
      value += char;
    }
  }

  if (value.length > 0 || row.length > 0) {
    row.push(value);
    rows.push(row);
  }

  return rows.filter((csvRow) => csvRow.length > 1 || csvRow[0] !== '');
}

function xmlEscape(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function sheetName(name, usedNames) {
  const base = String(name)
    .replace(/[\\/?*[\]:]/g, '_')
    .slice(0, 31) || 'sheet';
  let candidate = base;
  let index = 2;

  while (usedNames.has(candidate)) {
    const suffix = `_${index}`;
    candidate = `${base.slice(0, 31 - suffix.length)}${suffix}`;
    index += 1;
  }

  usedNames.add(candidate);
  return candidate;
}

function cellXml(value, isHeader = false) {
  const style = isHeader ? ' ss:StyleID="header"' : '';
  return `<Cell${style}><Data ss:Type="String">${xmlEscape(value)}</Data></Cell>`;
}

function worksheetXml(name, rows, usedNames) {
  const safeName = sheetName(name, usedNames);
  const body = rows
    .map((row, rowIndex) => `<Row>${row.map((cell) => cellXml(cell, rowIndex === 0)).join('')}</Row>`)
    .join('');

  return `<Worksheet ss:Name="${xmlEscape(safeName)}"><Table>${body}</Table></Worksheet>`;
}

function workbookXml(sheets) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<?mso-application progid="Excel.Sheet"?>
<Workbook
  xmlns="urn:schemas-microsoft-com:office:spreadsheet"
  xmlns:o="urn:schemas-microsoft-com:office:office"
  xmlns:x="urn:schemas-microsoft-com:office:excel"
  xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"
  xmlns:html="http://www.w3.org/TR/REC-html40">
  <Styles>
    <Style ss:ID="header">
      <Font ss:Bold="1"/>
      <Interior ss:Color="#F97316" ss:Pattern="Solid"/>
    </Style>
  </Styles>
  ${sheets.join('\n')}
</Workbook>
`;
}

const tableFilter = includeAllPublic
  ? ''
  : "and tablename not like 'directus_%'";

const tables = runPsql(`
  select tablename
  from pg_tables
  where schemaname = 'public'
    ${tableFilter}
  order by tablename;
`)
  .trim()
  .split('\n')
  .map((name) => name.trim())
  .filter(Boolean)
  .filter((name) => includeAllPublic || !excludedTables.has(name));

if (tables.length === 0) {
  throw new Error('No tables found for export.');
}

mkdirSync(EXPORT_DIR, { recursive: true });

const usedNames = new Set();
const sheets = [];

for (const table of tables) {
  const csv = runCopy(table);
  const rows = parseCsv(csv);
  sheets.push(worksheetXml(table, rows, usedNames));
  console.log(`${table}: ${Math.max(rows.length - 1, 0)} rows`);
}

const stamp = new Date().toISOString().replace(/[-:]/g, '').slice(0, 15).replace('T', '-');
const filePath = resolve(EXPORT_DIR, `symbolika-export-${stamp}.xls`);
writeFileSync(filePath, workbookXml(sheets), 'utf8');

console.log(`\nExport saved: ${filePath}`);
