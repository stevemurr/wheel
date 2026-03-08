import './styles.css'

import { Editor, Extension, Node, mergeAttributes, type Range } from '@tiptap/core'
import type { Node as ProseMirrorNode } from '@tiptap/pm/model'
import { TextSelection } from '@tiptap/pm/state'
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
      debugApplyMarkdown: (text: string) => JSONObject
      debugOpenSlashMenu: (query: string) => JSONObject
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

const editorElement = document.getElementById('editor')

if (!editorElement) {
  throw new Error('Wheel note editor failed to find its editor root element.')
}

let documentChangeTimer: number | undefined

const sendBridgeMessage = (type: string, payload: JSONObject = {}) => {
  window.webkit?.messageHandlers?.noteEditorBridge?.postMessage({ type, payload })
}

function isEmptyParagraphNode(node: ProseMirrorNode | null | undefined): boolean {
  return Boolean(node && node.type.name === 'paragraph' && node.childCount === 0)
}

function deleteSourceBlock(editor: Editor, getPos: (() => number) | boolean): boolean {
  if (typeof getPos !== 'function') {
    return false
  }

  const position = getPos()
  const sourceNode = editor.state.doc.nodeAt(position)

  if (!sourceNode || sourceNode.type.name !== 'pageSource') {
    return false
  }

  let from = position
  let to = position + sourceNode.nodeSize

  const before = editor.state.doc.resolve(position).nodeBefore
  if (isEmptyParagraphNode(before)) {
    from -= before.nodeSize
  }

  const after = editor.state.doc.resolve(position + sourceNode.nodeSize).nodeAfter
  if (isEmptyParagraphNode(after)) {
    to += after.nodeSize
  }

  const paragraph = editor.state.schema.nodes.paragraph
  const transaction = editor.state.tr.delete(from, to)

  if (transaction.doc.childCount === 0 && paragraph) {
    transaction.insert(0, paragraph.create())
  }

  const selectionPosition = Math.min(from, transaction.doc.content.size)
  transaction.setSelection(TextSelection.near(transaction.doc.resolve(selectionPosition)))
  editor.view.dispatch(transaction.scrollIntoView())

  return true
}

function applyMarkdownShortcut(editor: Editor, rawTextBefore: string): boolean {
  const { selection } = editor.state

  if (!selection.empty) {
    return false
  }

  const { $from } = selection
  if ($from.parent.type.name !== 'paragraph') {
    return false
  }

  const textBefore = rawTextBefore.trimStart()
  if (!textBefore) {
    return false
  }

  const markerRange = {
    from: $from.start(),
    to: selection.from,
  }

  if (/^#{1,3}$/.test(textBefore)) {
    return editor
      .chain()
      .focus()
      .deleteRange(markerRange)
      .setNode('heading', { level: textBefore.length })
      .run()
  }

  if (/^[-+*]$/.test(textBefore)) {
    return editor.chain().focus().deleteRange(markerRange).toggleBulletList().run()
  }

  if (/^1[.)]$/.test(textBefore)) {
    return editor.chain().focus().deleteRange(markerRange).toggleOrderedList().run()
  }

  if (/^(?:\[\]|\[ \])$/.test(textBefore)) {
    return editor.chain().focus().deleteRange(markerRange).toggleTaskList().run()
  }

  if (textBefore === '>') {
    return editor.chain().focus().deleteRange(markerRange).toggleBlockquote().run()
  }

  if (textBefore === '```' || textBefore === '~~~') {
    return editor.chain().focus().deleteRange(markerRange).toggleCodeBlock().run()
  }

  return false
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
    return ({ editor, getPos, node }) => {
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

      const actions = document.createElement('div')
      actions.className = 'page-source__actions'

      const remove = document.createElement('button')
      remove.type = 'button'
      remove.className = 'page-source__remove'
      remove.textContent = 'Remove'
      remove.setAttribute('aria-label', 'Remove source block')
      const handleRemove = (event: MouseEvent) => {
        event.preventDefault()
        event.stopPropagation()
        deleteSourceBlock(editor, getPos)
      }
      remove.onmousedown = handleRemove
      remove.onclick = handleRemove

      meta.append(link, url)
      actions.append(time, remove)
      dom.append(icon, meta, actions)

      return {
        dom,
        selectNode: () => dom.classList.add('is-selected'),
        deselectNode: () => dom.classList.remove('is-selected'),
      }
    }
  },
})

