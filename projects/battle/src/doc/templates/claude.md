# CLAUDE.md - {{project.name}}

This file provides guidance to Claude Code (claude.ai/code) when working with the {{project.name}} codebase.

## Project Overview

**{{project.name}}** - {{project.description}}

**Version**: {{project.version}}  
**License**: {{project.license}}  
**Author**: {{project.author}}  
**Repository**: {{project.repository}}

## Core Development Principles

### Real PTY Testing
Battle uses real pseudo-terminal emulation, not pipes or mocks. This provides authentic terminal environment testing.

### Universal Framework
Replaces Jest, Vitest, and other testing frameworks with PTY-based testing for CLI and TUI applications.

### StarCraft-Style Replay
Every test session is recorded and can be replayed for analysis and debugging.

## Architecture Overview

Battle follows the Class = Directory pattern with TypeScript compilation via @akaoio/builder.

### Core Components

- **Battle**: Main testing class with PTY management
- **PTYManager**: Handles pseudo-terminal operations  
- **TestRunner**: Executes and manages test suites
- **ReplaySystem**: Records and replays test sessions

## Development Guidelines

### Testing Standards

- Use real PTY terminals, never pipes
- Test actual user interactions
- Validate terminal output exactly as users see it
- Record test sessions for replay analysis

### File Structure

```
battle/
├── src/
│   ├── Battle/          # Main class
│   ├── PTYManager/      # PTY operations
│   ├── TestRunner/      # Test execution
│   └── types/           # TypeScript definitions
├── test/                # Test suites
└── docs/                # Documentation
```

### Class = Directory Pattern

```
Battle/
├── index.ts            # Class exports
├── constructor.ts      # Constructor logic
├── start.ts           # start() method
├── stop.ts            # stop() method
├── write.ts           # write() method
└── waitFor.ts         # waitFor() method
```

## Testing Requirements

### Unit Tests

```javascript
// Battle/start.test.ts
import { Battle } from './index.js'

export default async function test() {
  const battle = new Battle({ command: 'echo', args: ['test'] })
  
  await battle.start()
  const output = await battle.waitFor('test')
  
  if (!output) {
    throw new Error('Should capture echo output')
  }
  
  await battle.stop()
}
```

### Integration Tests

Test complete CLI application workflows using Battle itself:

```javascript
export default async function test() {
  const battle = new Battle({ command: 'battle', args: ['run', 'simple.test.js'] })
  
  await battle.start()
  await battle.waitFor('✅ Tests passed')
  
  const exitCode = await battle.getExitCode()
  if (exitCode !== 0) {
    throw new Error('Battle should run tests successfully')
  }
}
```

## Performance Guidelines

- Minimize PTY creation overhead
- Reuse terminals when possible
- Implement proper timeout handling
- Clean up resources promptly

## Anti-Patterns to Avoid

❌ **DON'T**:
- Use pipes instead of PTY
- Mock terminal interactions
- Skip cleanup of PTY resources
- Test without realistic timing

✅ **DO**:
- Use real PTY terminals
- Test actual user workflows
- Clean up all resources
- Use appropriate timeouts

## Notes for AI Assistants

When working on this codebase:

1. **PTY First**: Always use real terminals, never mocks
2. **User Simulation**: Test exactly how users interact
3. **Resource Management**: Always clean up PTY resources
4. **Real Timing**: Use realistic delays and timeouts
5. **Replay Analysis**: Utilize recorded sessions for debugging

---

*This documentation is generated using @akaoio/composer*

*{{project.name}} - Real PTY testing for the modern age*

*Generated with ❤️ by @akaoio/composer*
