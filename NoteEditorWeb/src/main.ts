import './styles.css'

import { Editor, Extension, Node, mergeAttributes, type Range } from '@tiptap/core'
import Placeholder from '@tiptap/extension-placeholder'
import Table from '@tiptap/extension-table'
import TableCell from '@tiptap/extension-table-cell'
import TableHeader from '@tiptap/extension-table-header'
import TableRow from '@tiptap/extension-table-row'
import TaskItem from '@tiptap/extension-task-item'
import TaskList from '@tiptap/extension-task-list'
import StarterKit from '@tiptap/starter-kit'
import Suggestion, { type SuggestionKeyDownProps, type SuggestionProps } from '@tiptap/suggestion'

type JSONObject = Record<string, unknown>

type BridgeMessage = {
  type: string
  payload?: JSONObject
}

type SourcePayload = {
  title: string
  url: string
  capturedAt?: string
}

type SlashItem = {
  title: string
  description: string
  keywords: string[]
  command: (editor: Editor) => void
}

declare global {
  interface Window {
    NoteEditor: {
      receiveCommand: (command: string, payload: JSONObject) => void
    }
    webkit?: {
      messageHandlers?: {
        noteEditorBridge?: {
          postMessage: (message: BridgeMessage) => void
        }
      }
    }
  }
}

const toolbar = document.getElementById('toolbar')
const editorElement = document.getElementById('editor')

if (!toolbar || !editorElement) {
  throw new Error('Wheel note editor failed to find its root elements.')
}

let documentChangeTimer: number | undefined

const sendBridgeMessage = (type: string, payload: JSONObject = {}) => {
  window.webkit?.messageHandlers?.noteEditorBridge?.postMessage({ type, payload })
}

const PageSource = Node.create({
  name: 'pageSource',
  group: 'block',
  atom: true,
  selectable: true,
  draggable: false,

  addAttributes() {
    return {
      title: { default: '' },
      url: { default: '' },
      capturedAt: { default: '' },
    }
  },

  parseHTML() {
    return [{ tag: 'div[data-type="page-source"]' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, { 'data-type': 'page-source' })]
  },

  addNodeView() {
    return ({ node }) => {
      const dom = document.createElement('div')
      dom.className = 'page-source'
      dom.dataset.type = 'page-source'

      const icon = document.createElement('div')
      icon.className = 'page-source__icon'
      icon.textContent = '↗'

      const meta = document.createElement('div')
      meta.className = 'page-source__meta'

      const link = document.createElement('a')
      link.className = 'page-source__title'
      link.href = String(node.attrs.url ?? '')
      link.target = '_blank'
      link.rel = 'noreferrer'
      link.textContent = String(node.attrs.title ?? node.attrs.url ?? 'Source')

      const url = document.createElement('span')
      url.className = 'page-source__url'
      url.textContent = String(node.attrs.url ?? '')

      const time = document.createElement('span')
      time.className = 'page-source__time'
      time.textContent = formatCapturedAt(String(node.attrs.capturedAt ?? ''))

      meta.append(link, url)
      dom.append(icon, meta, time)

      return { dom }
    }
  },
})

const slashItems: SlashItem[] = [
  {
    title: 'Heading 1',
    description: 'Large section heading',
    keywords: ['heading', 'title', 'h1'],
    command: (editor) => editor.chain().focus().toggleHeading({ level: 1 }).run(),
  },
  {
    title: 'Heading 2',
    description: 'Secondary section heading',
    keywords: ['heading', 'subtitle', 'h2'],
    command: (editor) => editor.chain().focus().toggleHeading({ level: 2 }).run(),
  },
  {
    title: 'Bullet List',
    description: 'Create a bulleted list',
    keywords: ['list', 'bullets', 'unordered'],
    command: (editor) => editor.chain().focus().toggleBulletList().run(),
  },
  {
    title: 'Checklist',
    description: 'Track tasks with checkboxes',
    keywords: ['tasks', 'todo', 'checklist'],
    command: (editor) => editor.chain().focus().toggleTaskList().run(),
  },
  {
    title: 'Numbered List',
    description: 'Create an ordered list',
    keywords: ['list', 'ordered', 'numbers'],
    command: (editor) => editor.chain().focus().toggleOrderedList().run(),
  },
  {
    title: 'Quote',
    description: 'Insert a blockquote',
    keywords: ['blockquote', 'quote', 'citation'],
    command: (editor) => editor.chain().focus().toggleBlockquote().run(),
  },
  {
    title: 'Code Block',
    description: 'Insert a code block',
    keywords: ['code', 'snippet', 'monospace'],
    command: (editor) => editor.chain().focus().toggleCodeBlock().run(),
  },
  {
    title: 'Table',
    description: 'Insert a 3x3 table',
    keywords: ['table', 'grid', 'rows'],
    command: (editor) => editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run(),
  },
]

