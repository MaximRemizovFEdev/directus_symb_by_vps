import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('../qa/playwright/node_modules/playwright');

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const projectDir = path.resolve(currentDir, '..');
const sourceDir = path.join(projectDir, 'Инструкции');
const outputDir = path.join(sourceDir, 'PDF');

const escapeHtml = (value) => String(value || '')
  .replaceAll('&', '&amp;')
  .replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;');

function inlineMarkdown(value) {
  let text = escapeHtml(value);
  text = text.replace(/`([^`]+)`/g, '<code>$1</code>');
  text = text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  text = text.replace(/\*([^*]+)\*/g, '<em>$1</em>');
  text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_match, label, href) => {
    const decoded = href.replaceAll('&amp;', '&');
    const target = decoded.endsWith('.md') ? decoded.replace(/\.md$/, '.pdf') : decoded;
    return `<a href="${escapeHtml(target)}">${label}</a>`;
  });
  return text;
}

function isTableDivider(line) {
  return /^\s*\|?(?:\s*:?-{3,}:?\s*\|)+\s*:?-{3,}:?\s*\|?\s*$/.test(line);
}

function tableCells(line) {
  return line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((cell) => cell.trim());
}

function markdownToHtml(markdown) {
  const lines = String(markdown || '').replaceAll('\r\n', '\n').split('\n');
  const output = [];
  let paragraph = [];
  let listType = null;
  let inCode = false;
  let codeLanguage = '';
  let codeLines = [];

  const flushParagraph = () => {
    if (!paragraph.length) return;
    output.push(`<p>${inlineMarkdown(paragraph.join(' '))}</p>`);
    paragraph = [];
  };
  const closeList = () => {
    if (!listType) return;
    output.push(`</${listType}>`);
    listType = null;
  };

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const fence = line.match(/^```\s*(.*)$/);
    if (fence) {
      flushParagraph();
      closeList();
      if (!inCode) {
        inCode = true;
        codeLanguage = fence[1].trim();
        codeLines = [];
      } else {
        output.push(`<pre data-language="${escapeHtml(codeLanguage)}"><code>${escapeHtml(codeLines.join('\n'))}</code></pre>`);
        inCode = false;
      }
      continue;
    }
    if (inCode) {
      codeLines.push(line);
      continue;
    }

    if (line.includes('|') && index + 1 < lines.length && isTableDivider(lines[index + 1])) {
      flushParagraph();
      closeList();
      const headers = tableCells(line);
      index += 2;
      const rows = [];
      while (index < lines.length && lines[index].includes('|') && lines[index].trim()) {
        rows.push(tableCells(lines[index]));
        index += 1;
      }
      index -= 1;
      output.push('<table><thead><tr>');
      headers.forEach((cell) => output.push(`<th>${inlineMarkdown(cell)}</th>`));
      output.push('</tr></thead><tbody>');
      rows.forEach((row) => {
        output.push('<tr>');
        headers.forEach((_header, cellIndex) => output.push(`<td>${inlineMarkdown(row[cellIndex] || '')}</td>`));
        output.push('</tr>');
      });
      output.push('</tbody></table>');
      continue;
    }

    const heading = line.match(/^(#{1,6})\s+(.+)$/);
    if (heading) {
      flushParagraph();
      closeList();
      const level = heading[1].length;
      output.push(`<h${level}>${inlineMarkdown(heading[2])}</h${level}>`);
      continue;
    }

    if (/^\s*---+\s*$/.test(line)) {
      flushParagraph();
      closeList();
      output.push('<hr>');
      continue;
    }

    const quote = line.match(/^>\s?(.*)$/);
    if (quote) {
      flushParagraph();
      closeList();
      output.push(`<blockquote>${inlineMarkdown(quote[1])}</blockquote>`);
      continue;
    }

    const unordered = line.match(/^\s*[-*]\s+(.+)$/);
    const ordered = line.match(/^\s*\d+[.)]\s+(.+)$/);
    if (unordered || ordered) {
      flushParagraph();
      const nextType = ordered ? 'ol' : 'ul';
      if (listType !== nextType) {
        closeList();
        listType = nextType;
        output.push(`<${listType}>`);
      }
      output.push(`<li>${inlineMarkdown((ordered || unordered)[1])}</li>`);
      continue;
    }

    if (!line.trim()) {
      flushParagraph();
      closeList();
      continue;
    }
    paragraph.push(line.trim());
  }

  if (inCode) output.push(`<pre><code>${escapeHtml(codeLines.join('\n'))}</code></pre>`);
  flushParagraph();
  closeList();
  return output.join('\n');
}

