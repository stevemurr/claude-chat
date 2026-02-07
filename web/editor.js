import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import TaskList from '@tiptap/extension-task-list'
import TaskItem from '@tiptap/extension-task-item'
import Placeholder from '@tiptap/extension-placeholder'
import { Markdown } from 'tiptap-markdown'
import { Extension } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'

// --- Slash Command Menu (pure DOM, driven by a Tiptap plugin) ---

const slashCommands = [
  { type: 'paragraph', title: 'Text', icon: 'T', keywords: ['paragraph', 'plain', 'text'] },
  { type: 'heading1', title: 'Heading 1', icon: 'H1', keywords: ['h1', 'title', 'large'] },
  { type: 'heading2', title: 'Heading 2', icon: 'H2', keywords: ['h2', 'subtitle', 'medium'] },
  { type: 'heading3', title: 'Heading 3', icon: 'H3', keywords: ['h3', 'small'] },
  { type: 'bulletList', title: 'Bullet List', icon: '\u2022', keywords: ['unordered', 'ul', 'dash', 'bullet'] },
  { type: 'orderedList', title: 'Numbered List', icon: '1.', keywords: ['ordered', 'ol', 'numbered'] },
  { type: 'taskList', title: 'To-do', icon: '\u2611', keywords: ['checkbox', 'task', 'check', 'todo'] },
  { type: 'blockquote', title: 'Quote', icon: '\u201C', keywords: ['blockquote', 'quote'] },
  { type: 'codeBlock', title: 'Code', icon: '</>', keywords: ['snippet', 'pre', 'mono', 'code'] },
  { type: 'horizontalRule', title: 'Divider', icon: '\u2014', keywords: ['hr', 'line', 'separator', 'divider'] },
]

let slashMenuEl = null
let slashMenuVisible = false
let slashSelectedIndex = 0
let slashQuery = ''
let slashRange = null
let filteredCommands = slashCommands

function createSlashMenu() {
  slashMenuEl = document.createElement('div')
  slashMenuEl.className = 'slash-menu'
  slashMenuEl.style.display = 'none'
  document.body.appendChild(slashMenuEl)
}

function renderSlashMenu() {
  const q = slashQuery.toLowerCase()
  filteredCommands = q
    ? slashCommands.filter(c =>
        c.title.toLowerCase().includes(q) ||
        c.keywords.some(k => k.includes(q))
      )
    : slashCommands

  if (filteredCommands.length === 0) {
    hideSlashMenu()
    return
  }

  if (slashSelectedIndex >= filteredCommands.length) {
    slashSelectedIndex = filteredCommands.length - 1
  }

  slashMenuEl.innerHTML = filteredCommands.map((cmd, i) =>
    `<div class="slash-item${i === slashSelectedIndex ? ' selected' : ''}" data-index="${i}">
      <span class="slash-icon">${cmd.icon}</span>
      <span class="slash-title">${cmd.title}</span>
    </div>`
  ).join('')

  // Add click handlers
  slashMenuEl.querySelectorAll('.slash-item').forEach(el => {
    el.addEventListener('mousedown', (e) => {
      e.preventDefault()
      const idx = parseInt(el.dataset.index)
      executeSlashCommand(filteredCommands[idx])
    })
  })
}

function showSlashMenu(from) {
  slashRange = from
  slashQuery = ''
  slashSelectedIndex = 0
  slashMenuVisible = true

  // Position menu near cursor
  const coords = window._editor.view.coordsAtPos(from)
  slashMenuEl.style.left = `${coords.left}px`
  slashMenuEl.style.top = `${coords.bottom + 4}px`
  slashMenuEl.style.display = 'block'
  renderSlashMenu()
}

function hideSlashMenu() {
  slashMenuVisible = false
  slashQuery = ''
  slashRange = null
  if (slashMenuEl) {
    slashMenuEl.style.display = 'none'
  }
}

function executeSlashCommand(cmd) {
  const editor = window._editor
  if (!editor || !slashRange) return

  // Delete the slash and query text
  const { state } = editor.view
  const to = state.selection.from
  editor.chain().focus().deleteRange({ from: slashRange - 1, to }).run()

  // Apply the block type
  switch (cmd.type) {
    case 'paragraph':
      editor.chain().focus().setParagraph().run()
      break
    case 'heading1':
      editor.chain().focus().toggleHeading({ level: 1 }).run()
      break
    case 'heading2':
      editor.chain().focus().toggleHeading({ level: 2 }).run()
      break
    case 'heading3':
      editor.chain().focus().toggleHeading({ level: 3 }).run()
      break
    case 'bulletList':
      editor.chain().focus().toggleBulletList().run()
      break
    case 'orderedList':
      editor.chain().focus().toggleOrderedList().run()
      break
    case 'taskList':
      editor.chain().focus().toggleTaskList().run()
      break
    case 'blockquote':
      editor.chain().focus().toggleBlockquote().run()
      break
    case 'codeBlock':
      editor.chain().focus().toggleCodeBlock().run()
      break
    case 'horizontalRule':
      editor.chain().focus().setHorizontalRule().run()
      break
  }

  hideSlashMenu()
}

