/*
 * Created by ktiays on 2026/10/23.
 * Copyright (c) 2026 ktiays. All rights reserved.
 *
 * Rendered Markdown editing surface. The browser never edits the DOM directly: input events are
 * turned into model intents, the model returns freshly rendered HTML, and the caret is restored
 * from visible line offsets.
 */
(function () {
  'use strict';

  const container = document.getElementById('editor');
  const model = new MarkdownModel.Model('');
  const nonText = '[contenteditable="false"], .md-caret-anchor';
  const formatting = 'strong, em, del, code, a';

  let isEditable = true;
  let isComposing = false;
  let compositionSelection = null;
  let pendingMarkdown = null;
  // Caret placed after the last render, with its formatting side. DOM positions at a span
  // boundary are ambiguous, so this decides on which side the next typed character lands.
  let renderedCaret = null;

  function post(message) {
    window.webkit?.messageHandlers?.markdownEditor?.postMessage(message);
  }

  // MARK: - DOM ↔ model positions

  const lineDivs = () => Array.from(container.querySelectorAll('[data-line]'));
  const lineDiv = (index) => container.querySelector('[data-line="' + index + '"]');

  function lineDivContaining(node) {
    const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
    const line = element?.closest('[data-line]');
    return line && container.contains(line) ? line : null;
  }

  function textNodes(line) {
    const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => (node.parentElement.closest(nonText) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    return nodes;
  }

  const textLength = (line) => textNodes(line).reduce((total, node) => total + node.length, 0);

  function offsetInLine(line, node, offset) {
    const range = document.createRange();
    range.setStart(line, 0);
    range.setEnd(node, offset);
    let count = 0;
    for (const text of textNodes(line)) {
      if (text === node) return count + offset;
      if (range.comparePoint(text, text.length) !== 0) break;
      count += text.length;
    }
    return count;
  }

  /** Maps a DOM point to `{line, offset, inside}`, snapping points between lines to a line. */
  function modelPoint(node, offset) {
    const line = lineDivContaining(node);
    if (line) {
      const element = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
      const formatted = element.closest(formatting);
      return {
        line: Number(line.dataset.line),
        offset: offsetInLine(line, node, offset),
        inside: Boolean(formatted && line.contains(formatted)),
      };
    }
    const point = document.createRange();
    point.setStart(node, offset);
    const lines = lineDivs();
    const next = lines.find((candidate) => point.comparePoint(candidate, 0) >= 0);
    if (next) return { line: Number(next.dataset.line), offset: 0, inside: false };
    const last = lines.at(-1);
    return { line: Number(last.dataset.line), offset: textLength(last), inside: false };
  }

  function rangeSelection(startNode, startOffset, endNode, endOffset) {
    const start = modelPoint(startNode, startOffset);
    const end = modelPoint(endNode, endOffset);
    const collapsed = start.line === end.line && start.offset === end.offset;
    let inside = start.inside;
    if (collapsed && renderedCaret && renderedCaret.line === start.line && renderedCaret.offset === start.offset && renderedCaret.inside !== null) {
      inside = renderedCaret.inside;
    }
    return {
      startLine: start.line,
      startOffset: start.offset,
      endLine: end.line,
      endOffset: end.offset,
      collapsed,
      inside,
    };
  }

  function currentSelection() {
    const selection = window.getSelection();
    if (!selection.rangeCount || !container.contains(selection.anchorNode)) return null;
    const range = selection.getRangeAt(0);
    return rangeSelection(range.startContainer, range.startOffset, range.endContainer, range.endOffset);
  }

  /** Chooses the DOM position for a visible offset, honoring the requested formatting side. */
  function domPoint(line, offset, inside = null) {
    const nodes = textNodes(line);
    let remaining = Math.max(0, offset);
    for (let index = 0; index < nodes.length; index++) {
      const node = nodes[index];
      if (remaining < node.length) return { node, offset: remaining };
      if (remaining === node.length) {
        if (inside === false) {
          const next = nodes[index + 1];
          if (next) return { node: next, offset: 0 };
          const outer = outermostFormatting(node, line);
          if (outer) return { node: outer.parentNode, offset: Array.prototype.indexOf.call(outer.parentNode.childNodes, outer) + 1 };
        }
        return { node, offset: remaining };
      }
      remaining -= node.length;
    }
    if (nodes.length) {
      const last = nodes.at(-1);
      return { node: last, offset: last.length };
    }
    const anchor = line.querySelector('.md-caret-anchor')?.firstChild;
    return anchor ? { node: anchor, offset: 0 } : { node: line, offset: line.childNodes.length };
  }

  function outermostFormatting(node, line) {
    let outer = null;
    for (let element = node.parentElement; element && element !== line; element = element.parentElement) {
      if (element.matches(formatting)) outer = element;
    }
    return outer;
  }

  function placeCaret(lineIndex, offset, inside = null) {
    const line = lineDiv(lineIndex) || lineDivs().at(-1);
    if (!line) return;
    const point = domPoint(line, offset, inside);
    window.getSelection().setBaseAndExtent(point.node, point.offset, point.node, point.offset);
    renderedCaret = { line: Number(line.dataset.line), offset, inside };
    line.scrollIntoView({ block: 'nearest' });
  }

  function selectRange(selection) {
    const startLine = lineDiv(selection.startLine);
    const endLine = lineDiv(selection.endLine);
    if (!startLine || !endLine) return;
    const start = domPoint(startLine, selection.startOffset, true);
    const end = domPoint(endLine, selection.endOffset, true);
    window.getSelection().setBaseAndExtent(start.node, start.offset, end.node, end.offset);
    renderedCaret = null;
  }

  // MARK: - Rendering and intents

  function updatePlaceholder() {
    container.classList.toggle('is-empty', model.markdown === '' && !isComposing);
  }

  function render(reply, { restoreSelection = true } = {}) {
    container.innerHTML = reply.html;
    updatePlaceholder();
    if (!restoreSelection) return;
    if (reply.selection) selectRange(reply.selection);
    else placeCaret(reply.cursor.line, reply.cursor.offset, reply.cursor.inside);
  }

  function commit(operation) {
    const before = model.markdown;
    render(operation());
    if (model.markdown !== before) post({ type: 'change', markdown: model.markdown });
  }

  function intentFor(action, selection, extra = {}) {
    const intent = { action, line: selection.startLine, offset: selection.startOffset, insideFormatting: selection.inside, ...extra };
    if (!selection.collapsed) {
      Object.assign(intent, {
        selStartLine: selection.startLine,
        selStartOffset: selection.startOffset,
        selEndLine: selection.endLine,
        selEndOffset: selection.endOffset,
      });
    }
    return intent;
  }

  function send(action, selection, extra) {
    if (!isEditable || !selection) return;
    commit(() => model.handle(intentFor(action, selection, extra)));
  }

  function targetSelection(event) {
    const [range] = event.getTargetRanges?.() || [];
    if (!range || range.collapsed) return null;
    return rangeSelection(range.startContainer, range.startOffset, range.endContainer, range.endOffset);
  }

  const deletions = {
    deleteContentBackward: { action: 'backspace' },
    deleteContentForward: { action: 'delete' },
    deleteWordBackward: { action: 'backspace', alt: true },
    deleteWordForward: { action: 'delete', alt: true },
    deleteSoftLineBackward: { action: 'backspace', meta: true },
    deleteHardLineBackward: { action: 'backspace', meta: true },
    deleteSoftLineForward: { action: 'delete', meta: true },
    deleteHardLineForward: { action: 'delete', meta: true },
  };

  container.addEventListener('beforeinput', (event) => {
    if (isComposing || event.isComposing) return;
    event.preventDefault();
    if (!isEditable) return;
    const selection = currentSelection();
    if (!selection) return;
    const type = event.inputType;

    if (type === 'insertText') {
      send('type', selection, { text: event.data ?? '' });
    } else if (type === 'insertReplacementText') {
      const text = event.data ?? event.dataTransfer?.getData('text/plain') ?? '';
      send('type', targetSelection(event) ?? selection, { text });
    } else if (type === 'insertParagraph' || type === 'insertLineBreak') {
      send('enter', selection, { shift: type === 'insertLineBreak' });
    } else if (deletions[type]) {
      const { action, ...modifiers } = deletions[type];
      const target = selection.collapsed ? targetSelection(event) : null;
      // At a line start the model's own rule applies, so a list item first loses its marker.
      const usesTarget = target && !(action === 'backspace' && selection.startOffset === 0 && !modifiers.meta);
      send(action, usesTarget ? target : selection, usesTarget ? {} : modifiers);
    } else if (type === 'historyUndo' || type === 'historyRedo') {
      commit(() => model.handle({ action: type === 'historyUndo' ? 'undo' : 'redo' }));
    }
  });

  container.addEventListener('keydown', (event) => {
    if (isComposing || event.isComposing || event.keyCode === 229) return;
    const key = event.key.toLowerCase();
    if (event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey && (key === 'b' || key === 'i')) {
      event.preventDefault();
      const selection = currentSelection();
      if (isEditable && selection) commit(() => model.toggleInline(key === 'b' ? 'bold' : 'italic', selection));
    } else if (key === 'tab' && !event.metaKey && !event.ctrlKey && !event.altKey) {
      event.preventDefault();
      send('tab', currentSelection(), { shift: event.shiftKey });
    }
  });

  // IME text is composed in the DOM as usual and committed to the model once at the end.
  container.addEventListener('compositionstart', () => {
    isComposing = true;
    compositionSelection = currentSelection();
    updatePlaceholder();
  });

  container.addEventListener('compositionend', (event) => {
    isComposing = false;
    const selection = compositionSelection;
    compositionSelection = null;
    if (event.data && selection) {
      send('type', selection, { text: event.data });
    } else {
      render(model.reply(), { restoreSelection: false });
      if (selection) placeCaret(selection.startLine, selection.startOffset, selection.inside);
    }
    if (pendingMarkdown !== null) {
      const markdown = pendingMarkdown;
      pendingMarkdown = null;
      api.setMarkdown(markdown, { preservingHistory: true });
    }
  });

  function selectedMarkdown() {
    const selection = currentSelection();
    if (!selection || selection.collapsed) return null;
    return model.selectedMarkdown(intentFor('copy', selection));
  }

  container.addEventListener('copy', (event) => {
    const markdown = selectedMarkdown();
    if (markdown === null) return;
    event.preventDefault();
    event.clipboardData.setData('text/plain', markdown);
  });

  container.addEventListener('cut', (event) => {
    const markdown = selectedMarkdown();
    if (markdown === null) return;
    event.preventDefault();
    event.clipboardData.setData('text/plain', markdown);
    send('backspace', currentSelection());
  });

  container.addEventListener('paste', (event) => {
    event.preventDefault();
    const text = event.clipboardData?.getData('text/plain');
    if (text) send('paste', currentSelection(), { text });
  });

  // Moving text by dragging would need a coordinated delete and insert; only drops from
  // outside the editor are accepted.
  container.addEventListener('dragstart', (event) => event.preventDefault());
  container.addEventListener('dragover', (event) => {
    if (event.dataTransfer?.types.includes('text/plain')) event.preventDefault();
  });
  container.addEventListener('drop', (event) => {
    event.preventDefault();
    const text = event.dataTransfer?.getData('text/plain');
    const range = document.caretRangeFromPoint(event.clientX, event.clientY);
    if (!text || !range || !container.contains(range.startContainer)) return;
    send('paste', rangeSelection(range.startContainer, range.startOffset, range.startContainer, range.startOffset), { text });
  });

  container.addEventListener('mousedown', (event) => {
    if (event.target.closest('.md-checkbox')) event.preventDefault();
  });

  container.addEventListener('click', (event) => {
    const checkbox = event.target.closest('.md-checkbox');
    if (checkbox) {
      event.preventDefault();
      const line = lineDivContaining(checkbox);
      if (line && isEditable) {
        commit(() => model.handle({ action: 'checkbox', line: Number(line.dataset.line), checked: !checkbox.classList.contains('md-checked') }));
      }
      return;
    }
    const link = event.target.closest('a');
    if (link) {
      event.preventDefault();
      const href = link.getAttribute('href');
      if (href && (event.metaKey || !isEditable)) post({ type: 'openLink', url: href });
    }
  });

  document.addEventListener('keydown', (event) => container.classList.toggle('is-command-pressed', event.metaKey));
  document.addEventListener('keyup', (event) => container.classList.toggle('is-command-pressed', event.metaKey));
  window.addEventListener('blur', () => container.classList.remove('is-command-pressed'));

  // MARK: - Host API

  const api = {
    /**
     * Replaces the document. `preservingHistory` keeps the change undoable, for updates that
     * originate outside the editor while it is in use.
     */
    setMarkdown(markdown, { preservingHistory = false } = {}) {
      const normalized = String(markdown).replace(/\r\n?/g, '\n');
      if (isComposing) {
        pendingMarkdown = normalized;
        return;
      }
      if (normalized === model.markdown) return;
      if (preservingHistory) {
        render(model.replace(0, model.markdown.length, normalized), { restoreSelection: container.contains(document.activeElement) });
      } else {
        model.setMarkdown(normalized);
        render(model.reply(), { restoreSelection: false });
        renderedCaret = null;
      }
    },
    getMarkdown: () => model.markdown,
    getSelection: currentSelection,
    setSelection(startLine, startOffset, endLine = startLine, endOffset = startOffset) {
      if (startLine === endLine && startOffset === endOffset) placeCaret(startLine, startOffset);
      else selectRange({ startLine, startOffset, endLine, endOffset });
    },
    focus() {
      const hadSelection = Boolean(currentSelection());
      container.focus();
      if (!hadSelection) placeCaret(model.cursor.line, model.cursor.offset, model.cursor.inside);
    },
    setEditable(editable) {
      isEditable = Boolean(editable);
      container.contentEditable = String(isEditable);
      container.setAttribute('aria-readonly', String(!isEditable));
    },
    setPlaceholder(text) {
      container.dataset.placeholder = String(text);
    },
    // The host routes ⌘Z here: the menu's Undo key equivalent never reaches the page.
    undo() {
      if (isEditable && !isComposing) commit(() => model.handle({ action: 'undo' }));
    },
    redo() {
      if (isEditable && !isComposing) commit(() => model.handle({ action: 'redo' }));
    },
  };

  window.markdownEditor = api;
  render(model.reply(), { restoreSelection: false });
  post({ type: 'ready' });
})();
