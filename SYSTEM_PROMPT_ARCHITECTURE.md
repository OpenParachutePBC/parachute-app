# System Prompt Architecture: Hierarchical Context for Second Brain

**Date**: November 3, 2025  
**Focus**: Designing root + space-specific system prompts with proper layering

---

## The Core Problem

**User's Insight**:
> "I love the idea of us having a really solid and well defined system prompt in the root directory, and then having space specific system prompts - so then whenever we're thinking in a space, we are operating as a whole second brain but we're also gated into that space"

**The Tension**:
- **Too broad**: Loses space-specific focus, context bleeding across spaces
- **Too gated**: Can't access second brain capabilities, feels disconnected
- **Perfect balance**: Second brain powers + space-specific expertise

**The Interoperability Issue**:
- If we use `AGENTS.md`, Claude Code won't work in same directory
- If we use `CLAUDE.md`, it's not multi-agent friendly
- If we have both, duplicate system prompts (double context)
- Need a solution that works for both use cases

---

## Solution: Hierarchical Context Architecture

### The Layered Model

Research shows AI agents benefit from **hierarchical context layers**:

1. **Meta-Context** - Agent identity, tone, persona
2. **System-Context** - Core capabilities, constraints
3. **Domain-Context** - Space-specific knowledge
4. **Task-Context** - Current conversation/task
5. **Memory-Context** - Historical interactions

**For Parachute**:
```
┌─────────────────────────────────────────┐
│ Global Layer (Root)                     │
│ - Second brain identity                 │
│ - Core capabilities                     │
│ - Cross-space features                  │
└─────────────────────────────────────────┘
               ↓ (inherits)
┌─────────────────────────────────────────┐
│ Space Layer (Space-Specific)            │
│ - Space purpose/expertise               │
│ - Space knowledge ({{note_count}})      │
│ - Space-specific guidelines             │
└─────────────────────────────────────────┘
               ↓ (inherits)
┌─────────────────────────────────────────┐
│ Conversation Layer                      │
│ - Message history                       │
│ - Current task                          │
│ - Active tools                          │
└─────────────────────────────────────────┘
```

### File Structure

**Option 1: CLAUDE.md for Interoperability** 🎯

```
~/Parachute/
├── CLAUDE.md                    # Root system prompt (global)
├── captures/
└── spaces/
    ├── work-projects/
    │   ├── CLAUDE.md            # Space-specific prompt
    │   ├── space.sqlite
    │   └── files/
    │
    └── personal-ideas/
        ├── CLAUDE.md
        ├── space.sqlite
        └── files/
```

**Advantages**:
- ✅ Works with Claude Code extension out of the box
- ✅ Standard filename everyone recognizes
- ✅ Clear hierarchy: root → space
- ✅ No symlink needed
- ✅ No duplicate prompts

**Disadvantages**:
- ❌ "CLAUDE" name implies single agent
- ⚠️ Goose won't auto-load (but we control that anyway)

**Verdict**: **Best for interoperability**

**Option 2: AGENTS.md + Symlink Strategy** 🔗

```
~/Parachute/
├── AGENTS.md                    # Our primary file
├── CLAUDE.md → AGENTS.md        # Symlink for compatibility
├── captures/
└── spaces/
    └── work-projects/
        ├── AGENTS.md
        └── CLAUDE.md → AGENTS.md
```

**Advantages**:
- ✅ Multi-agent friendly naming
- ✅ Works with Claude Code (via symlink)
- ✅ Single source of truth

**Disadvantages**:
- ❌ Symlinks confusing for users
- ❌ Platform compatibility (Windows)
- ❌ Git may not track symlinks well

**Verdict**: **Too complex**

**Option 3: Dual Files with Clear Roles** 📋

```
~/Parachute/
├── CLAUDE.md                    # Root capabilities (for Claude Code)
├── .parachute/
│   └── global-context.md        # Parachute-specific global
├── captures/
└── spaces/
    └── work-projects/
        └── CLAUDE.md            # Space-specific
```

**Advantages**:
- ✅ Claude Code compatibility
- ✅ Parachute has extra config location
- ✅ No duplication

**Disadvantages**:
- ❌ More complex file structure
- ❌ Two places for config

**Verdict**: **Unnecessary complexity**

**Option 4: CLAUDE.md with Frontmatter for Agent Config** ✨

