#!/usr/bin/env node
/**
 * VISUAL & UX Battle Test for Access
 * Tests terminal UI, colors, formatting, user experience
 * Uses PTY to capture actual terminal output with colors
 */

const pty = require('node-pty');
// Simple strip ANSI implementation
function stripAnsi(str) {
    return str.replace(/\x1b\[[0-9;]*m/g, '');
}
const fs = require('fs').promises;
const path = require('path');
const os = require('os');

// ANSI color codes for detection
const ANSI = {
    RED: '\x1b[0;31m',
    GREEN: '\x1b[0;32m',
    YELLOW: '\x1b[1;33m',
    BLUE: '\x1b[0;34m',
    BOLD: '\x1b[1m',
    RESET: '\x1b[0m',
    CLEAR: '\x1b[2J',
};

// Test configuration
const TEST_CONFIG = {
    accessPath: path.join(__dirname, 'access.sh'),
    installerPath: path.join(__dirname, 'install.sh'),
    uninstallerPath: path.join(__dirname, 'uninstall.sh'),
    testHome: path.join(os.tmpdir(), 'access_visual_test_' + Date.now()),
    width: 80,
    height: 24
};

// PTY helper
function runInPTY(command, args = [], options = {}) {
    return new Promise((resolve, reject) => {
        const env = {
            ...process.env,
            HOME: TEST_CONFIG.testHome,
            ACCESS_HOME: path.join(TEST_CONFIG.testHome, '.access'),
            TERM: 'xterm-256color',
            FORCE_COLOR: '1',
            ...options.env
        };

        const ptyProcess = pty.spawn(command, args, {
            name: 'xterm-256color',
            cols: options.cols || TEST_CONFIG.width,
            rows: options.rows || TEST_CONFIG.height,
            cwd: options.cwd || __dirname,
            env
        });

        let output = '';
        let cleanOutput = '';
        
        ptyProcess.on('data', (data) => {
            output += data;
            cleanOutput += stripAnsi(data);
        });

        // Send input if provided
        if (options.input) {
            setTimeout(() => {
                for (const line of options.input) {
                    ptyProcess.write(line + '\r');
                }
            }, 100);
        }

        // Auto-kill after timeout
        const timeout = setTimeout(() => {
            ptyProcess.kill();
        }, options.timeout || 3000);

        ptyProcess.on('exit', (code) => {
            clearTimeout(timeout);
            resolve({ 
                output, 
                cleanOutput, 
                code,
                hasColors: output !== cleanOutput,
                lines: cleanOutput.split('\n')
            });
        });

        ptyProcess.on('error', reject);
    });
}

// Visual test framework
class VisualBattleTest {
    constructor() {
        this.tests = [];
        this.results = {
            passed: 0,
            failed: 0,
            warnings: 0
        };
        this.issues = [];
    }

    test(category, name, fn) {
        this.tests.push({ category, name, fn });
    }

    async run() {
        console.log('\n🎨 VISUAL & UX BATTLE TEST FOR ACCESS');
        console.log('=' .repeat(60));
        console.log('Testing terminal UI, colors, formatting, and user experience\n');

        const categories = {};
        
        for (const test of this.tests) {
            if (!categories[test.category]) {
                categories[test.category] = [];
            }
            categories[test.category].push(test);
        }

        for (const [category, tests] of Object.entries(categories)) {
            console.log(`\n📦 ${category}`);
            console.log('-'.repeat(40));
            
            for (const test of tests) {
                try {
                    const result = await test.fn();
                    if (result === 'warning') {
                        this.results.warnings++;
                        console.log(`  ⚠️  ${test.name}`);
                    } else {
                        this.results.passed++;
                        console.log(`  ✅ ${test.name}`);
                    }
                } catch (error) {
                    this.results.failed++;
                    this.issues.push({
                        category,
                        test: test.name,
                        error: error.message
                    });
                    console.log(`  ❌ ${test.name}`);
                    console.log(`     ${error.message}`);
                }
            }
        }

        // Summary
        console.log('\n' + '='.repeat(60));
        console.log('📊 VISUAL/UX TEST SUMMARY');
        console.log('-'.repeat(60));
        console.log(`✅ Passed: ${this.results.passed}`);
        console.log(`⚠️  Warnings: ${this.results.warnings}`);
        console.log(`❌ Failed: ${this.results.failed}`);
        
        if (this.issues.length > 0) {
            console.log('\n❌ Issues Found:');
            for (const issue of this.issues) {
                console.log(`   [${issue.category}] ${issue.test}:`);
                console.log(`     ${issue.error}`);
            }
        }

        return this.results.failed === 0;
    }
}

// Setup test environment
async function setupTestEnvironment() {
    await fs.mkdir(TEST_CONFIG.testHome, { recursive: true });
    await fs.mkdir(path.join(TEST_CONFIG.testHome, '.access'), { recursive: true });
}

async function cleanupTestEnvironment() {
    try {
        await fs.rm(TEST_CONFIG.testHome, { recursive: true, force: true });
    } catch (e) {
        // Ignore
    }
}

// Create test suite
const suite = new VisualBattleTest();

// ============================================================================
// COLOR & FORMATTING TESTS
// ============================================================================

suite.test('Colors & Formatting', 'Terminal colors are used', async () => {
    const result = await runInPTY('sh', ['install.sh', '--help']);
    
    if (!result.hasColors) {
        throw new Error('No colors detected in output');
    }
    
    // Check for specific colors
    if (!result.output.includes(ANSI.GREEN)) {
        throw new Error('Green color not used (success indicator)');
    }
});

suite.test('Colors & Formatting', 'Error messages use red color', async () => {
    const result = await runInPTY('sh', ['access.sh', 'update']);
    
    // Should have error in red
    if (result.cleanOutput.includes('ERROR') && !result.output.includes(ANSI.RED)) {
        throw new Error('Error messages not in red');
    }
});

suite.test('Colors & Formatting', 'Warnings use yellow color', async () => {
    // Try to trigger a warning
    const result = await runInPTY('sh', ['install.sh', '--unknown-option']);
    
    if (result.cleanOutput.includes('Warning') && !result.output.includes(ANSI.YELLOW)) {
        return 'warning'; // Warning: warnings might not use yellow
    }
});

suite.test('Colors & Formatting', 'Success indicators use green', async () => {
    const result = await runInPTY('sh', ['access.sh', 'ip']);
    
    // Check for success markers
    if (result.cleanOutput.includes('Detected') && !result.output.includes(ANSI.GREEN)) {
        return 'warning'; // Some success messages might not be colored
    }
});

// ============================================================================
// OUTPUT STRUCTURE & READABILITY
// ============================================================================

suite.test('Output Structure', 'Help text is well-formatted', async () => {
    const result = await runInPTY('sh', ['access.sh', 'help']);
    
    // Check for proper sections
    const requiredSections = ['Usage:', 'Configuration:', 'Examples:', 'Environment variables:'];
    for (const section of requiredSections) {
        if (!result.cleanOutput.includes(section)) {
            throw new Error(`Missing section: ${section}`);
        }
    }
    
    // Check line length
    const longLines = result.lines.filter(line => line.length > 80);
    if (longLines.length > 5) {
        throw new Error(`${longLines.length} lines exceed 80 characters (terminal width)`);
    }
});

suite.test('Output Structure', 'Commands are aligned in help', async () => {
    const result = await runInPTY('sh', ['access.sh', 'help']);
    
    // Find command lines
    const commandLines = result.lines.filter(line => line.includes('access '));
    
    // Check alignment
    const indents = commandLines.map(line => line.search(/\S/));
    const uniqueIndents = [...new Set(indents)];
    
    if (uniqueIndents.length > 2) {
        throw new Error('Commands not properly aligned in help text');
    }
});

suite.test('Output Structure', 'Provider list is formatted as table', async () => {
    const result = await runInPTY('sh', ['access.sh', 'providers']);
    
    // Check for table-like structure
    const providerLines = result.lines.filter(line => 
        line.includes('[dns]') || line.includes('[blockchain]')
    );
    
    if (providerLines.length < 4) {
        throw new Error('Provider list not formatted as table');
    }
    
    // Check alignment
    const hasBrackets = providerLines.every(line => line.includes('[') && line.includes(']'));
    if (!hasBrackets) {
        throw new Error('Provider types not properly bracketed');
    }
});

// ============================================================================
// USER INTERACTION & FEEDBACK
// ============================================================================

suite.test('User Feedback', 'Progress indicators exist', async () => {
    const result = await runInPTY('sh', ['access.sh', 'health']);
    
    // Should show checking progress
    if (!result.cleanOutput.includes('...') && !result.cleanOutput.includes('✓')) {
        throw new Error('No progress indicators (... or ✓) found');
    }
});

suite.test('User Feedback', 'Clear error messages', async () => {
    const result = await runInPTY('sh', ['access.sh', 'config']);
    
    // Should have clear error
    if (!result.cleanOutput.includes('Error:') && !result.cleanOutput.includes('Usage:')) {
        throw new Error('Unclear error message when provider not specified');
    }
});

suite.test('User Feedback', 'Confirmation prompts are clear', async () => {
    const result = await runInPTY('sh', ['uninstall.sh'], {
        input: ['no\r'],
        timeout: 1000
    });
    
    // Should have clear prompt
    if (!result.cleanOutput.includes('Are you sure') || !result.cleanOutput.includes('Type')) {
        throw new Error('Confirmation prompt not clear');
    }
});

suite.test('User Feedback', 'Exit messages are friendly', async () => {
    const result = await runInPTY('sh', ['uninstall.sh'], {
        input: ['no\r'],
        timeout: 1000
    });
    
    if (!result.cleanOutput.includes('cancelled') && !result.cleanOutput.includes('Thank you')) {
        return 'warning'; // Warning: exit messages could be friendlier
    }
});

// ============================================================================
// VISUAL HIERARCHY
// ============================================================================

suite.test('Visual Hierarchy', 'Headers use separators', async () => {
    const result = await runInPTY('sh', ['install.sh', '--help']);
    
    // Check for visual separators
    const separators = ['====', '----', '****', '####'];
    let hasSeparator = false;
    
    for (const sep of separators) {
        if (result.cleanOutput.includes(sep)) {
            hasSeparator = true;
            break;
        }
    }
    
    if (!hasSeparator) {
        throw new Error('No visual separators (===, ---, etc) for sections');
    }
});

suite.test('Visual Hierarchy', 'Important info is highlighted', async () => {
    const result = await runInPTY('sh', ['access.sh', 'version']);
    
    // Version should be clearly visible
    if (!result.cleanOutput.includes('v0.0.2')) {
        throw new Error('Version number not clearly displayed');
    }
});

suite.test('Visual Hierarchy', 'Emojis used appropriately', async () => {
    const result = await runInPTY('sh', ['access.sh', 'health']);
    
    // Should use checkmarks or X for status
    const hasStatusEmoji = result.cleanOutput.includes('✓') || 
                          result.cleanOutput.includes('✗') ||
                          result.cleanOutput.includes('✅') ||
                          result.cleanOutput.includes('❌');
    
    if (!hasStatusEmoji) {
        return 'warning'; // Warning: could use emojis for better UX
    }
});

// ============================================================================
// ACCESSIBILITY
// ============================================================================

suite.test('Accessibility', 'No color-only information', async () => {
    const result = await runInPTY('sh', ['access.sh', 'health']);
    
    // Even without colors, should be understandable
    const clean = stripAnsi(result.output);
    if (!clean.includes('Healthy') && !clean.includes('Failed')) {
        throw new Error('Status not clear without colors');
    }
});

suite.test('Accessibility', 'Screen reader friendly output', async () => {
    const result = await runInPTY('sh', ['access.sh', 'providers']);
    
    // Should not have ASCII art that confuses screen readers
    const asciiArtChars = ['╔', '╗', '╚', '╝', '║', '═', '│', '─', '┌', '┐', '└', '┘'];
    let hasComplexArt = false;
    
    for (const char of asciiArtChars) {
        if (result.cleanOutput.includes(char)) {
            hasComplexArt = true;
            break;
        }
    }
    
    if (hasComplexArt) {
        return 'warning'; // Warning: complex ASCII art might confuse screen readers
    }
});

// ============================================================================
// ERROR HANDLING UX
// ============================================================================

suite.test('Error UX', 'Errors suggest solutions', async () => {
    const result = await runInPTY('sh', ['access.sh', 'update']);
    
    // Should suggest what to do
    if (!result.cleanOutput.includes('Run:') && !result.cleanOutput.includes('Try:')) {
        throw new Error('Error does not suggest solution');
    }
});

suite.test('Error UX', 'Invalid commands show help', async () => {
    const result = await runInPTY('sh', ['access.sh', 'invalid-command']);
    
    // Should show help or usage
    if (!result.cleanOutput.includes('Usage:') && !result.cleanOutput.includes('help')) {
        throw new Error('Invalid command does not show help');
    }
});

// ============================================================================
// PERFORMANCE FEEDBACK
// ============================================================================

suite.test('Performance', 'Long operations show progress', async () => {
    const result = await runInPTY('sh', ['access.sh', 'health']);
    
    // Health check should show progress
    const providerCount = (result.cleanOutput.match(/\.\.\./g) || []).length;
    if (providerCount < 3) {
        throw new Error('Long operation does not show progress');
    }
});

suite.test('Performance', 'Response time is acceptable', async () => {
    const start = Date.now();
    const result = await runInPTY('sh', ['access.sh', 'version'], {
        timeout: 1000
    });
    const duration = Date.now() - start;
    
    if (duration > 500) {
        throw new Error(`Slow response: ${duration}ms for simple command`);
    }
});

// ============================================================================
// CONSISTENCY
// ============================================================================

suite.test('Consistency', 'Consistent date/time format', async () => {
    // Create log entry
    await runInPTY('sh', ['access.sh', 'ip']);
    
    // Read log
    const logPath = path.join(TEST_CONFIG.testHome, '.access', 'access.log');
    try {
        const log = await fs.readFile(logPath, 'utf8');
        
        // Check date format
        const datePattern = /\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]/;
        if (!datePattern.test(log)) {
            throw new Error('Inconsistent date/time format in logs');
        }
    } catch (e) {
        // Log might not exist yet
        return 'warning';
    }
});