const slashItems: SlashItem[] = [
  {
    title: 'Text',
    description: 'Switch back to normal text',
    keywords: ['paragraph', 'text', 'body'],
    command: (editor) => editor.chain().focus().setParagraph().run(),
  },
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
    title: 'Heading 3',
    description: 'Compact section heading',
    keywords: ['heading', 'subheading', 'h3'],
    command: (editor) => editor.chain().focus().toggleHeading({ level: 3 }).run(),
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

    const menuWidth = element.offsetWidth || 240
    const menuHeight = element.offsetHeight || 280
    const left = Math.max(12, Math.min(rect.left, window.innerWidth - menuWidth - 12))
    const preferredTop = rect.bottom + 10
    const top = preferredTop + menuHeight <= window.innerHeight - 12
      ? preferredTop
      : Math.max(12, rect.top - menuHeight - 10)

    element.style.left = `${left}px`
    element.style.top = `${top}px`
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
    if (propsRef.items.length === 0) {
      const emptyState = document.createElement('div')
      emptyState.className = 'slash-menu__empty'
      emptyState.textContent = 'No matching blocks'
      element.appendChild(emptyState)
      return
    }

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

      if (propsRef.items.length === 0) {
        if (event.key === 'Escape') {
          remove()
          return true
        }

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

      if (event.key === 'Tab') {
        event.preventDefault()
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
        startOfLine: true,
        allowedPrefixes: null,
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

const MarkdownShortcuts = Extension.create({
  name: 'markdownShortcuts',

  addKeyboardShortcuts() {
    return {
      Space: () => {
        const { selection } = this.editor.state
        const { $from } = selection
        const textBefore = $from.parent.textBetween(0, $from.parentOffset, undefined, '\ufffc')
        return applyMarkdownShortcut(this.editor, textBefore)
      },
    }
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
      placeholder: 'First line becomes the title. Type / for blocks, or use markdown like #, -, [], >, and ```',
    }),
    PageSource,
    MarkdownShortcuts,
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
  },
  onCreate: () => {
    sendBridgeMessage('ready')
  },
})

function setDocument(document: JSONObject | undefined) {
  editor.commands.setContent(
    document ?? {
      type: 'doc',
      content: [{ type: 'paragraph' }],
    },
    false
  )
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
  debugApplyMarkdown(text: string) {
    const triggerText = text.endsWith(' ') ? text.slice(0, -1) : text

    setDocument({
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: triggerText
            ? [
                {
                  type: 'text',
                  text: triggerText,
                },
              ]
            : [],
        },
      ],
    })
    editor.commands.focus('start')
    editor.commands.focus('end')
    const applied = applyMarkdownShortcut(editor, triggerText)
    const document = editor.getJSON() as {
      content?: Array<Record<string, unknown>>
    }
    const firstNode = document.content?.[0] ?? {}
    const attrs = (firstNode.attrs as Record<string, unknown> | undefined) ?? {}

    return {
      applied,
      type: firstNode.type ?? '',
      level: attrs.level ?? 0,
    }
  },
  debugOpenSlashMenu(query: string) {
    setDocument({
      type: 'doc',
      content: [{ type: 'paragraph' }],
    })
    editor.commands.focus('start')
    editor.commands.focus('end')
    if (query.length > 0) {
      editor.commands.insertContent(`/${query}`)
    } else {
      editor.commands.insertContent('/')
    }

    const items = Array.from(document.querySelectorAll('.slash-menu__item strong')).map((element) => {
      return element.textContent ?? ''
    })

    return {
      visible: Boolean(document.querySelector('.slash-menu')),
      itemCount: items.length,
      items,
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