```markdown
---
# Meta-configuration (Parachute reads this, Claude Code ignores)
parachute:
  level: root
  agents:
    claude:
      enabled: true
    goose:
      enabled: true
      provider: anthropic
---

# Parachute Second Brain

You are Parachute, an AI-powered second brain assistant...

## Core Capabilities

- **Cross-Space Knowledge**: You can see connections across all spaces
- **Note Linking**: Help users link related thoughts
- **Knowledge Graph**: Build understanding over time

## Behavior

- Be thoughtful and reflective
- Help users think, don't think for them
- Suggest connections, don't force them

## Available Features

- Voice recording transcription
- Note linking across spaces
- Tag-based organization
- Dynamic context from space knowledge
```

**Advantages**:
- ✅ Single file format
- ✅ Claude Code compatible (ignores frontmatter)
- ✅ Parachute gets extra config
- ✅ Clean, understandable

**Verdict**: **RECOMMENDED** 🎯

---

## Recommended Architecture

### File Structure

```
~/Parachute/
├── CLAUDE.md                              # Root system prompt
│   ├── Frontmatter: Agent config
│   ├── Body: Second brain identity
│   └── Used by: Claude Code, Parachute root
│
├── captures/
│   └── *.md                               # Voice recordings
│
└── spaces/
    ├── work-projects/
    │   ├── CLAUDE.md                      # Space-specific prompt
    │   │   ├── Frontmatter: Space config
    │   │   ├── Body: Work focus
    │   │   └── Inherits: Root context
    │   ├── space.sqlite
    │   └── files/
    │
    └── personal-ideas/
        ├── CLAUDE.md
        │   ├── Frontmatter: Space config
        │   ├── Body: Creative thinking
        │   └── Inherits: Root context
        ├── space.sqlite
        └── files/
```

### Root CLAUDE.md Template

```markdown
---
# Parachute Configuration
parachute:
  version: "1.0"
  level: "root"
  
agents:
  claude:
    enabled: true
    model: "claude-sonnet-4.5-20250514"
  goose:
    enabled: true
    provider: "anthropic"
    model: "claude-sonnet-4.5-20250514"
---

# Parachute: Your Second Brain

You are Parachute, an AI-powered second brain assistant that helps users capture, organize, and connect their thoughts across different areas of life.

## Your Core Identity

- **Role**: Thoughtful thinking partner and knowledge organizer
- **Purpose**: Help users build a interconnected knowledge system
- **Approach**: Guide thinking, don't replace it

## Core Capabilities

### 1. Cross-Space Knowledge 🌐
- You can see connections across all spaces (work, personal, learning, etc.)
- Help users discover unexpected links between ideas
- Suggest when thoughts from different spaces might be related

### 2. Note Linking & Knowledge Graph 🔗
- Link related notes based on content and context
- Build understanding over time through space.sqlite knowledge graphs
- Track which notes appear in multiple spaces (cross-pollination)

### 3. Context-Aware Assistance 🧠
- Understand the current space's purpose and focus
- Use space-specific knowledge: {{note_count}} notes, {{recent_tags}}
- Reference past conversations and linked notes

### 4. Voice Recording Support 🎤
- Work with transcribed voice recordings
- Help extract key insights from captures
- Suggest which spaces a recording should be linked to

## Behavioral Guidelines

### Be Thoughtful
- Take time to understand the user's question deeply
- Consider context from linked notes and space knowledge
- Think about connections across spaces

### Enhance, Don't Replace
- Help users think better, don't think for them
- Ask clarifying questions when needed
- Suggest, don't dictate

### Respect Space Boundaries
- Each space has its own purpose and context
- Use space-specific prompts to guide behavior
- But remember you can reference knowledge across spaces

### Build Understanding Over Time
- Remember patterns from past conversations (via space.sqlite)
- Track which topics come up frequently
- Notice when new insights connect to old knowledge

## Available Data & Context

When in a space, you have access to:
- Space name and purpose (from space CLAUDE.md)
- Linked notes: {{note_count}}
- Recent topics: {{recent_tags}}
- Notes by tag: {{notes_tagged:TAG}}
- Recent activity: {{recent_notes}}

When at root level (no specific space):
- All spaces and their purposes
- Cross-space connections
- Global organization structure

## Technical Context

- User's vault: ~/Parachute/
- Captures folder: ~/Parachute/captures/
- Spaces folder: ~/Parachute/spaces/
- Each space has: CLAUDE.md, space.sqlite, files/
- Same note can appear in multiple spaces with different context

## Response Style

- **Tone**: Thoughtful, curious, supportive
- **Length**: Concise but complete - respect the user's time
- **Structure**: Use markdown, headings, lists for clarity
- **Examples**: Show, don't just tell
- **Questions**: Ask good questions to understand context

---

*This is your base context. When working in a specific space, you'll receive additional instructions from that space's CLAUDE.md that will refine your focus and expertise.*
```

