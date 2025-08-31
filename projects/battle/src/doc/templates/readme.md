# {{project.name}}

{{project.description}}

> {{project.tagline}}

**Version**: {{project.version}}  
**License**: {{project.license}}  
**Repository**: {{project.repository}}

## Overview

Battle is the universal terminal testing framework that replaces Jest, Vitest, and all traditional testing frameworks. It uses real PTY (Pseudo-Terminal) emulation to test applications exactly as users interact with them.

## Installation

```bash
npm install @akaoio/battle
```

## Quick Start

```javascript
import { Battle } from '@akaoio/battle'

export default async function test() {
  const battle = new Battle({
    command: 'node',
    args: ['app.js']
  })
  
  await battle.start()
  await battle.write('hello\n')
  
  const output = await battle.waitFor('Hello')
  if (!output) {
    throw new Error('Expected output not found')
  }
  
  await battle.stop()
}
```

## API Reference

### Battle Class

#### Constructor
```javascript
new Battle(options)
```

#### Methods

##### `start(): Promise<void>`
Start the application in PTY.

##### `stop(): Promise<void>`  
Stop the application and cleanup.

##### `write(data: string): Promise<void>`
Send input to the application.

##### `waitFor(pattern: string | RegExp): Promise<string>`
Wait for specific output pattern.

## CLI Commands

```bash
battle run      # Run all tests
battle watch    # Watch mode
```

---

*{{project.name}} - {{project.tagline}}*

*Built with ❤️ by AKAO.IO*
