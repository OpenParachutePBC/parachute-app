# Parachute

> "The mind is like a parachute, it doesn't work if it's not open" — Frank Zappa

**Your open, interoperable second brain powered by Claude AI**

[![Backend CI](https://github.com/ParachuteLabs/parachute/actions/workflows/backend-ci.yml/badge.svg)](https://github.com/ParachuteLabs/parachute/actions/workflows/backend-ci.yml)
[![Frontend CI](https://github.com/ParachuteLabs/parachute/actions/workflows/frontend-ci.yml/badge.svg)](https://github.com/ParachuteLabs/parachute/actions/workflows/frontend-ci.yml)
[![codecov](https://codecov.io/gh/ParachuteLabs/parachute/branch/main/graph/badge.svg)](https://codecov.io/gh/ParachuteLabs/parachute)

---

## What is Parachute?

Parachute is a cross-platform application that makes the Agent Client Protocol (ACP) as accessible as Claude Desktop, but with the power of local file access, MCP servers, and true multi-platform availability. It also includes integrated voice recording capabilities with AI transcription.

### Core Features

**AI Chat with Spaces**
Each **Space** is a cognitive context - a room in your digital memory palace:

- Has its own `CLAUDE.md` file (persistent AI memory)
- Contains relevant files and resources
- Independent conversation history
- Optional MCP server configurations
- Works across all your devices

**Voice Recorder**
Capture thoughts and conversations effortlessly:

- Local microphone recording
- Omi device integration (Bluetooth pendant)
- AI transcription (local Whisper models)
- Gemma 2B model for intelligent title generation
- Recording management and playback
- Transcript viewing and editing

**Vault-Based File System**
Your data, your way:

- Configurable vault location (default: `~/Parachute/`)
- Works with Obsidian, Logseq, and other markdown vaults
- Customizable subfolder names (`captures/`, `spaces/`)
- Platform-specific storage (macOS, Android, iOS)
- All data local and portable
- No lock-in, standard formats

### Built on Openness

1. **Open Protocols** - Built on ACP & MCP (not proprietary)
2. **Open Data** - Your files, your control, standard formats
3. **Open Platforms** - iOS, Android, Web, Desktop
4. **Open Integration** - Connect to anything via MCP servers

---

## Technology Stack

- **Backend:** Go 1.25+ (Fiber web framework, SQLite database)
- **Frontend:** Flutter 3.24+ (iOS, Android, Web, Desktop)
- **AI Integration:** Agent Client Protocol (ACP) via claude-code-acp
- **Extensibility:** Model Context Protocol (MCP)

---

## Project Structure

```
parachute/
├── backend/          # Go backend service (REST API + WebSocket)
├── app/             # Flutter frontend (cross-platform UI)
├── docs/            # Shared documentation
├── scripts/         # Development and deployment scripts
└── README.md        # This file
```

---

## Quick Start

### Prerequisites

- Go 1.25+
- Flutter 3.24+
- Node.js 18+ (for claude-code-acp)

### Backend

```bash
cd backend
go run cmd/server/main.go
```

Backend runs on http://localhost:8080

### Frontend (Flutter App)

```bash
cd app
flutter run -d macos  # or ios, chrome, etc.
```

The app includes three main features accessible via bottom navigation:

- **Recorder** - Voice recording with AI transcription and title generation (default screen)
- **Spaces** - AI conversations with Claude in organized spaces
- **Files** - Browse and preview files in your vault

---

## Documentation

- **[Architecture](ARCHITECTURE.md)** - System design and technical decisions
- **[API Documentation](http://localhost:8080/api/docs)** - Interactive REST API documentation (Swagger UI)
- **[Branding](docs/BRANDING.md)** - Brand identity and philosophy
- **[Launch Guide](docs/LAUNCH-GUIDE.md)** - Comprehensive implementation guide
- **[Setup Guide](docs/SETUP.md)** - Environment setup instructions
- **[Development Workflow](docs/DEVELOPMENT-WORKFLOW.md)** - Day-to-day development
- **[Roadmap](docs/ROADMAP.md)** - Implementation phases and progress

### Component Documentation

- **Backend:** See `backend/CLAUDE.md` and `backend/dev-docs/`
- **Frontend:** See `app/CLAUDE.md` and `app/dev-docs/`

---

## Current Status

🚀 **Active Development** - Local-First Alpha with Complete Recorder

Core functionality is working with full local-first architecture. All recorder features complete!

**Recently Completed (Nov 13, 2025):**

**Recording Features:**

- [x] **Auto-pause voice recording** - VAD-based silence detection (hands-free journaling)
- [x] **Noise suppression** - OS-level suppression + high-pass filter
- [x] **Context field with voice input** - Record → transcribe → insert
- [x] **Background transcription** - Continues even when app backgrounded
- [x] **Incomplete transcription recovery** - Detect and resume interrupted transcriptions
- [x] **Immediate persistence** - No data loss on exit
- [x] **Custom app icon** - Yellow parachute design on all platforms
- [x] **Android stability** - Permissions and ProGuard fixes

**Sync & Infrastructure:**

- [x] **Git-based sync** - Multi-device synchronization via GitHub
- [x] **Auto-sync** - Automatic commits after save/update/delete
- [x] **Manual sync** - UI indicator with file counts
- [x] **Periodic sync** - Background sync every 5 minutes
- [x] **Settings persistence** - Git configuration saved across restarts
- [x] **Local-first architecture** - Complete removal of backend dependencies for recordings

**Core Features Complete:**

- [x] Voice recorder with Omi device support
- [x] Local AI transcription (Whisper models)
- [x] Gemma 2B title generation with HuggingFace integration
- [x] Vault-based architecture with configurable location
- [x] Obsidian/Logseq compatibility
- [x] File browser with markdown preview
- [x] 4-step onboarding flow
- [x] ACP integration with Claude AI
- [x] WebSocket streaming conversations

**Next Steps:**

- [ ] Space SQLite Knowledge System - Link captures to spaces with structured metadata

See [ROADMAP.md](ROADMAP.md) for detailed progress and future plans.

---

## Target Users

**Primary:**

- Knowledge workers organizing information
- Researchers managing sources and notes
- Writers working on multiple projects
- Consultants managing client contexts

**Future:**

- Developers (complementary to IDE)
- Teams and organizations

---

## Why Parachute?

| Feature                 | Parachute    | Claude Desktop | Claude Code | Zed |
| ----------------------- | ------------ | -------------- | ----------- | --- |
| **Mobile Access**       | ✅           | ❌             | ❌          | ❌  |
| **File Access**         | ✅           | ❌             | ✅          | ✅  |
| **MCP Servers**         | ✅           | ❌             | ✅          | ✅  |
| **Spaces/Context**      | ✅           | ❌             | ⚠️          | ⚠️  |
| **Open Protocol**       | ✅           | ❌             | ✅          | ✅  |
| **Vault Integration**   | ✅           | ❌             | ❌          | ❌  |
| **Voice Recording**     | ✅           | ❌             | ❌          | ❌  |
| **Obsidian Compatible** | ✅           | ❌             | ❌          | ❌  |
| **Git Sync**            | ✅           | ❌             | ❌          | ❌  |
| **Use Case**            | Second brain | Chat           | Coding      | IDE |

**Our Niche:** The only open, cross-platform second brain for Claude AI that works with your existing knowledge vault

---

## Contributing

This is currently a personal project in early development. Once we reach MVP, we'll open up for contributions.

---

## License

TBD - Will be decided before public release

---

## Attribution

Parachute uses the following open models and technologies:

### Google Gemma

Gemma models for on-device AI title generation are used under the [Gemma Terms of Use](https://ai.google.dev/gemma/terms).

- **Model:** Gemma 3 1B Instruction-Tuned (INT4 quantized)
- **Provider:** Google DeepMind
- **License:** [Gemma Terms of Use](https://ai.google.dev/gemma/terms) (allows commercial use and redistribution)
- **Source:** Originally from [litert-community/Gemma3-1B-IT](https://huggingface.co/litert-community/Gemma3-1B-IT)
- **Hosting:** Hosted on Parachute CDN for easy download (no account required)

**Citation:**

> Gemma Team, Google DeepMind. "Gemma: Open Models Based on Gemini Research and Technology." 2024. https://ai.google.dev/gemma

### OpenAI Whisper

Whisper models for speech-to-text transcription are used under the MIT License.

- **Provider:** OpenAI
- **License:** MIT
- **Source:** https://github.com/openai/whisper

---

## Contact

Questions? Ideas? Reach out: [contact info TBD]

---

**Status:** Active Development (Alpha) - Last Updated: November 20, 2025