### Space-Specific CLAUDE.md Template

```markdown
---
# Work Projects Space Configuration
parachute:
  version: "1.0"
  level: "space"
  inherits: "root"
  
space:
  name: "Work Projects"
  purpose: "Software engineering project management"
  default_agent: "claude"
  
agents:
  claude:
    mode: "code"
---

# Work Projects Management

**You are now operating within the Work Projects space.**

## Space Purpose

This space tracks all software engineering projects, technical discussions, architecture decisions, and development work.

## Your Role in This Space

- **Primary Role**: Technical Project Manager & Engineering Advisor
- **Expertise**: Backend development, API design, database optimization
- **Focus**: Help prioritize work, track progress, make technical decisions

## Space-Specific Behavior

### Prioritization
- Consider customer impact first
- Balance urgency vs. technical debt
- Reference past discussions (check {{notes_tagged:meeting}})

### Technical Decisions
- Prefer pragmatic solutions over perfect ones
- Consider maintainability and team velocity
- Reference architecture discussions ({{notes_tagged:architecture}})

### Communication Style
- Be direct and action-oriented
- Suggest concrete next steps
- Break down complex problems

## Available Knowledge in This Space

- **Linked Notes**: {{note_count}} work discussions and meeting notes
- **Recent Topics**: {{recent_tags}}
- **Active Work**: 
  - Meeting notes: {{notes_tagged:meeting}}
  - Bug reports: {{notes_tagged:bug}}
  - Feature discussions: {{notes_tagged:feature}}
  - Architecture decisions: {{notes_tagged:architecture}}

## Common Tasks

### 1. "What should I work on today?"
- Review recent meeting notes for commitments
- Check bug reports for urgent issues
- Consider customer feedback
- Suggest prioritized list with reasoning

### 2. "How did we decide on X?"
- Search notes tagged with relevant topics
- Reference architecture discussions
- Link to specific past conversations

### 3. "Should we use technology Y?"
- Consider team expertise
- Evaluate project constraints
- Reference similar past decisions
- Suggest pragmatic path forward

## Cross-Space Connections

While focused on work, you can still:
- Reference learning notes (if user is studying relevant tech)
- Connect work challenges to personal insights
- Suggest moving ideas to other spaces when appropriate

---

*Remember: You inherit all capabilities from the root Parachute prompt, but within this space, you're focused on software engineering project management.*
```

---

## The Inheritance Model

### How It Works in Code

```go
func (h *MessageHandler) buildSystemPrompt(spaceObj *space.Space) string {
    var prompt strings.Builder
    
    // 1. Read root CLAUDE.md
    rootMD, _ := readFile("~/Parachute/CLAUDE.md")
    rootParsed := parseMarkdownWithFrontmatter(rootMD)
    
    // 2. Read space CLAUDE.md
    spaceMD, _ := readFile(spaceObj.Path + "/CLAUDE.md")
    spaceParsed := parseMarkdownWithFrontmatter(spaceMD)
    
    // 3. Build layered prompt
    if spaceParsed.Inherits == "root" {
        // Include root capabilities
        prompt.WriteString("# Core Context (Root Level)\n\n")
        prompt.WriteString(rootParsed.Body)
        prompt.WriteString("\n\n---\n\n")
    }
    
    // 4. Add space-specific context
    prompt.WriteString("# Space Context\n\n")
    prompt.WriteString(spaceParsed.Body)
    
    // 5. Resolve variables
    resolved := h.contextService.ResolveVariables(prompt.String(), spaceObj.Path)
    
    return resolved
}
```

### Prompt Assembly

**Final prompt sent to Claude**:
```
# Core Context (Root Level)

You are Parachute, an AI-powered second brain assistant...
[Full root CLAUDE.md]

---

# Space Context

You are now operating within the Work Projects space.
[Full space CLAUDE.md with {{variables}} resolved]

Available Knowledge in This Space:
- Linked Notes: 15 work discussions and meeting notes
- Recent Topics: backend, api, bug-fix, architecture, meeting
- Meeting notes: 8
- Bug reports: 3

---

# User Message

[User's actual question]
```

**Result**: 
- ✅ Full second brain capabilities (from root)
- ✅ Space-specific focus (from space)
- ✅ Dynamic context (from space.sqlite)
- ✅ No duplication (single assembly)

