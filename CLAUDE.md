# CLAUDE.md - @akaoio/access

This file provides guidance to Claude Code (claude.ai/code) when working with the @akaoio/access codebase.

## Project Overview

**@akaoio/access** - Pure POSIX shell implementation for automatic IP synchronization with multiple DNS providers - The eternal foundation layer for network infrastructure

**Version**: 0.0.3  
**License**: MIT  
**Author**: AKAO Team  
**Repository**: https://github.com/akaoio/access  
**Philosophy**: "While languages come and go, shell is eternal."

## Core Development Principles



## Architecture Overview

### System Design

Access is built as a pure POSIX shell framework for automatic DNS synchronization. It operates as the foundational network layer that ensures connectivity regardless of other system failures.

### Core Components



## Features



## Command Interface

Access provides a comprehensive command-line interface:



## Development Guidelines

### Shell Script Standards

- **POSIX Compliance**: All scripts must be POSIX-compliant
- **No Bashisms**: Avoid bash-specific syntax
- **Error Handling**: Always check return codes
- **Logging**: Use consistent logging format
- **Testing**: Every function must have tests

### File Structure

```
access/
├── access.sh              # Main executable
├── lib/                   # Core library functions
├── modules/               # Provider-specific modules
├── providers/            # DNS provider implementations
├── tests/                # Test suites
└── install.sh            # Installation script
```

### Provider Development

When adding new DNS providers:

1. Create module in `providers/`
2. Implement required functions: `sync`, `validate`, `configure`
3. Add comprehensive tests
4. Update documentation
5. Ensure POSIX compliance

### Testing Requirements

- All functions must have unit tests
- Integration tests for each provider
- POSIX compliance verification
- Cross-platform compatibility testing

## Security Considerations

- Never log API keys or sensitive data
- Use secure defaults for all configurations
- Validate all external inputs
- Implement rate limiting for API calls
- Store credentials securely

## Performance Guidelines

- Minimize external dependencies
- Cache DNS lookups when appropriate
- Batch API calls where possible
- Implement exponential backoff for retries
- Monitor and log performance metrics

## Supported Providers



## Environment Variables



## Common Commands

```bash
# Initialize access
access init

# Configure provider
access config set provider.name.key value

# Start service
access start

# Check status
access status

# Manual sync
access sync

# View logs
access logs

# Health check
access health
```

## Anti-Patterns to Avoid

❌ **DON'T**:
- Use bashisms or non-POSIX syntax
- Hard-code provider credentials
- Skip error handling
- Mix business logic with presentation
- Use external dependencies unnecessarily

✅ **DO**:
- Follow POSIX standards strictly
- Use configuration files for settings
- Implement comprehensive error handling
- Separate concerns clearly
- Keep dependencies minimal

## Notes for AI Assistants

When working on this codebase:

1. **POSIX First**: Always verify POSIX compliance
2. **Zero Dependencies**: Don't add external dependencies
3. **Shell Best Practices**: Follow shell scripting standards
4. **Test Everything**: Add tests for all new functionality
5. **Document Changes**: Update docs for any modifications
6. **Security Focus**: Always consider security implications

## Key Implementation Rules

- **POSIX Compliance**: No bashisms, GNU extensions, or modern shell features
- **Error Handling**: Check return codes and handle failures gracefully
- **Logging**: Use consistent, structured logging
- **Configuration**: Use file-based configuration, not hard-coded values
- **Testing**: Every function needs corresponding tests

---

*This documentation is generated using @akaoio/composer*

* - The eternal foundation that never fails*

*Generated with ❤️ by @akaoio/composer v*