suite.test('Consistency', 'Consistent command format', async () => {
    const result = await runInPTY('sh', ['access.sh', 'help']);
    
    // All commands should follow pattern: access <command>
    const commandPattern = /access \w+/g;
    const commands = result.cleanOutput.match(commandPattern) || [];
    
    if (commands.length < 10) {
        throw new Error('Commands not consistently formatted');
    }
});

// ============================================================================
// MAIN
// ============================================================================

async function main() {
    console.log('🎨 Visual & UX Battle Test for Access');
    console.log('Testing terminal UI, colors, and user experience...\n');
    
    // Check if node-pty is installed
    try {
        require.resolve('node-pty');
    } catch (e) {
        console.error('❌ Required package not installed');
        console.error('Run: npm install node-pty');
        process.exit(1);
    }
    
    try {
        await setupTestEnvironment();
        const success = await suite.run();
        
        if (success) {
            console.log('\n✅ VISUAL/UX TEST PASSED!');
            console.log('Terminal UI is user-friendly and well-formatted.');
        } else {
            console.log('\n❌ VISUAL/UX TEST FAILED');
            console.log('UI/UX needs improvement.');
            process.exit(1);
        }
    } catch (error) {
        console.error('💥 Test framework error:', error);
        process.exit(1);
    } finally {
        await cleanupTestEnvironment();
    }
}

if (require.main === module) {
    main().catch(console.error);
}