---

## The Balance: Gated vs. Global

### Achieving the Right Balance

**The Goal**:
> "operating as a whole second brain but we're also gated into that space"

**How We Achieve This**:

1. **Root Level Establishes Identity**
   - "You are Parachute, a second brain"
   - Core capabilities always available
   - Cross-space awareness

2. **Space Level Adds Focus**
   - "You are now in Work Projects space"
   - Specific expertise and behavior
   - Space knowledge prioritized

3. **Explicit Cross-Space Permission**
   ```markdown
   ## Cross-Space Connections
   
   While focused on work, you can still:
   - Reference learning notes (if relevant)
   - Connect work challenges to personal insights
   - Suggest moving ideas to other spaces
   ```

4. **Attention Budget Management**
   - Space context is "foreground"
   - Root context is "background"
   - Cross-space is "on request"

### Example Behavior

**User in Work Projects space asks**: *"How do I fix this API bug?"*

**Claude's Internal Process**:
```
1. Root context: "I'm Parachute, a second brain"
2. Space context: "I'm in Work Projects, focus on engineering"
3. Space knowledge: "15 notes, recent topics: backend, api, bug"
4. Relevant notes: Check {{notes_tagged:bug}}
5. Response: Engineering-focused, references past discussions
```

**User asks**: *"This reminds me of something... what was it?"*

**Claude's Internal Process**:
```
1. Space context: "Focused on Work Projects"
2. Root context: "I can see across spaces"
3. Cross-space permission: "Suggest connections"
4. Search: Check work notes, then learning journal, then ideas
5. Response: "In your Learning Journal, you noted a similar pattern..."
```

**The Balance**:
- Default: Space-focused (gated)
- When needed: Cross-space aware (global)
- Always: Second brain identity

---

## Preventing Double System Prompts

### The Problem

If user opens `~/Parachute/` in VS Code with Claude Code:

**Claude Code Sends**:
```
System Prompt: [Built-in Claude Code prompt]
User Message: [Auto-includes CLAUDE.md from ~/Parachute/CLAUDE.md]
```

**Parachute Sends**:
```
User Message: [CLAUDE.md from ~/Parachute/CLAUDE.md] + user question
```

**Result**: Same content twice!

### The Solution: Detection & Deduplication

**Option 1: Check if Claude Code is in use** ❌
- Can't reliably detect
- User might use both

**Option 2: Design CLAUDE.md to work both ways** ✅

```markdown
# Parachute Second Brain

<!-- 
If you're seeing this as part of Claude Code's automatic context:
This is intentional. This prompt defines Parachute's second brain capabilities.

If you're seeing this prepended to a user message:
This is Parachute's system providing context for a space-specific conversation.

Either way, follow the instructions below.
-->

You are Parachute, an AI-powered second brain assistant...
```

**Option 3: Use frontmatter to signal intent** ✅

```markdown
---
parachute:
  mode: "standalone"  # or "embedded"
---
```

**Parachute Code**:
```go
func (h *MessageHandler) shouldIncludeRootContext() bool {
    // If using Claude Code via ACP, it already loaded CLAUDE.md
    // Don't include it again
    
    // If using Goose or direct ACP, include it
    return h.agentType != "claude-code-with-auto-context"
}
```

**Option 4: Idempotent Prompts** 🎯 **BEST**

Design prompts so that including them twice doesn't hurt:

```markdown
# Parachute Second Brain

## Core Identity
You are Parachute, a second brain assistant.

## Capabilities
- Note linking
- Knowledge graphs
- Cross-space awareness

## Current Context
[This section only filled by Parachute when active]
```

If seen twice:
- Core identity: Same message = reinforcement
- Capabilities: Same message = reinforcement  
- Current context: Only filled once (by Parachute)

**Result**: No harm if duplicated!

---

## Implementation Strategy

### Phase 1: Root + Space CLAUDE.md

**Files**:
```
~/Parachute/CLAUDE.md                    # Root context
~/Parachute/spaces/*/CLAUDE.md          # Space context
```

**Code**:
```go
func (h *MessageHandler) buildPrompt(spaceObj *space.Space, userMsg string) string {
    // Read root
    rootMD := readCLAUDEMD("~/Parachute/CLAUDE.md")
    rootParsed := parseFrontmatter(rootMD)
    
    // Read space
    spaceMD := readCLAUDEMD(spaceObj.Path + "/CLAUDE.md")
    spaceParsed := parseFrontmatter(spaceMD)
    
    // Assemble
    prompt := rootParsed.Body
    if spaceParsed.Inherits == "root" {
        prompt += "\n\n---\n\n" + spaceParsed.Body
    }
    
    // Resolve variables
    resolved := resolveVariables(prompt, spaceObj.Path)
    
    // Prepend to user message
    return resolved + "\n\n---\n\n" + userMsg
}
```

