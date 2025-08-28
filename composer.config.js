// @akaoio/composer configuration for Access cortex
module.exports = {
  sources: {
    docs: {
      pattern: 'src/doc/**/*.yaml',
      parser: 'yaml'
    }
  },
  build: {
    tasks: []
  },
  outputs: [
    {
      target: 'README.md',
      template: 'templates/readme.md',
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
