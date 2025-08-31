// @akaoio/composer configuration for Access cortex
module.exports = {
  sources: {
    // Map specific atoms to proper data structure that templates expect
    project: {
      pattern: 'src/doc/educational-overview.yaml',
      parser: 'yaml'
    },
    commands: {
      pattern: 'src/doc/commands.yaml',
      parser: 'yaml'
    },
    // Include rich educational content from workspace atoms
    educational: {
      pattern: '../../docs/atoms/project-overview.yaml',
      parser: 'yaml'
    }
  },
  build: {
    tasks: []
  },
  outputs: [
    {
      target: 'README.md',
      template: 'templates/educational-readme.md',
      data: 'docs'
    },
    {
      target: 'CLAUDE.md',
      template: 'templates/claude.md',
      data: 'docs'
    },
    {
      target: 'API.md',
      template: 'templates/api.md',
      data: 'docs'
    },
    {
      target: 'PROVIDERS.md',
      template: 'templates/providers.md',
      data: 'docs'
    }
  ],
  options: {
    baseDir: process.cwd()
  }
}
