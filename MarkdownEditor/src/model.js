/*
 * Created by ktiays on 2026/10/23.
 * Copyright (c) 2026 ktiays. All rights reserved.
 *
 * Line-based Markdown document model. The Markdown source is authoritative: every edit is a
 * source replacement, and each line is re-rendered with a map from visible characters back to
 * source offsets, so editing never reformats text the user did not touch.
 */
(function (root) {
  'use strict';

  const escapeHTML = (value) => String(value).replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[character]));
  const normalize = (value) => String(value).replace(/\r\n?/g, '\n');
  const safeLink = (value) => (/^(https?:|mailto:|#)/i.test(value.trim()) ? value.trim() : '');

  const emphasisMarkers = [
    ['***', 'strong><em', 'boldItalic'],
    ['**', 'strong', 'bold'],
    ['__', 'strong', 'bold'],
    ['~~', 'del', 'strikethrough'],
    ['*', 'em', 'italic'],
    ['_', 'em', 'italic'],
  ];

  /**
   * Renders inline Markdown. `starts[i]`/`ends[i]` give the source range of visible character
   * `i`; `spans` record formatted ranges with their delimiters for boundary-aware editing.
   */
  function inline(source, base = 0, depth = 0) {
    const out = { html: '', text: '', starts: [], ends: [], spans: [] };

    function literal(value, start) {
      out.html += escapeHTML(value);
      for (let index = 0; index < value.length; index++) {
        out.text += value[index];
        out.starts.push(base + start + index);
        out.ends.push(base + start + index + 1);
      }
    }

    function child(value, start, open, close, fullStart, fullEnd, format, url) {
      const part = inline(value, base + start, depth + 1);
      const offset = out.text.length;
      out.html += open + part.html + close;
      out.text += part.text;
      out.starts.push(...part.starts);
      out.ends.push(...part.ends);
      out.spans.push(...part.spans.map((span) => ({ ...span, from: span.from + offset, to: span.to + offset })));
      out.spans.push({
        from: offset,
        to: out.text.length,
        start: base + fullStart,
        end: base + fullEnd,
        contentStart: base + start,
        contentEnd: base + start + value.length,
        format,
        url,
      });
    }

    for (let index = 0; index < source.length;) {
      const rest = source.slice(index);
      let match;
      if (source[index] === '\\' && index + 1 < source.length && /[\\`*_{}\[\]()#+.!>~|\-]/.test(source[index + 1])) {
        literal(source[index + 1], index + 1);
        index += 2;
        continue;
      }
      if ((match = /^(`+)([\s\S]*?)\1(?!`)/.exec(rest))) {
        const start = out.text.length;
        const text = match[2];
        const contentStart = index + match[1].length;
        out.html += '<code>' + escapeHTML(text) + '</code>';
        for (let offset = 0; offset < text.length; offset++) {
          out.text += text[offset];
          out.starts.push(base + contentStart + offset);
          out.ends.push(base + contentStart + offset + 1);
        }
        out.spans.push({
          from: start,
          to: out.text.length,
          start: base + index,
          end: base + index + match[0].length,
          contentStart: base + contentStart,
          contentEnd: base + contentStart + text.length,
          format: 'code',
        });
        index += match[0].length;
        continue;
      }
      // Images stay as editable source text; nothing is ever loaded from the network.
      if ((match = /^!\[([^\]]*)\]\(([^)]+)\)/.exec(rest))) {
        out.html += '<span class="md-image-source">';
        literal(match[0], index);
        out.html += '</span>';
        index += match[0].length;
        continue;
      }
      if (depth < 16 && (match = /^\[([^\]]+)\]\(([^)]+)\)/.exec(rest))) {
        child(match[1], index + 1, '<a href="' + escapeHTML(safeLink(match[2])) + '">', '</a>', index, index + match[0].length, 'link', match[2]);
        index += match[0].length;
        continue;
      }
      let matched = false;
      if (depth < 16) {
        for (const [marker, tag, format] of emphasisMarkers) {
          if (!source.startsWith(marker, index) || /\s/.test(source[index + marker.length] || ' ')) continue;
          if (marker.includes('_') && /[\p{L}\p{N}]/u.test(source[index - 1] || '')) continue;
          const end = source.indexOf(marker, index + marker.length);
          if (end <= index + marker.length || /\s/.test(source[end - 1])) continue;
          const open = '<' + tag + '>';
          const close = tag === 'strong><em' ? '</em></strong>' : '</' + tag + '>';
          child(source.slice(index + marker.length, end), index + marker.length, open, close, index, end + marker.length, format);
          index = end + marker.length;
          matched = true;
          break;
        }
      }
      if (!matched) {
        literal(source[index], index);
        index++;
      }
    }
    return out;
  }

  function plainContent(body, prefixLength) {
    return {
      html: escapeHTML(body),
      text: body,
      starts: Array.from({ length: body.length }, (_, index) => prefixLength + index),
      ends: Array.from({ length: body.length }, (_, index) => prefixLength + index + 1),
      spans: [],
    };
  }

  const isTableSeparator = (line) => line.includes('|')
    && line.trim().replace(/^\||\|$/g, '').split('|').every((cell) => /^\s*:?-{3,}:?\s*$/.test(cell));

  const tableAlignment = (separator) => separator.trim().replace(/^\||\|$/g, '').split('|')
    .map((cell) => (/^\s*:.*:\s*$/.test(cell) ? 'center' : /:\s*$/.test(cell) ? 'right' : 'left'));

  function tableRowContent(source, alignment) {
    const content = { html: '', text: '', starts: [], ends: [], spans: [] };
    const pieces = source.split(/(?<!\\)\|/);
    let position = 0;
    let column = 0;
    pieces.forEach((cell, index) => {
      if (index) {
        content.html += '<span class="md-table-pipe" aria-hidden="true">|</span>';
        content.text += '|';
        content.starts.push(position - 1);
        content.ends.push(position);
      }
      const part = inline(cell, position);
      const offset = content.text.length;
      const isOuterPadding = (index === 0 || index === pieces.length - 1) && !cell.trim();
      if (isOuterPadding) {
        content.html += '<span class="md-table-pad">' + escapeHTML(cell) + '</span>';
      } else {
        content.html += '<span class="md-table-cell" data-col="' + column + '" data-align="' + (alignment[column] || 'left') + '">'
          + (part.html || '<br>') + '</span>';
        column++;
      }
      content.text += part.text;
      content.starts.push(...part.starts);
      content.ends.push(...part.ends);
      content.spans.push(...part.spans.map((span) => ({ ...span, from: span.from + offset, to: span.to + offset })));
      position += cell.length + 1;
    });
    return content;
  }

  function parse(markdown) {
    const raw = normalize(markdown).split('\n');
    const lines = [];
    let fence = null;
    let tableEnd = -1;
    let alignment = [];

    for (let index = 0; index < raw.length; index++) {
      const source = raw[index];
      let prefix = '';
      let cls = 'md-paragraph';
      let attributes = '';
      let before = '';
      let body = source;
      let isPlain = false;
      let groupStart = false;
      let groupEnd = false;
      let match;

      if (fence) {
        if (new RegExp('^ {0,3}' + fence.character + '{' + fence.length + ',}\\s*$').test(source)) {
          cls = 'md-code-fence md-code-fence-end';
          attributes = ' contenteditable="false"';
          fence = null;
        } else {
          cls = 'md-code';
          attributes = ' spellcheck="false"';
        }
        isPlain = true;
      } else if ((match = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(source))) {
        fence = { character: match[1][0], length: match[1].length };
        cls = 'md-code-fence';
        attributes = ' contenteditable="false"';
        before = '<span class="md-code-language">' + escapeHTML(match[2].trim()) + '</span>';
        body = '';
        isPlain = true;
      } else if (index < tableEnd || (index + 1 < raw.length && source.includes('|') && isTableSeparator(raw[index + 1]))) {
        if (index >= tableEnd) {
          groupStart = true;
          tableEnd = index + 2;
          while (tableEnd < raw.length && raw[tableEnd].includes('|') && raw[tableEnd].trim()) tableEnd++;
          alignment = tableAlignment(raw[index + 1]);
        }
        groupEnd = index === tableEnd - 1;
        cls = isTableSeparator(source) ? 'md-table-separator' : groupStart ? 'md-table-header' : 'md-table-row';
        if (cls === 'md-table-separator') {
          attributes = ' contenteditable="false" hidden';
          isPlain = true;
        }
      } else if ((match = /^( {0,3}#{1,6})\s+/.exec(source))) {
        const level = match[1].trim().length;
        prefix = match[0];
        body = source.slice(prefix.length);
        cls = 'md-heading md-h' + level;
        attributes = ' role="heading" aria-level="' + level + '"';
      } else if ((match = /^(\s*(?:>\s?)+)/.exec(source))) {
        const depth = Math.min((match[0].match(/>/g) || []).length, 5);
        prefix = match[0];
        body = source.slice(prefix.length);
        cls = 'md-blockquote';
        attributes = ' data-depth="' + depth + '"';
        before = Array.from({ length: depth }, (_, position) => '<span class="md-quote-bar" data-position="' + position + '" contenteditable="false"></span>').join('');
      } else if ((match = /^(\s*)([-+*]|\d+[.)])\s+(?:\[([ xX])\]\s+)?/.exec(source))) {
        const depth = Math.min(7, Math.floor(match[1].replace(/\t/g, '    ').length / 2));
        prefix = match[0];
        body = source.slice(prefix.length);
        attributes = ' data-depth="' + depth + '"';
        if (match[3] !== undefined) {
          const checked = Boolean(match[3].trim());
          cls = 'md-task';
          before = '<span class="md-checkbox' + (checked ? ' md-checked' : '') + '" contenteditable="false" role="checkbox" aria-checked="' + checked + '"></span>';
        } else if (/\d/.test(match[2][0])) {
          cls = 'md-list-item md-ordered';
          before = '<span class="md-marker" contenteditable="false" aria-hidden="true">' + parseInt(match[2], 10) + '.</span>';
        } else {
          cls = 'md-list-item';
          before = '<span class="md-marker md-bullet" contenteditable="false" aria-hidden="true"></span>';
        }
      } else if (/^\s{0,3}([-*_])(?:\s*\1){2,}\s*$/.test(source)) {
        cls = 'md-rule';
        attributes = ' contenteditable="false" role="separator"';
        isPlain = true;
      } else if (!source) {
        cls = 'md-blank';
      }

      let content = isPlain ? plainContent(body, prefix.length) : inline(body, prefix.length);
      if (cls === 'md-table-header' || cls === 'md-table-row') content = tableRowContent(source, alignment);
      const after = !content.text && !cls.includes('fence') ? '<span class="md-caret-anchor">\u200b</span><br>' : '';
      const html = '<div data-line="' + index + '" class="' + cls + '"' + attributes + '>' + before + content.html + after + '</div>';
      lines.push({ source, prefix, cls, ...content, html, groupStart, groupEnd, columnCount: alignment.length });
    }

    let html = '';
    for (const line of lines) {
      if (line.groupStart) {
        html += '<div class="md-table" style="grid-template-columns:repeat(' + line.columnCount + ',minmax(4em,auto))">';
      }
      html += line.html;
      if (line.groupEnd) html += '</div>';
    }
    return { lines, html };
  }

  const maximumUndoDepth = 200;

  class Model {
    constructor(markdown = '') {
      this.setMarkdown(markdown);
    }

    setMarkdown(markdown) {
      this.markdown = normalize(markdown);
      this.document = parse(this.markdown);
      this.undoStack = [];
      this.redoStack = [];
      this.moveCursor(this.markdown.length);
    }

    lineStart(line) {
      return this.document.lines.slice(0, line).reduce((total, current) => total + current.source.length + 1, 0);
    }

    /**
     * Converts a visible offset to a source offset. At a formatting boundary `inside` decides
     * whether the position sits within the delimiters or outside them.
     */
    rawOffset(line, offset, inside = false) {
      const current = this.document.lines[Math.max(0, Math.min(line, this.document.lines.length - 1))];
      const clamped = Math.max(0, Math.min(offset, current.text.length));
      let position = clamped < current.starts.length ? current.starts[clamped] : current.ends.at(-1) ?? current.prefix.length;
      for (const span of current.spans) {
        if (!inside && clamped === span.from) position = Math.min(position, span.start);
        if (!inside && clamped === span.to) position = Math.max(position, span.end);
        if (inside && clamped === span.to) position = current.ends[clamped - 1] ?? position;
      }
      return position;
    }

    absolute(line, offset, inside = false) {
      return this.lineStart(line) + this.rawOffset(line, offset, inside);
    }

    rawPoint(absolute) {
      let line = 0;
      let remaining = absolute;
      while (line < this.document.lines.length - 1 && remaining > this.document.lines[line].source.length) {
        remaining -= this.document.lines[line].source.length + 1;
        line++;
      }
      const current = this.document.lines[line];
      let offset = 0;
      while (offset < current.ends.length && current.ends[offset] <= remaining) offset++;
      return { line, offset, inside: this.isInsideFormatting(current, offset, remaining) };
    }

    /** Whether a source position at a span boundary lies between that span's delimiters. */
    isInsideFormatting(line, offset, sourceOffset) {
      let inside = null;
      for (const span of line.spans) {
        if (span.to === offset) inside = sourceOffset < span.end;
        else if (span.from === offset && inside === null) inside = sourceOffset >= span.contentStart;
      }
      return inside;
    }

    moveCursor(absolute) {
      this.cursor = this.rawPoint(absolute);
    }

    selection(intent) {
      if (intent.selStartLine === undefined) {
        const position = this.absolute(intent.line ?? 0, intent.offset ?? 0, intent.insideFormatting);
        return [position, position];
      }
      const first = this.absolute(intent.selStartLine, intent.selStartOffset, true);
      const second = this.absolute(intent.selEndLine, intent.selEndOffset, true);
      let start = Math.min(first, second);
      let end = Math.max(first, second);
      // A selection covering a whole formatted span takes its delimiters along.
      let base = 0;
      for (const line of this.document.lines) {
        for (const span of line.spans) {
          if (span.from < span.to && start <= base + line.starts[span.from] && end >= base + line.ends[span.to - 1]) {
            start = Math.min(start, base + span.start);
            end = Math.max(end, base + span.end);
          }
        }
        base += line.source.length + 1;
      }
      return [start, end];
    }

    selectedMarkdown(intent) {
      const [start, end] = this.selection(intent);
      return this.markdown.slice(start, end);
    }

    reply() {
      return { html: this.document.html, cursor: { ...this.cursor } };
    }

    snapshot() {
      return { markdown: this.markdown, cursor: { ...this.cursor } };
    }

    restore(snapshot) {
      this.markdown = snapshot.markdown;
      this.document = parse(this.markdown);
      this.cursor = { ...snapshot.cursor };
    }

    replace(start, end, text) {
      const markdown = this.markdown.slice(0, start) + text + this.markdown.slice(end);
      if (markdown !== this.markdown) {
        this.undoStack.push(this.snapshot());
        if (this.undoStack.length > maximumUndoDepth) this.undoStack.shift();
        this.redoStack = [];
      }
      this.markdown = markdown;
      this.document = parse(markdown);
      this.moveCursor(start + text.length);
      return this.reply();
    }

    selectRange(from, to) {
      const start = this.rawPoint(from);
      const end = this.rawPoint(to);
      this.cursor = { ...end };
      return { ...this.reply(), selection: { startLine: start.line, startOffset: start.offset, endLine: end.line, endOffset: end.offset } };
    }

    toggleInline(format, selection) {
      const markers = { bold: '**', italic: '*', strikethrough: '~~', code: '`' };
      if (!markers[format]) throw new TypeError('Unknown inline format');
      const { startLine: line, startOffset: offset, endLine, endOffset } = selection;
      if (line !== endLine) return this.reply();
      const current = this.document.lines[line];
      const base = this.lineStart(line);
      const existing = current.spans.find((span) => span.format === format && span.from <= offset && span.to >= endOffset);
      if (existing) {
        const text = current.source.slice(existing.contentStart, existing.contentEnd);
        this.replace(base + existing.start, base + existing.end, text);
        return this.selectRange(base + existing.start, base + existing.start + text.length);
      }
      let [start, end] = this.selection({ selStartLine: line, selStartOffset: offset, selEndLine: endLine, selEndOffset: endOffset });
      let text = this.markdown.slice(start, end);
      if (start === end) {
        const left = current.text.slice(0, offset).match(/[\p{L}\p{N}_]+$/u)?.[0].length || 0;
        const right = current.text.slice(offset).match(/^[\p{L}\p{N}_]+/u)?.[0].length || 0;
        start = this.absolute(line, offset - left, true);
        end = this.absolute(line, offset + right, true);
        text = this.markdown.slice(start, end) || 'text';
      }
      let marker = markers[format];
      if (format === 'code') {
        const longest = Math.max(0, ...(text.match(/`+/g) || []).map((run) => run.length));
        marker = '`'.repeat(longest + 1);
      }
      this.replace(start, end, marker + text + marker);
      return this.selectRange(start + marker.length, start + marker.length + text.length);
    }

    handle(intent) {
      const action = intent.action;
      if (action === 'undo' || action === 'redo') {
        const from = action === 'undo' ? this.undoStack : this.redoStack;
        const to = action === 'undo' ? this.redoStack : this.undoStack;
        if (from.length) {
          to.push(this.snapshot());
          this.restore(from.pop());
        }
        return this.reply();
      }

      const lineIndex = Math.max(0, Math.min(intent.line ?? 0, this.document.lines.length - 1));
      const line = this.document.lines[lineIndex];
      let [start, end] = this.selection({ ...intent, line: lineIndex });
      const text = normalize(intent.text ?? '');

      if (action === 'checkbox') {
        const match = /\[[ xX]\]/.exec(line.prefix);
        const base = this.lineStart(lineIndex);
        return match ? this.replace(base + match.index + 1, base + match.index + 2, intent.checked ? 'x' : ' ') : this.reply();
      }
      if (action === 'type' || action === 'paste') return this.replace(start, end, text);
      if (action === 'enter') {
        if (!line.text.trim() && line.prefix) return this.replace(start - this.rawOffset(lineIndex, intent.offset ?? 0), end, '');
        let prefix = intent.shift || line.cls === 'md-code' ? '' : line.prefix;
        prefix = prefix.replace(/(\d+)([.)])/, (_, number, suffix) => String(Number(number) + 1) + suffix).replace(/\[[xX]\]/, '[ ]');
        return this.replace(start, end, '\n' + prefix);
      }
      if (action === 'backspace' || action === 'delete') {
        if (start !== end) return this.replace(start, end, '');
        const offset = intent.offset ?? 0;
        if (action === 'backspace' && offset === 0 && line.prefix) return this.replace(start - line.prefix.length, start, '');
        if (!intent.meta && !intent.alt) {
          if (action === 'backspace' && offset > 0) {
            const step = /[\uDC00-\uDFFF]/.test(line.text[offset - 1]) ? 2 : 1;
            const range = this.selection({ selStartLine: lineIndex, selStartOffset: Math.max(0, offset - step), selEndLine: lineIndex, selEndOffset: offset });
            return this.replace(...range, '');
          }
          if (action === 'delete' && offset < line.text.length) {
            const step = /[\uD800-\uDBFF]/.test(line.text[offset]) ? 2 : 1;
            const range = this.selection({ selStartLine: lineIndex, selStartOffset: offset, selEndLine: lineIndex, selEndOffset: Math.min(line.text.length, offset + step) });
            return this.replace(...range, '');
          }
        }
        if (action === 'backspace') {
          if (intent.meta) start -= this.rawOffset(lineIndex, offset);
          else if (intent.alt) start -= (this.markdown.slice(0, start).match(/\s*\S+\s*$/) || [''])[0].length;
          else {
            start = Math.max(0, start - 1);
            if (start > 0 && /[\uDC00-\uDFFF]/.test(this.markdown[start])) start--;
          }
        } else if (intent.meta) {
          end += line.source.length - this.rawOffset(lineIndex, offset);
        } else if (intent.alt) {
          end += (this.markdown.slice(end).match(/^\s*\S+\s*/) || [''])[0].length;
        } else {
          end = Math.min(this.markdown.length, end + 1);
          if (/[\uD800-\uDBFF]/.test(this.markdown[end - 1] || '')) end++;
        }
        return this.replace(start, end, '');
      }
      if (action === 'tab') {
        if (line.cls.includes('list') || line.cls === 'md-task') {
          const base = this.lineStart(lineIndex);
          if (!intent.shift) return this.replace(base, base, '  ');
          const indent = line.source.startsWith('  ') ? 2 : line.source.startsWith('\t') ? 1 : 0;
          return this.replace(base, base + indent, '');
        }
        return intent.shift ? this.reply() : this.replace(start, end, '  ');
      }
      return this.reply();
    }
  }

  const api = { Model, parse, inline, escapeHTML };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.MarkdownModel = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