// --- Custom Tiptap extension for slash commands ---

const SlashCommands = Extension.create({
  name: 'slashCommands',

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey('slashCommands'),
        props: {
          handleKeyDown(view, event) {
            if (slashMenuVisible) {
              if (event.key === 'ArrowDown') {
                event.preventDefault()
                slashSelectedIndex = (slashSelectedIndex + 1) % filteredCommands.length
                renderSlashMenu()
                return true
              }
              if (event.key === 'ArrowUp') {
                event.preventDefault()
                slashSelectedIndex = (slashSelectedIndex - 1 + filteredCommands.length) % filteredCommands.length
                renderSlashMenu()
                return true
              }
              if (event.key === 'Enter') {
                event.preventDefault()
                if (filteredCommands[slashSelectedIndex]) {
                  executeSlashCommand(filteredCommands[slashSelectedIndex])
                }
                return true
              }
              if (event.key === 'Escape') {
                event.preventDefault()
                hideSlashMenu()
                return true
              }
            }
            return false
          },
          handleTextInput(view, from, to, text) {
            if (text === '/') {
              const { state } = view
              const $from = state.doc.resolve(from)
              const textBefore = $from.parent.textContent.slice(0, $from.parentOffset)
              // Show menu if / is typed at start of an empty block or as first char
              if (textBefore.trim() === '') {
                setTimeout(() => showSlashMenu(from + 1), 0)
              }
            } else if (slashMenuVisible) {
              // Update query
              slashQuery += text
              renderSlashMenu()
            }
            return false
          },
        },
        // Watch for deletions while slash menu is open
        appendTransaction(transactions, oldState, newState) {
          if (slashMenuVisible) {
            const { from } = newState.selection
            if (slashRange !== null) {
              const $from = newState.doc.resolve(from)
              const textBefore = $from.parent.textContent.slice(0, $from.parentOffset)
              const slashPos = textBefore.lastIndexOf('/')
              if (slashPos === -1) {
                hideSlashMenu()
              } else {
                slashQuery = textBefore.slice(slashPos + 1)
                renderSlashMenu()
              }
            }
          }
          return null
        },
      }),
    ]
  },
})

// --- Custom input rule for todo shortcut: [] or [ ] at start of line ---

const TodoInputRule = Extension.create({
  name: 'todoInputRule',

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey('todoInputRule'),
        props: {
          handleTextInput(view, from, to, text) {
            if (text !== ' ') return false
            const { state } = view
            const $from = state.doc.resolve(from)
            const textBefore = $from.parent.textContent.slice(0, $from.parentOffset)
            // Match "[]" or "[ ]" at start of paragraph
            if ($from.parent.type.name === 'paragraph' && (textBefore === '[]' || textBefore === '[ ]')) {
              const editor = window._editor
              if (!editor) return false
              // Delete the [] or [ ] text, then convert to task list
              const blockStart = from - textBefore.length
              const tr = state.tr.delete(blockStart, from + 1) // +1 for the space being typed
              view.dispatch(tr)
              editor.chain().focus().toggleTaskList().run()
              return true
            }
            return false
          },
        },
      }),
    ]
  },
})


// --- Custom JSON-to-Markdown serializer ---
// More reliable than tiptap-markdown's getMarkdown() which can return HTML

function serializeInline(content) {
  if (!content) return ''
  return content.map(node => {
    if (node.type === 'text') {
      let text = node.text || ''
      if (node.marks) {
        for (const mark of node.marks) {
          switch (mark.type) {
            case 'bold': text = `**${text}**`; break
            case 'italic': text = `*${text}*`; break
            case 'code': text = '`' + text + '`'; break
            case 'strike': text = `~~${text}~~`; break
            case 'link': text = `[${text}](${mark.attrs?.href || ''})`; break
          }
        }
      }
      return text
    }
    if (node.type === 'hardBreak') return '\n'
    return ''
  }).join('')
}

