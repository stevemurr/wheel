<div align="center">

# Wheel

**A browser that thinks with you.**

The macOS browser with an AI copilot, semantic memory, and workspaces built-in.

![macOS](https://img.shields.io/badge/macOS-26+-000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.2+-F05138?logo=swift&logoColor=white)
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

- **Apple Intelligence** — Powered by the on-device language model via FoundationModels. No API keys, no servers, no data leaves your Mac.
- **@mentions** — Pull in multiple tabs or history results
- **Streaming** — Watch responses arrive in real-time
- **Agent Studio** — Build custom agents with system prompts

### Semantic Search
Every page you visit gets embedded locally. Search by concept, not exact text.

- Powered by [VecturaKit](https://github.com/rryam/VecturaKit) for on-device vector search
- Automatic background indexing as you browse
- Category filtering with `@Web`, `@History`, `@ReadingList` mentions
- Fully local — no external server required

### Workspaces
Keep contexts separate. Each workspace has its own tabs, color, and default agent.

### Reading List
Press **Cmd+S** to save any page. Press **Cmd+B** to browse your list. Search within it.

### The Rest
- **Downloads** — Progress tracking, auto-organized
- **Picture-in-Picture** — Float videos (Cmd+Shift+P)
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

**Requirements:** macOS 26+, Apple Silicon, Xcode 26+, Apple Intelligence enabled

---

## Architecture

```
WheelBrowser/
├── OmniBar/          # The unified input system
├── SemanticSearch/   # VecturaKit-powered on-device vector search
├── Letta/            # AI agent integration
├── Shared/LLM/      # Apple FoundationModels integration
├── ModuleSystem/     # Extensible module architecture
├── Workspaces/       # Context management
├── RightClickPanel/  # Quick actions overlay
└── Downloads/        # Download handling
```

All AI features run entirely on-device using Apple Intelligence (FoundationModels) and VecturaKit. No external servers, API keys, or network calls required for AI functionality.

---

<div align="center">

MIT License

</div>