const createSlashMenu = () => {
  let element: HTMLDivElement | null = null
  let propsRef: SuggestionProps<SlashItem> | null = null
  let selectedIndex = 0

  const remove = () => {
    element?.remove()
    element = null
    propsRef = null
    selectedIndex = 0
  }

  const updatePosition = () => {
    if (!element || !propsRef?.clientRect) {
      return
    }

    const rect = propsRef.clientRect()
    if (!rect) {
      return
    }

    element.style.left = `${rect.left + window.scrollX}px`
    element.style.top = `${rect.bottom + window.scrollY + 10}px`
  }

  const selectItem = (index: number) => {
    if (!propsRef) {
      return
    }

    const item = propsRef.items[index]
    if (!item) {
      return
    }

    propsRef.command(item)
  }

  const renderItems = () => {
    if (!element || !propsRef) {
      return
    }

    element.innerHTML = ''
    propsRef.items.forEach((item, index) => {
      const button = document.createElement('button')
      button.type = 'button'
      button.className = `slash-menu__item${index === selectedIndex ? ' is-selected' : ''}`
      button.innerHTML = `<strong>${item.title}</strong><span>${item.description}</span>`
      button.onmousedown = (event) => {
        event.preventDefault()
        selectItem(index)
      }
      element?.appendChild(button)
    })
  }

  return {
    onStart: (props: SuggestionProps<SlashItem>) => {
      propsRef = props
      selectedIndex = 0
      element = document.createElement('div')
      element.className = 'slash-menu'
      document.body.appendChild(element)
      renderItems()
      updatePosition()
    },
    onUpdate: (props: SuggestionProps<SlashItem>) => {
      propsRef = props
      selectedIndex = Math.min(selectedIndex, Math.max(props.items.length - 1, 0))
      renderItems()
      updatePosition()
    },
    onKeyDown: ({ event }: SuggestionKeyDownProps) => {
      if (!propsRef) {
        return false
      }

      if (event.key === 'ArrowDown') {
        selectedIndex = (selectedIndex + 1) % propsRef.items.length
        renderItems()
        return true
      }

      if (event.key === 'ArrowUp') {
        selectedIndex = (selectedIndex + propsRef.items.length - 1) % propsRef.items.length
        renderItems()
        return true
      }

      if (event.key === 'Enter') {
        selectItem(selectedIndex)
        return true
      }

      if (event.key === 'Escape') {
        remove()
        return true
      }

      return false
    },
    onExit: remove,
  }
}

const SlashCommand = Extension.create({
  name: 'slashCommand',

  addProseMirrorPlugins() {
    return [
      Suggestion<SlashItem>({
        editor: this.editor,
        char: '/',
        startOfLine: false,
        allow: ({ state, range }) => {
          const $from = state.doc.resolve(range.from)
          const textBefore = $from.parent.textBetween(0, $from.parentOffset, undefined, '\ufffc')
          return textBefore === '/' || textBefore.endsWith(' /')
        },
        items: ({ query }) => {
          const normalized = query.trim().toLowerCase()
          if (!normalized) {
            return slashItems
          }
          return slashItems.filter((item) => {
            return (
              item.title.toLowerCase().includes(normalized) ||
              item.description.toLowerCase().includes(normalized) ||
              item.keywords.some((keyword) => keyword.includes(normalized))
            )
          })
        },
        command: ({ editor, range, props }) => {
          editor.chain().focus().deleteRange(range as Range).run()
          props.command(editor)
        },
        render: createSlashMenu,
      }),
    ]
  },
})

