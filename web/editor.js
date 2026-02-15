import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import TaskList from '@tiptap/extension-task-list'
import TaskItem from '@tiptap/extension-task-item'
import Placeholder from '@tiptap/extension-placeholder'
import Table from '@tiptap/extension-table'
import TableRow from '@tiptap/extension-table-row'
import TableCell from '@tiptap/extension-table-cell'
import TableHeader from '@tiptap/extension-table-header'
import { Markdown } from 'tiptap-markdown'
import { Extension, Node, mergeAttributes } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

// --- GroupNode Extension ---
// Custom node that renders as a clickable card for navigation

const GroupNode = Node.create({
  name: 'contentGroup',
  group: 'block',
  content: 'block+',
  defining: true,

  addAttributes() {
    return {
      id: {
        default: null,
        parseHTML: element => element.getAttribute('data-group-id'),
        renderHTML: attributes => ({
          'data-group-id': attributes.id,
        }),
      },
      title: {
        default: 'Untitled',
        parseHTML: element => element.getAttribute('data-group-title'),
        renderHTML: attributes => ({
          'data-group-title': attributes.title,
        }),
      },
    }
  },

  parseHTML() {
    return [
      {
        tag: 'div[data-type="content-group"]',
      },
    ]
  },

  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, {
      'data-type': 'content-group',
      class: 'content-group',
    }), 0]
  },

  addNodeView() {
    return ({ node, getPos, editor }) => {
      const dom = document.createElement('div')
      dom.className = 'content-group'
      dom.setAttribute('data-type', 'content-group')
      dom.setAttribute('data-group-id', node.attrs.id || '')

      // Track current node (updated on each update call)
      let currentNode = node

      // Extract title from first line of content (strip markdown formatting)
      const getFirstLineTitle = (groupNode) => {
        let title = 'Untitled'
        if (groupNode.content && groupNode.content.size > 0) {
          const firstChild = groupNode.content.firstChild
          if (firstChild) {
            // Get text content of first block
            let text = ''
            firstChild.forEach(child => {
              if (child.isText) {
                text += child.text
              }
            })
            text = text.trim()
            // Strip markdown formatting
            text = text
              .replace(/^#{1,6}\s*/, '')  // Heading markers
              .replace(/^\s*[-*+]\s*/, '') // List markers
              .replace(/^\s*\d+\.\s*/, '') // Numbered list
              .replace(/^\s*>\s*/, '')     // Blockquote
              .replace(/\*\*([^*]+)\*\*/g, '$1') // Bold
              .replace(/\*([^*]+)\*/g, '$1')     // Italic
              .replace(/__([^_]+)__/g, '$1')     // Bold
              .replace(/_([^_]+)_/g, '$1')       // Italic
              .replace(/`([^`]+)`/g, '$1')       // Inline code
              .trim()
            if (text) {
              // Truncate if too long
              title = text.length > 50 ? text.substring(0, 50) + '…' : text
            }
          }
        }
        return title
      }

      const initialTitle = getFirstLineTitle(node)

      // Create card header (visible in collapsed state)
      const header = document.createElement('div')
      header.className = 'content-group-header'
      header.innerHTML = `
        <span class="content-group-icon">📁</span>
        <span class="content-group-title">${escapeHtml(initialTitle)}</span>
        <span class="content-group-chevron">›</span>
      `

      // Handle click on header to navigate into group
      header.addEventListener('click', (e) => {
        e.preventDefault()
        e.stopPropagation()
        const groupId = currentNode.attrs.id
        const groupTitle = getFirstLineTitle(currentNode)
        try {
          webkit.messageHandlers.openGroup.postMessage({
            id: groupId,
            title: groupTitle,
            pos: typeof getPos === 'function' ? getPos() : 0
          })
        } catch (err) {
          console.log('openGroup:', groupId, groupTitle)
        }
      })

      // Content wrapper (holds actual content when editing inside)
      const contentWrapper = document.createElement('div')
      contentWrapper.className = 'content-group-content'

      dom.appendChild(header)
      dom.appendChild(contentWrapper)

      return {
        dom,
        contentDOM: contentWrapper,
        update: (updatedNode) => {
          if (updatedNode.type.name !== 'contentGroup') return false
          // Update current node reference
          currentNode = updatedNode
          // Update title from first line of content
          const titleEl = header.querySelector('.content-group-title')
          if (titleEl) {
            titleEl.textContent = getFirstLineTitle(updatedNode)
          }
          dom.setAttribute('data-group-id', updatedNode.attrs.id || '')
          return true
        },
      }
    }
  },

  addCommands() {
    return {
      insertGroup: (attrs = {}) => ({ chain, state }) => {
        const id = attrs.id || generateUUID()
        const title = attrs.title || 'Untitled'
        return chain()
          .insertContent({
            type: 'contentGroup',
            attrs: { id, title },
            content: [{ type: 'paragraph' }],
          })
          .run()
      },
      setGroupTitle: (id, title) => ({ tr, state, dispatch }) => {
        let found = false
        state.doc.descendants((node, pos) => {
          if (node.type.name === 'contentGroup' && node.attrs.id === id) {
            if (dispatch) {
              tr.setNodeMarkup(pos, null, { ...node.attrs, title })
            }
            found = true
            return false
          }
        })
        return found
      },
    }
  },
})

// Helper to escape HTML
function escapeHtml(text) {
  const div = document.createElement('div')
  div.textContent = text
  return div.innerHTML
}

// Generate UUID for group IDs
function generateUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0
    const v = c === 'x' ? r : (r & 0x3 | 0x8)
    return v.toString(16)
  })
}

// --- Group Selection Extension ---
// Allows Cmd+G to group currently selected content

const GroupSelectionExtension = Extension.create({
  name: 'groupSelection',

  addKeyboardShortcuts() {
    return {
      'Mod-g': ({ editor }) => {
        return groupCurrentSelection(editor)
      },
      'Escape': () => {
        // Try to navigate back if inside a group
        try {
          webkit.messageHandlers.navigateBack.postMessage(true)
          return true
        } catch (err) {
          // Not in WKWebView context
          return false
        }
      },
    }
  },
})

// Group the current text selection into a group
function groupCurrentSelection(editor) {
  const { state } = editor
  const { selection, schema } = state
  const { from, to } = selection

  // Check if there's actually a selection (not just a cursor)
  if (from === to) {
    return false
  }

  // Find the range of top-level blocks that are fully or partially selected
  const $from = state.doc.resolve(from)
  const $to = state.doc.resolve(to)

  // Get the start of the first block and end of the last block
  let startPos = from
  let endPos = to

  // Find the first top-level block containing the selection start
  for (let d = $from.depth; d >= 1; d--) {
    if ($from.node(d - 1).type.name === 'doc') {
      startPos = $from.before(d)
      break
    }
  }

  // Find the last top-level block containing the selection end
  for (let d = $to.depth; d >= 1; d--) {
    if ($to.node(d - 1).type.name === 'doc') {
      endPos = $to.after(d)
      break
    }
  }

  // Get the content between these positions
  const slice = state.doc.slice(startPos, endPos)
  const content = slice.content

  if (content.size === 0) {
    return false
  }

  // Create the group node
  const groupType = schema.nodes.contentGroup
  if (!groupType) {
    console.error('contentGroup node type not found in schema')
    return false
  }

  const groupId = generateUUID()
  const group = groupType.create(
    { id: groupId, title: 'Untitled' },
    content
  )

  // Replace the range with the group
  const tr = state.tr.replaceWith(startPos, endPos, group)
  editor.view.dispatch(tr)

  return true
}

// --- Table Context Menu ---

let tableMenuEl = null
let tableMenuVisible = false

const tableMenuCommands = [
  { type: 'addRowBefore', title: 'Insert Row Above', icon: '\u2191', section: 'row' },
  { type: 'addRowAfter', title: 'Insert Row Below', icon: '\u2193', section: 'row' },
  { type: 'deleteRow', title: 'Delete Row', icon: '\u2212', section: 'row' },
  { type: 'divider1', section: 'divider' },
  { type: 'addColumnBefore', title: 'Insert Column Left', icon: '\u2190', section: 'column' },
  { type: 'addColumnAfter', title: 'Insert Column Right', icon: '\u2192', section: 'column' },
  { type: 'deleteColumn', title: 'Delete Column', icon: '\u2212', section: 'column' },
  { type: 'divider2', section: 'divider' },
  { type: 'toggleHeaderRow', title: 'Toggle Header Row', icon: 'H', section: 'header' },
  { type: 'toggleHeaderColumn', title: 'Toggle Header Column', icon: 'H', section: 'header' },
  { type: 'divider3', section: 'divider' },
  { type: 'deleteTable', title: 'Delete Table', icon: '\u2717', section: 'table' },
]

function createTableMenu() {
  tableMenuEl = document.createElement('div')
  tableMenuEl.className = 'table-menu'
  tableMenuEl.style.display = 'none'
  document.body.appendChild(tableMenuEl)
}

function renderTableMenu() {
  tableMenuEl.innerHTML = tableMenuCommands.map((cmd) => {
    if (cmd.section === 'divider') {
      return '<div class="table-menu-divider"></div>'
    }
    return `<div class="table-menu-item" data-type="${cmd.type}">
      <span class="table-menu-icon">${cmd.icon}</span>
      <span class="table-menu-title">${cmd.title}</span>
    </div>`
  }).join('')

  // Add click handlers
  tableMenuEl.querySelectorAll('.table-menu-item').forEach(el => {
    el.addEventListener('mousedown', (e) => {
      e.preventDefault()
      e.stopPropagation()
      executeTableCommand(el.dataset.type)
    })
  })
}

function showTableMenu(x, y) {
  tableMenuVisible = true
  renderTableMenu()

  // Position menu at cursor, but keep within viewport
  const menuWidth = 200
  const menuHeight = tableMenuEl.offsetHeight || 300
  const viewportWidth = window.innerWidth
  const viewportHeight = window.innerHeight

  let left = x
  let top = y

  if (x + menuWidth > viewportWidth) {
    left = viewportWidth - menuWidth - 8
  }
  if (y + menuHeight > viewportHeight) {
    top = viewportHeight - menuHeight - 8
  }

  tableMenuEl.style.left = `${left}px`
  tableMenuEl.style.top = `${top}px`
  tableMenuEl.style.display = 'block'
}

function hideTableMenu() {
  tableMenuVisible = false
  if (tableMenuEl) {
    tableMenuEl.style.display = 'none'
  }
}

function executeTableCommand(type) {
  const editor = window._editor
  if (!editor) return

  switch (type) {
    case 'addRowBefore':
      editor.chain().focus().addRowBefore().run()
      break
    case 'addRowAfter':
      editor.chain().focus().addRowAfter().run()
      break
    case 'deleteRow':
      editor.chain().focus().deleteRow().run()
      break
    case 'addColumnBefore':
      editor.chain().focus().addColumnBefore().run()
      break
    case 'addColumnAfter':
      editor.chain().focus().addColumnAfter().run()
      break
    case 'deleteColumn':
      editor.chain().focus().deleteColumn().run()
      break
    case 'toggleHeaderRow':
      editor.chain().focus().toggleHeaderRow().run()
      break
    case 'toggleHeaderColumn':
      editor.chain().focus().toggleHeaderColumn().run()
      break
    case 'deleteTable':
      editor.chain().focus().deleteTable().run()
      break
  }

  hideTableMenu()
}

function isInTable(view, pos) {
  const $pos = view.state.doc.resolve(pos)
  for (let d = $pos.depth; d > 0; d--) {
    if ($pos.node(d).type.name === 'table') {
      return true
    }
  }
  return false
}

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
  { type: 'table', title: 'Table', icon: '\u2637', keywords: ['table', 'grid', 'rows', 'columns', 'cells'] },
  { type: 'group', title: 'Group', icon: '📁', keywords: ['group', 'page', 'folder', 'container', 'card'] },
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
    case 'table':
      editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run()
      break
    case 'group':
      editor.chain().focus().insertGroup().run()
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

// --- Tab Indentation Extension ---

const TabIndentation = Extension.create({
  name: 'tabIndentation',

  addKeyboardShortcuts() {
    return {
      Tab: ({ editor }) => {
        // Check if we're in a task list
        if (editor.isActive('taskItem')) {
          // Try to sink the task item
          if (editor.can().sinkListItem('taskItem')) {
            editor.chain().focus().sinkListItem('taskItem').run()
            return true
          }
          // Can't sink (first item or already max depth), just consume the key
          return true
        }
        // Check if we're in a regular list
        if (editor.isActive('listItem')) {
          if (editor.can().sinkListItem('listItem')) {
            editor.chain().focus().sinkListItem('listItem').run()
            return true
          }
          return true
        }
        // Not in a list, insert a tab character
        editor.chain().focus().insertContent('\t').run()
        return true
      },
      'Shift-Tab': ({ editor }) => {
        // Check if we're in a task list
        if (editor.isActive('taskItem')) {
          if (editor.can().liftListItem('taskItem')) {
            editor.chain().focus().liftListItem('taskItem').run()
            return true
          }
          return true
        }
        // Check if we're in a regular list
        if (editor.isActive('listItem')) {
          if (editor.can().liftListItem('listItem')) {
            editor.chain().focus().liftListItem('listItem').run()
            return true
          }
          return true
        }
        return true
      },
    }
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

    case 'table': {
      const rows = node.content || []
      if (rows.length === 0) return ''

      const serializedRows = rows.map((row, rowIndex) => {
        const cells = row.content || []
        const cellContents = cells.map(cell => {
          const cellText = (cell.content || []).map(c => serializeNode(c, context)).join('').trim()
          return cellText || ' '
        })
        return '| ' + cellContents.join(' | ') + ' |'
      })

      // Insert separator after header row (first row)
      if (serializedRows.length > 0) {
        const firstRow = rows[0]
        const numCols = (firstRow.content || []).length
        const separator = '| ' + Array(numCols).fill('---').join(' | ') + ' |'
        serializedRows.splice(1, 0, separator)
      }

      return serializedRows.join('\n')
    }

    case 'tableRow':
    case 'tableCell':
    case 'tableHeader':
      // These are handled by the table case
      return ''

    case 'contentGroup': {
      const groupId = node.attrs?.id || ''
      const inner = serializeChildren(node.content, context)
      // Derive title from first line of content, stripping markdown
      const firstLine = inner.split('\n')[0] || ''
      const title = firstLine
        .replace(/^#{1,6}\s*/, '')      // Heading markers
        .replace(/^\s*[-*+]\s*/, '')    // List markers
        .replace(/^\s*\d+\.\s*/, '')    // Numbered list
        .replace(/^\s*>\s*/, '')        // Blockquote
        .replace(/\*\*([^*]+)\*\*/g, '$1') // Bold
        .replace(/\*([^*]+)\*/g, '$1')     // Italic
        .replace(/`([^`]+)`/g, '$1')       // Inline code
        .trim()
        .substring(0, 50) || 'Untitled'
      return `<!-- group:${groupId}:${title} -->\n${inner}\n<!-- /group:${groupId} -->`
    }

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


// --- Table Markdown Fix Extension ---
// Fixes markdown table parsing by unwrapping <thead> and <tbody> elements
// that markdown-it generates but Tiptap's Table schema doesn't expect

const TableMarkdownFix = Extension.create({
  name: 'tableMarkdownFix',

  addStorage() {
    return {
      markdown: {
        parse: {
          updateDOM(element) {
            // Find all tables and unwrap thead/tbody so tr elements are direct children
            element.querySelectorAll('table').forEach(table => {
              ['thead', 'tbody', 'tfoot'].forEach(tag => {
                const wrapper = table.querySelector(tag)
                if (wrapper) {
                  // Move all children (tr elements) to be direct children of table
                  while (wrapper.firstChild) {
                    table.insertBefore(wrapper.firstChild, wrapper)
                  }
                  wrapper.remove()
                }
              })
            })
          }
        }
      }
    }
  }
})

// --- Group Markdown Preprocessor ---
// Converts <!-- group:id:title --> ... <!-- /group:id --> comments into parseable HTML

function preprocessGroupMarkdown(markdown) {
  // Match group start/end comments and wrap content in div
  const groupStartRegex = /<!--\s*group:([^:]+):([^>]+?)\s*-->/g
  const groupEndRegex = /<!--\s*\/group:([^>]+?)\s*-->/g

  // First pass: find all group regions and build a tree structure
  let result = markdown

  // Replace start comments with opening div
  result = result.replace(groupStartRegex, (match, id, title) => {
    const escapedTitle = title.replace(/"/g, '&quot;')
    return `<div data-type="content-group" data-group-id="${id}" data-group-title="${escapedTitle}">`
  })

  // Replace end comments with closing div
  result = result.replace(groupEndRegex, '</div>')

  return result
}

// --- Table Context Menu Extension ---

const TableContextMenu = Extension.create({
  name: 'tableContextMenu',

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey('tableContextMenu'),
        props: {
          handleDOMEvents: {
            contextmenu(view, event) {
              // Check if right-click is inside a table
              const pos = view.posAtCoords({ left: event.clientX, top: event.clientY })
              if (pos && isInTable(view, pos.pos)) {
                event.preventDefault()
                showTableMenu(event.clientX, event.clientY)
                return true
              }
              return false
            },
          },
        },
      }),
    ]
  },
})

// --- Initialize editor ---

function initEditor() {
  createSlashMenu()
  createTableMenu()

  const editor = new Editor({
    element: document.getElementById('editor'),
    extensions: [
      StarterKit.configure({
        heading: { levels: [1, 2, 3] },
      }),
      Link.configure({
        openOnClick: false, // We handle clicks ourselves
        autolink: true,
        linkOnPaste: true,
        HTMLAttributes: {
          class: 'tiptap-link',
        },
      }),
      TaskList,
      TaskItem.configure({
        nested: true,
      }),
      Placeholder.configure({
        placeholder: 'Type / for commands...',
      }),
      Markdown.configure({
        html: true,  // Required for group nodes to parse correctly
        transformCopiedText: true,
        transformPastedText: true,
      }),
      Table.configure({
        resizable: true,
        HTMLAttributes: {
          class: 'tiptap-table',
        },
      }),
      TableRow,
      TableHeader,
      TableCell,
      TableMarkdownFix,
      SlashCommands,
      TodoInputRule,
      TableContextMenu,
      TabIndentation,
      GroupNode,
      GroupSelectionExtension,
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
        // Preprocess group comments before parsing
        const processed = preprocessGroupMarkdown(markdown)
        editor.commands.setContent(processed)
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
    // Get the content of a specific group by ID
    getGroupContent(groupId) {
      const { state } = editor
      let content = ''
      state.doc.descendants((node, pos) => {
        if (node.type.name === 'contentGroup' && node.attrs.id === groupId) {
          // Serialize the content inside this group
          const groupContent = { type: 'doc', content: [] }
          node.forEach(child => {
            groupContent.content.push(child.toJSON())
          })
          content = serializeChildren(groupContent.content, {})
          return false // Stop searching
        }
      })
      return content
    },
    // Update the content of a specific group by ID
    updateGroupContent(groupId, newMarkdown) {
      const { state } = editor
      let found = false
      state.doc.descendants((node, pos) => {
        if (node.type.name === 'contentGroup' && node.attrs.id === groupId) {
          // Parse the new markdown content
          const tempEditor = new Editor({
            extensions: editor.extensionManager.extensions,
            content: preprocessGroupMarkdown(newMarkdown),
          })
          const newContent = tempEditor.state.doc.content
          tempEditor.destroy()

          // Replace the group's content
          const tr = state.tr
          const groupStart = pos + 1 // After opening tag
          const groupEnd = pos + node.nodeSize - 1 // Before closing tag
          tr.replaceWith(groupStart, groupEnd, newContent)
          editor.view.dispatch(tr)
          found = true
          return false
        }
      })
      return found
    },
    // Set the title of a group
    setGroupTitle(groupId, title) {
      return editor.commands.setGroupTitle(groupId, title)
    },
    // Navigate back (for keyboard shortcut - tells Swift to handle navigation)
    navigateBack() {
      try {
        webkit.messageHandlers.navigateBack.postMessage(true)
      } catch (err) {
        console.log('navigateBack not available')
      }
    },
  }

  // Notify Swift that editor is ready
  try {
    webkit.messageHandlers.editorReady.postMessage(true)
  } catch (e) {
    // Not in WKWebView context
  }

  // Handle link clicks - send to Swift to open in browser
  // Also handle click-after-content to append
  document.getElementById('editor').addEventListener('click', (e) => {
    const link = e.target.closest('a')
    if (link && link.href) {
      e.preventDefault()
      e.stopPropagation()
      try {
        webkit.messageHandlers.openLink.postMessage(link.href)
      } catch (err) {
        // Fallback for non-WKWebView context
        window.open(link.href, '_blank')
      }
      return
    }

    // Check if click is below all content (in the padding area)
    const editorEl = document.getElementById('editor')
    const contentEl = editorEl.querySelector('.tiptap-content')
    if (contentEl && e.target === editorEl) {
      // Click was on the editor container itself, not on content
      // Move cursor to end of document
      editor.commands.focus('end')
    }
  })

  // Handle clicks below content to allow easy appending
  document.getElementById('editor').addEventListener('click', (e) => {
    const editorEl = document.getElementById('editor')
    const contentEl = editorEl.querySelector('.tiptap-content')

    if (!contentEl) return

    // Find the last actual content element (could be paragraph, heading, group, etc.)
    const lastContentElement = contentEl.lastElementChild
    if (!lastContentElement) return

    const lastElementRect = lastContentElement.getBoundingClientRect()
    const clickY = e.clientY

    // If click is below the last content element
    if (clickY > lastElementRect.bottom + 5) {
      e.preventDefault()
      appendParagraphAtEnd()
    }
  }, true) // Use capture phase

  // Also handle mousedown for immediate response
  document.getElementById('editor').addEventListener('mousedown', (e) => {
    const editorEl = document.getElementById('editor')
    const contentEl = editorEl.querySelector('.tiptap-content')

    if (!contentEl) return

    // Find the last actual content element
    const lastContentElement = contentEl.lastElementChild
    if (!lastContentElement) return

    const lastElementRect = lastContentElement.getBoundingClientRect()
    const editorRect = editorEl.getBoundingClientRect()
    const clickY = e.clientY

    // If click is in the padding area below last element
    if (clickY > lastElementRect.bottom + 5 && clickY < editorRect.bottom) {
      e.preventDefault()
      e.stopPropagation()
      appendParagraphAtEnd()
    }
  }, true) // Use capture phase

  // Helper to append paragraph at end and focus
  function appendParagraphAtEnd() {
    const { state } = editor
    const lastNode = state.doc.lastChild

    // If last node is empty paragraph, just focus
    if (lastNode && lastNode.type.name === 'paragraph' && lastNode.content.size === 0) {
      editor.commands.focus('end')
      return
    }

    // If last node is a group or any other block, insert a new paragraph after it
    const endPos = state.doc.content.size
    editor.chain()
      .focus()
      .insertContentAt(endPos, { type: 'paragraph' })
      .focus('end')
      .run()
  }

  // Also expose for external use (e.g., from Swift)
  window.tiptap.appendParagraph = appendParagraphAtEnd
}

// Handle click outside menus to dismiss
document.addEventListener('click', (e) => {
  if (slashMenuVisible && slashMenuEl && !slashMenuEl.contains(e.target)) {
    hideSlashMenu()
  }
  if (tableMenuVisible && tableMenuEl && !tableMenuEl.contains(e.target)) {
    hideTableMenu()
  }
})

// Handle escape key to dismiss table menu
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && tableMenuVisible) {
    hideTableMenu()
  }
})

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initEditor)
} else {
  initEditor()
}
