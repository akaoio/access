# {{project.name}}

{{project.description}}

> {{project.philosophy}}

**Version**: {{project.version}}  
**License**: {{project.license}}  
**Repository**: {{project.repository}}

## Overview

{{architecture.overview}}

## Core Principles

{{#each core_principles}}

### {{title}}
{{description}}

{{/each}}

## Features

{{#each features}}
- **{{name}}**: {{description}}
{{/each}}

## Installation

### Quick Start

```bash
# Clone and setup
git clone {{project.repository}}.git
cd access
chmod +x access.sh

# Run directly
./access.sh ip

# Or install globally
sudo cp access.sh /usr/local/bin/access
access help
```

### System Integration

```bash
# Setup as systemd service
./access.sh daemon --setup

# Or add to crontab
crontab -e
# Add: */5 * * * * /usr/local/bin/access update
```

## Usage

### Basic Commands

```bash
# Check current IP
access ip

# Update DNS with current IP
access update

# Configure provider
access config cloudflare
access config set domain example.com
access config set host @

# Run daemon
access daemon

# Check all providers
access providers

# Check provider health
access health
```

## Provider Support

### Cloud Providers
{{#each providers.cloud}}
#### {{name}}
- **Description**: {{description}}
- **Requirement**: {{requirement}}
- **Status**: {{status}}

{{/each}}

### Traditional Providers
{{#each providers.traditional}}
#### {{name}}
- **Description**: {{description}}
- **Requirement**: {{requirement}}  
- **Status**: {{status}}

{{/each}}

## IP Detection Methods

### {{detection_methods.tier1.name}}
{{detection_methods.tier1.description}}
- **Response Time**: {{detection_methods.tier1.response_time}}

### {{detection_methods.tier2.name}}
{{#each detection_methods.tier2.services}}
- {{this}}
{{/each}}

### Validation
{{detection_methods.validation.description}}

## Security

### Credential Security
{{#each security.credential_security}}
- {{this}}
{{/each}}

### Network Security
{{#each security.network_security}}
- {{this}}
{{/each}}

### System Security
{{#each security.system_security}}
- {{this}}
{{/each}}

## Why Access?

{{why_access.description}}

**{{why_access.key_point}}**

### Benefits
{{#each why_access.benefits}}
- {{this}}
{{/each}}

## Architecture

{{#each architecture.components}}
### {{name}}
{{description}}
- **Responsibility**: {{responsibility}}

{{/each}}

### System Layers

{{#each architecture.layers}}
#### {{name}}
{{description}}

{{#if commands}}
**Commands**: {{#each commands}}{{this}}{{#unless @last}}, {{/unless}}{{/each}}
{{/if}}

**Capability**: {{capability}}

{{/each}}

---

*{{project.tagline}}*

*Version: {{project.version}} | License: {{project.license}} | Author: {{project.author}}*