const editor = new Editor({
  element: editorElement,
  extensions: [
    StarterKit.configure({
      history: true,
      heading: { levels: [1, 2, 3] },
    }),
    TaskList,
    TaskItem.configure({ nested: true }),
    Table.configure({ resizable: true }),
    TableRow,
    TableHeader,
    TableCell,
    Placeholder.configure({
      placeholder: 'Start writing, or type / for commands…',
    }),
    PageSource,
    SlashCommand,
  ],
  editorProps: {
    attributes: {
      class: 'wheel-note-editor',
      spellcheck: 'true',
    },
  },
  content: {
    type: 'doc',
    content: [{ type: 'paragraph' }],
  },
  onUpdate: ({ editor }) => {
    window.clearTimeout(documentChangeTimer)
    documentChangeTimer = window.setTimeout(() => {
      sendBridgeMessage('documentChanged', { document: editor.getJSON() as JSONObject })
    }, 120)
    renderToolbar()
  },
  onSelectionUpdate: renderToolbar,
  onCreate: () => {
    renderToolbar()
    sendBridgeMessage('ready')
  },
})

const toolbarButtons = [
  {
    label: 'H1',
    isActive: () => editor.isActive('heading', { level: 1 }),
    run: () => editor.chain().focus().toggleHeading({ level: 1 }).run(),
  },
  {
    label: 'H2',
    isActive: () => editor.isActive('heading', { level: 2 }),
    run: () => editor.chain().focus().toggleHeading({ level: 2 }).run(),
  },
  {
    label: 'Bold',
    isActive: () => editor.isActive('bold'),
    run: () => editor.chain().focus().toggleBold().run(),
  },
  {
    label: 'List',
    isActive: () => editor.isActive('bulletList'),
    run: () => editor.chain().focus().toggleBulletList().run(),
  },
  {
    label: 'Tasks',
    isActive: () => editor.isActive('taskList'),
    run: () => editor.chain().focus().toggleTaskList().run(),
  },
  {
    label: 'Quote',
    isActive: () => editor.isActive('blockquote'),
    run: () => editor.chain().focus().toggleBlockquote().run(),
  },
  {
    label: 'Code',
    isActive: () => editor.isActive('codeBlock'),
    run: () => editor.chain().focus().toggleCodeBlock().run(),
  },
  {
    label: 'Table',
    isActive: () => editor.isActive('table'),
    run: () => editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run(),
  },
]

function renderToolbar() {
  toolbar!.innerHTML = ''
  toolbarButtons.forEach((item) => {
    const button = document.createElement('button')
    button.type = 'button'
    button.textContent = item.label
    if (item.isActive()) {
      button.classList.add('is-active')
    }
    button.onclick = () => item.run()
    toolbar!.appendChild(button)
  })
}

function setDocument(document: JSONObject | undefined) {
  editor.commands.setContent(
    document ?? {
      type: 'doc',
      content: [{ type: 'paragraph' }],
    },
    false
  )
  renderToolbar()
}

function insertSourceBlock(source: SourcePayload | undefined) {
  if (!source) {
    return
  }

  editor
    .chain()
    .focus()
    .insertContent([
      {
        type: 'pageSource',
        attrs: {
          title: source.title,
          url: source.url,
          capturedAt: source.capturedAt ?? new Date().toISOString(),
        },
      },
      {
        type: 'paragraph',
      },
    ])
    .run()
}

window.NoteEditor = {
  receiveCommand(command: string, payload: JSONObject) {
    try {
      switch (command) {
        case 'loadDocument':
          setDocument(payload.document as JSONObject | undefined)
          break
        case 'focusEditor':
          editor.commands.focus('end')
          break
        case 'insertSourceBlock':
          insertSourceBlock(payload.source as SourcePayload | undefined)
          break
        default:
          break
      }
    } catch (error) {
      sendBridgeMessage('editorError', {
        message: error instanceof Error ? error.message : 'Unknown note editor failure',
      })
    }
  },
}

function formatCapturedAt(value: string): string {
  if (!value) {
    return 'Source'
  }

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return 'Source'
  }

  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  })
}