function serializeNode(node, context) {
  context = context || {}
  switch (node.type) {
    case 'doc':
      return serializeChildren(node.content, context)

    case 'paragraph':
      return serializeInline(node.content)

    case 'heading': {
      const level = node.attrs?.level || 1
      const prefix = '#'.repeat(level) + ' '
      return prefix + serializeInline(node.content)
    }

    case 'bulletList':
      return (node.content || []).map(child =>
        serializeNode(child, { ...context, listType: 'bullet' })
      ).join('\n')

    case 'orderedList': {
      let num = node.attrs?.start || 1
      return (node.content || []).map(child => {
        const result = serializeNode(child, { ...context, listType: 'ordered', listNumber: num })
        num++
        return result
      }).join('\n')
    }

    case 'listItem': {
      const inner = (node.content || []).map(c => serializeNode(c, context)).join('\n')
      if (context.listType === 'ordered') {
        return `${context.listNumber || 1}. ${inner}`
      }
      return `- ${inner}`
    }

    case 'taskList':
      return (node.content || []).map(child =>
        serializeNode(child, { ...context, listType: 'task' })
      ).join('\n')

    case 'taskItem': {
      const checked = node.attrs?.checked ? 'x' : ' '
      const inner = (node.content || []).map(c => serializeNode(c, context)).join('\n')
      return `- [${checked}] ${inner}`
    }

    case 'blockquote': {
      const inner = (node.content || []).map(c => serializeNode(c, context)).join('\n')
      return inner.split('\n').map(line => `> ${line}`).join('\n')
    }

    case 'codeBlock': {
      const lang = node.attrs?.language || ''
      const code = (node.content || []).map(c => c.text || '').join('')
      return '```' + lang + '\n' + code + '\n```'
    }

    case 'horizontalRule':
      return '---'

    case 'hardBreak':
      return '\n'

    default:
      // Fallback: serialize children or inline content
      if (node.content) {
        return (node.content || []).map(c => serializeNode(c, context)).join('\n')
      }
      return serializeInline(node.content)
  }
}

function serializeChildren(content, context) {
  if (!content) return ''
  const blocks = []
  for (let i = 0; i < content.length; i++) {
    const node = content[i]
    const text = serializeNode(node, context)
    blocks.push(text)
  }

  // Join blocks with blank lines between them, except consecutive list items
  const lines = []
  for (let i = 0; i < blocks.length; i++) {
    lines.push(blocks[i])
    if (i < blocks.length - 1) {
      const curr = content[i].type
      const next = content[i + 1].type
      const isConsecutiveList =
        (curr === 'bulletList' && next === 'bulletList') ||
        (curr === 'orderedList' && next === 'orderedList') ||
        (curr === 'taskList' && next === 'taskList')
      if (!isConsecutiveList) {
        lines.push('')
      }
    }
  }
  return lines.join('\n')
}

function editorToMarkdown(editor) {
  const json = editor.getJSON()
  return serializeChildren(json.content, {})
}

// --- Initialize editor ---

function initEditor() {
  createSlashMenu()

  const editor = new Editor({
    element: document.getElementById('editor'),
    extensions: [
      StarterKit.configure({
        heading: { levels: [1, 2, 3] },
      }),
      TaskList,
      TaskItem.configure({
        nested: false,
      }),
      Placeholder.configure({
        placeholder: 'Type / for commands...',
      }),
      Markdown.configure({
        html: false,
        transformCopiedText: true,
        transformPastedText: true,
      }),
      SlashCommands,
      TodoInputRule,
    ],
    autofocus: true,
    editorProps: {
      attributes: {
        class: 'tiptap-content',
        spellcheck: 'true',
      },
    },
    onUpdate({ editor }) {
      const markdown = editorToMarkdown(editor)
      try {
        webkit.messageHandlers.contentChanged.postMessage(markdown)
      } catch (e) {
        // Not in WKWebView context
      }
    },
  })

  window._editor = editor

  // Public API for Swift bridge
  window.tiptap = {
    setContent(markdown) {
      if (!markdown || markdown.trim() === '') {
        editor.commands.clearContent()
      } else {
        editor.commands.setContent(markdown)
      }
    },
    getContent() {
      return editorToMarkdown(editor)
    },
    focus() {
      editor.commands.focus()
    },
    clear() {
      editor.commands.clearContent()
      editor.commands.focus()
    },
  }

  // Notify Swift that editor is ready
  try {
    webkit.messageHandlers.editorReady.postMessage(true)
  } catch (e) {
    // Not in WKWebView context
  }
}

// Handle click outside slash menu to dismiss
document.addEventListener('click', (e) => {
  if (slashMenuVisible && slashMenuEl && !slashMenuEl.contains(e.target)) {
    hideSlashMenu()
  }
})

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initEditor)
} else {
  initEditor()
}