### Phase 2: Frontmatter Parsing

```go
type FrontmatterMD struct {
    Frontmatter map[string]interface{}
    Body        string
    Inherits    string  // "root" or ""
    Level       string  // "root" or "space"
}

func parseFrontmatter(content string) *FrontmatterMD {
    // Parse YAML frontmatter
    // Extract body
    // Return structured data
}
```

### Phase 3: Template Library

**Built-in Templates**:

1. **Root Context Template**
   - Second brain identity
   - Core capabilities
   - Behavioral guidelines

2. **Space Templates**:
   - Work Projects (engineering focus)
   - Learning Journal (reflection focus)
   - Personal Ideas (creative focus)
   - Meeting Notes (organization focus)
   - Research (analysis focus)

**UI**:
```
┌─ Create New Space ──────────────────────┐
│                                         │
│ Name: [My Space________]                │
│                                         │
│ Template: [Work Projects ▼]            │
│                                         │
│ ○ Work Projects                         │
│   Engineering project management        │
│                                         │
│ ○ Learning Journal                      │
│   Reflection and knowledge building     │
│                                         │
│ ○ Personal Ideas                        │
│   Creative thinking and brainstorming   │
│                                         │
│ ○ Custom (blank)                        │
│   Start from scratch                    │
│                                         │
│ [Preview] [Create]                      │
└─────────────────────────────────────────┘
```

---

## Best Practices for Users

### Writing Root CLAUDE.md

**Do**:
- ✅ Define second brain identity
- ✅ List core capabilities
- ✅ Set behavioral guidelines
- ✅ Explain cross-space features
- ✅ Be foundational, not task-specific

**Don't**:
- ❌ Include space-specific instructions
- ❌ Reference specific projects
- ❌ Write task procedures
- ❌ Be too long (attention budget!)

**Length**: 200-400 words ideal

### Writing Space CLAUDE.md

**Do**:
- ✅ Define space purpose clearly
- ✅ Specify expertise/focus area
- ✅ Include space-specific behavior
- ✅ Use {{variables}} for dynamic context
- ✅ Inherit from root explicitly

**Don't**:
- ❌ Repeat root capabilities
- ❌ Contradict root guidelines
- ❌ Ignore cross-space connections
- ❌ Be too narrow (allow flexibility)

**Length**: 150-300 words ideal

### Example Balance

**Too Gated** ❌:
```markdown
# Work Projects

You ONLY help with work.
Never mention other topics.
Stay focused on code.
```
*Problem*: Loses second brain benefits, can't make connections

**Too Global** ❌:
```markdown
# Work Projects

Help with anything!
Work, personal, ideas, whatever!
```
*Problem*: No focus, loses space-specific expertise

**Just Right** ✅:
```markdown
# Work Projects

Primary focus: Software engineering project management.

While focused on work, you can:
- Reference relevant learning notes
- Connect work challenges to insights from other spaces
- Suggest when an idea belongs in a different space

Default to work context, but enable cross-pollination when valuable.
```

---

## Conclusion

### The Architecture Decision

**Recommendation**: Use `CLAUDE.md` for both root and space levels

**Reasoning**:
1. ✅ **Interoperability**: Works with Claude Code extension
2. ✅ **Clarity**: Everyone knows what CLAUDE.md is
3. ✅ **Simplicity**: One standard, two levels
4. ✅ **Hierarchy**: Root → Space inheritance clear
5. ✅ **No Duplication**: Proper assembly prevents doubling

**Tradeoff Accepted**:
- ⚠️ "CLAUDE" name implies single agent
- ✅ But we control reading/assembly anyway
- ✅ Frontmatter adds multi-agent config
- ✅ Users can use Claude Code in same directory

### The Balance Solution

**Root CLAUDE.md**:
- Second brain identity (foundational)
- Core capabilities (always available)
- Cross-space awareness (background)

**Space CLAUDE.md**:
- Space purpose (foreground)
- Specific expertise (focused)
- Space knowledge ({{variables}})
- Explicit cross-space permission (controlled)

**Result**:
> "operating as a whole second brain but also gated into that space"

Achieved! ✅

---

**Researched by**: Claude Code Agent  
**Status**: Architecture designed ✅
