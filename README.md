<div align="center">

# Wheel

**A browser that thinks with you.**

The macOS browser with an AI copilot, semantic memory, and workspaces built-in.

![macOS](https://img.shields.io/badge/macOS-14.0+-000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)

</div>

---

## Why Wheel?

Most browsers treat AI as an afterthought—a sidebar you open sometimes. Wheel makes AI native to how you browse. Ask questions about any page, search your history by meaning, and let agents handle multi-step tasks across tabs.

---

## The OmniBar

One input. Five modes. Press **Tab** to cycle.

| Mode | What it does |
|------|--------------|
| **Search** | URLs, fuzzy history search, open tabs |
| **Chat** | AI assistant with full page context |
| **Semantic** | Find pages by meaning, not keywords |
| **Agent** | Autonomous tasks across your tabs |
| **Reading List** | Save pages for later (Cmd+S) |

The OmniBar floats at the bottom. It expands when focused, collapses when you're browsing.

---

## Features

### AI Chat
Talk to any webpage. Wheel extracts the content and gives the AI full context.

- **@mentions** — Pull in multiple tabs or history results
- **Streaming** — Watch responses arrive in real-time
- **Agent Studio** — Build custom agents with system prompts

### Semantic Search
Every page you visit gets embedded. Search by concept, not exact text.

- Uses sqlite-vec for fast vector search
- Automatic background indexing
- Persists across sessions

### Workspaces
Keep contexts separate. Each workspace has its own tabs, color, and default agent.

### Reading List
Press **Cmd+S** to save any page. Press **Cmd+B** to browse your list. Search within it.

### The Rest
- **Downloads** — Progress tracking, auto-organized
- **Content Blocking** — Built-in ad blocker with category controls
- **Picture-in-Picture** — Float videos (Cmd+Shift+P)
- **Dark Mode** — System-aware or forced
- **Middle-click panel** — Quick tab switching and actions

---

## Shortcuts

**Navigation**
| | |
|--|--|
| `Cmd+L` | Address bar |
| `Cmd+K` | AI chat |
| `Cmd+J` | Semantic search |
| `Cmd+B` | Reading list |
| `Tab` | Next OmniBar mode |

**Tabs**
| | |
|--|--|
| `Cmd+T` | New tab |
| `Cmd+W` | Close tab |
| `Cmd+1-9` | Jump to tab |
| `Cmd+Shift+T` | Reopen closed |

**Actions**
| | |
|--|--|
| `Cmd+S` | Save to reading list |
| `Cmd+F` | Find in page |
| `Cmd+D` | Downloads |
| `Cmd+Shift+P` | Picture-in-Picture |

---

## Install

```bash
git clone https://github.com/stevemurr/wheel.git
cd wheel/WheelBrowser
make install
```

Or run directly:

```bash
swift run WheelBrowser
```

**Requirements:** macOS 14+, Xcode 15+

---

## LLM Setup

Wheel works with any OpenAI-compatible API.

| Provider | Endpoint |
|----------|----------|
| **Ollama** (local) | `http://localhost:11434/v1` |
| **OpenAI** | `https://api.openai.com/v1` |
| **OpenRouter** | `https://openrouter.ai/api/v1` |

Configure in **Settings** → **AI**.

---

## Architecture

```
WheelBrowser/
├── OmniBar/          # The unified input system
├── SemanticSearch/   # sqlite-vec powered search
├── Letta/            # AI agent integration
├── Workspaces/       # Context management
├── RightClickPanel/  # Quick actions overlay
├── Downloads/        # Download handling
└── ContentBlocking/  # Ad blocking
```

---

<div align="center">

MIT License

</div>