const styles = `
  @page { size: A4; margin: 18mm 16mm 18mm; }
  * { box-sizing: border-box; }
  body { margin: 0; color: #1d232d; font-family: Inter, "Segoe UI", Arial, sans-serif; font-size: 10.5pt; line-height: 1.52; }
  .document { max-width: 100%; }
  .document + .document { break-before: page; }
  h1 { margin: 0 0 18px; color: #17202c; font-size: 25pt; line-height: 1.12; border-bottom: 3px solid #ff7a2f; padding-bottom: 10px; }
  h2 { margin: 24px 0 9px; color: #273343; font-size: 16pt; line-height: 1.2; break-after: avoid; }
  h3 { margin: 18px 0 7px; color: #344154; font-size: 12.5pt; break-after: avoid; }
  h4, h5, h6 { margin: 14px 0 6px; color: #3d495a; break-after: avoid; }
  p { margin: 0 0 9px; }
  ul, ol { margin: 5px 0 11px; padding-left: 24px; }
  li { margin: 3px 0; }
  a { color: #c94f0c; text-decoration: none; }
  strong { color: #111820; }
  code { font-family: Consolas, "Cascadia Mono", monospace; background: #f1f3f5; border-radius: 4px; padding: 1px 4px; font-size: 9.2pt; }
  pre { margin: 10px 0 14px; padding: 11px 13px; color: #f5f7fa; background: #17202a; border-left: 4px solid #ff7a2f; border-radius: 7px; white-space: pre-wrap; overflow-wrap: anywhere; break-inside: avoid; }
  pre code { padding: 0; color: inherit; background: transparent; }
  blockquote { margin: 10px 0 14px; padding: 9px 13px; color: #5a3a28; background: #fff3eb; border-left: 4px solid #ff7a2f; border-radius: 0 6px 6px 0; }
  table { width: 100%; margin: 10px 0 16px; border-collapse: collapse; font-size: 9.4pt; break-inside: auto; }
  thead { display: table-header-group; }
  tr { break-inside: avoid; }
  th { color: #fff; background: #313b49; text-align: left; }
  th, td { padding: 7px 8px; border: 1px solid #cfd5dc; vertical-align: top; overflow-wrap: anywhere; }
  tbody tr:nth-child(even) { background: #f6f7f9; }
  hr { margin: 18px 0; border: 0; border-top: 1px solid #d8dde3; }
`;

function pageHtml(title, content) {
  return `<!doctype html><html lang="ru"><head><meta charset="utf-8"><title>${escapeHtml(title)}</title><style>${styles}</style></head><body>${content}</body></html>`;
}

async function printPdf(page, html, outputPath) {
  await page.setContent(html, { waitUntil: 'load' });
  await page.emulateMedia({ media: 'print' });
  await page.pdf({
    path: outputPath,
    format: 'A4',
    printBackground: true,
    preferCSSPageSize: true,
    displayHeaderFooter: true,
    headerTemplate: '<div></div>',
    footerTemplate: '<div style="width:100%;font:8px Segoe UI,Arial;color:#7b8490;text-align:center"><span class="pageNumber"></span> / <span class="totalPages"></span></div>',
    margin: { top: '18mm', right: '16mm', bottom: '18mm', left: '16mm' },
  });
}

await fs.mkdir(outputDir, { recursive: true });
const names = (await fs.readdir(sourceDir))
  .filter((name) => name.toLowerCase().endsWith('.md'))
  .sort((left, right) => left.localeCompare(right, 'ru'));

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
const combined = [];

try {
  for (const name of names) {
    const markdown = await fs.readFile(path.join(sourceDir, name), 'utf8');
    const title = name === 'README.md' ? 'Все инструкции системы «Символика»' : path.basename(name, '.md');
    const content = `<article class="document">${markdownToHtml(markdown)}</article>`;
    const pdfName = name === 'README.md' ? 'Оглавление.pdf' : `${path.basename(name, '.md')}.pdf`;
    await printPdf(page, pageHtml(title, content), path.join(outputDir, pdfName));
    combined.push(content);
    process.stdout.write(`Создан: ${pdfName}\n`);
  }
  await printPdf(
    page,
    pageHtml('Все инструкции системы «Символика»', combined.join('\n')),
    path.join(outputDir, 'Все инструкции системы Символика.pdf'),
  );
  process.stdout.write('Создан: Все инструкции системы Символика.pdf\n');
} finally {
  await browser.close();
}
