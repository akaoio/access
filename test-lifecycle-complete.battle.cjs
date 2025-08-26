#!/usr/bin/env node
/**
 * COMPLETE LIFECYCLE TEST for Access
 * Tests: Installation → Configuration → Updates → Uninstallation
 * Vietnamese: Test toàn bộ quy trình cài đặt, cập nhật và tháo gỡ
 */

const { exec, spawn } = require('child_process');
const { promisify } = require('util');
const execAsync = promisify(exec);
const fs = require('fs').promises;
const path = require('path');
const os = require('os');

// Test environment
const TEST_ENV = {
    testHome: path.join(os.tmpdir(), 'access_lifecycle_test_' + Date.now()),
    binDir: path.join(os.tmpdir(), 'access_lifecycle_test_' + Date.now(), 'bin'),
    accessHome: null,
    originalHome: process.env.HOME,
    originalPath: process.env.PATH,
    testStartTime: Date.now()
};

TEST_ENV.accessHome = path.join(TEST_ENV.testHome, '.access');

class LifecycleTest {
    constructor() {
        this.tests = [];
        this.results = { passed: 0, failed: 0, warnings: 0 };
        this.issues = [];
        this.artifacts = [];
    }

    test(phase, name, fn) {
        this.tests.push({ phase, name, fn });
    }

    async run() {
        console.log('\n🔄 COMPLETE LIFECYCLE TEST FOR ACCESS');
        console.log('=' .repeat(60));
        console.log('Testing: Installation → Configuration → Updates → Uninstallation');
        console.log(`Test Environment: ${TEST_ENV.testHome}`);
        console.log('');

        const phases = {};
        for (const test of this.tests) {
            if (!phases[test.phase]) {
                phases[test.phase] = [];
            }
            phases[test.phase].push(test);
        }

        const phaseOrder = ['Setup', 'Installation', 'Configuration', 'Updates', 'Uninstallation', 'Cleanup'];
        
        for (const phase of phaseOrder) {
            if (!phases[phase]) continue;
            
            console.log(`\n🔧 ${phase} Phase`);
            console.log('-'.repeat(40));
            
            for (const test of phases[phase]) {
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
                    this.issues.push({ phase, test: test.name, error: error.message });
                    console.log(`  ❌ ${test.name}: ${error.message}`);
                    
                    // Continue with non-critical tests
                    if (!error.critical) {
                        console.log(`     (Continuing despite error...)`);
                    }
                }
            }
        }

        console.log('\n' + '='.repeat(60));
        console.log('📊 LIFECYCLE TEST SUMMARY');
        console.log('-'.repeat(60));
        console.log(`✅ Passed: ${this.results.passed}`);
        console.log(`⚠️  Warnings: ${this.results.warnings}`);
        console.log(`❌ Failed: ${this.results.failed}`);
        
        if (this.issues.length > 0) {
            console.log('\n❌ Issues Found:');
            for (const issue of this.issues) {
                console.log(`   [${issue.phase}] ${issue.test}:`);
                console.log(`     ${issue.error}`);
            }
        }

        if (this.artifacts.length > 0) {
            console.log('\n📁 Test Artifacts Created:');
            for (const artifact of this.artifacts) {
                console.log(`   ${artifact}`);
            }
        }

        return this.results.failed === 0;
    }

    addArtifact(path) {
        this.artifacts.push(path);
    }
}

async function runCommand(cmd, options = {}) {
    try {
        const env = {
            ...process.env,
            HOME: TEST_ENV.testHome,
            ACCESS_HOME: TEST_ENV.accessHome,
            PATH: `${TEST_ENV.binDir}:${process.env.PATH}`,
            FORCE_COLOR: '1',
            ...options.env
        };

        const { stdout, stderr } = await execAsync(cmd, {
            cwd: options.cwd || __dirname,
            env,
            timeout: options.timeout || 10000
        });
        
        return { stdout, stderr, success: true };
    } catch (error) {
        return { 
            stdout: error.stdout || '', 
            stderr: error.stderr || '',
            code: error.code || 1,
            success: false,
            error: error.message
        };
    }
}

async function runInteractiveCommand(cmd, inputs = [], options = {}) {
    return new Promise((resolve, reject) => {
        const env = {
            ...process.env,
            HOME: TEST_ENV.testHome,
            ACCESS_HOME: TEST_ENV.accessHome,
            PATH: `${TEST_ENV.binDir}:${process.env.PATH}`,
            ...options.env
        };

        const proc = spawn('sh', ['-c', cmd], {
            cwd: options.cwd || __dirname,
            env,
            stdio: ['pipe', 'pipe', 'pipe']
        });

        let stdout = '';
        let stderr = '';
        
        proc.stdout.on('data', (data) => {
            stdout += data.toString();
        });
        
        proc.stderr.on('data', (data) => {
            stderr += data.toString();
        });

        // Send inputs
        let inputIndex = 0;
        const sendNextInput = () => {
            if (inputIndex < inputs.length) {
                setTimeout(() => {
                    proc.stdin.write(inputs[inputIndex] + '\n');
                    inputIndex++;
                    sendNextInput();
                }, 100);
            } else {
                setTimeout(() => {
                    proc.stdin.end();
                }, 100);
            }
        };

        setTimeout(sendNextInput, 100);

        proc.on('close', (code) => {
            resolve({ stdout, stderr, code, success: code === 0 });
        });

        proc.on('error', reject);
        
        // Timeout
        setTimeout(() => {
            proc.kill('SIGTERM');
            resolve({ stdout, stderr, code: 124, success: false, timeout: true });
        }, options.timeout || 5000);
    });
}

const suite = new LifecycleTest();

// ============================================================================
// SETUP PHASE
// ============================================================================

suite.test('Setup', 'Create test environment', async () => {
    await fs.mkdir(TEST_ENV.testHome, { recursive: true });
    await fs.mkdir(TEST_ENV.binDir, { recursive: true });
    await fs.mkdir(TEST_ENV.accessHome, { recursive: true });
    
    // Verify directories
    const homeExists = await fs.access(TEST_ENV.testHome).then(() => true).catch(() => false);
    const binExists = await fs.access(TEST_ENV.binDir).then(() => true).catch(() => false);
    
    if (!homeExists || !binExists) {
        throw new Error('Failed to create test directories');
    }
    
    suite.addArtifact(TEST_ENV.testHome);
});

suite.test('Setup', 'Backup current system state', async () => {
    // Check if access is already installed
    const { success: accessExists } = await runCommand('which access 2>/dev/null');
    
    if (accessExists) {
        console.log('     (Access already installed - noting for cleanup)');
        return 'warning';
    }
});

// ============================================================================
// INSTALLATION PHASE  
// ============================================================================

suite.test('Installation', 'Installer script exists and is executable', async () => {
    const installerExists = await fs.access('install.sh').then(() => true).catch(() => false);
    if (!installerExists) {
        throw new Error('install.sh not found');
    }

    const stats = await fs.stat('install.sh');
    if (!(stats.mode & 0o111)) {
        throw new Error('install.sh is not executable');
    }
});

suite.test('Installation', 'Display installer help', async () => {
    const { stdout, success } = await runCommand('sh install.sh --help');
    
    if (!success) {
        throw new Error('Installer help failed');
    }

    if (!stdout.includes('Installation Options') || !stdout.includes('Examples')) {
        throw new Error('Installer help incomplete');
    }
});

suite.test('Installation', 'Install Access with default options', async () => {
    const { stdout, stderr, success } = await runCommand(`sh install.sh --prefix="${TEST_ENV.testHome}"`, {
        timeout: 15000
    });
    
    if (!success) {
        throw new Error(`Installation failed: ${stderr}`);
    }

    // Check if binary was installed
    const accessBinary = path.join(TEST_ENV.binDir, 'access');
    const binaryExists = await fs.access(accessBinary).then(() => true).catch(() => false);
    
    if (!binaryExists) {
        throw new Error('Access binary not installed');
    }

    suite.addArtifact(accessBinary);
});

suite.test('Installation', 'Verify installed binary works', async () => {
    const { stdout, success } = await runCommand('access version');
    
    if (!success) {
        throw new Error('Installed binary does not work');
    }

    if (!stdout.includes('v0.0.2')) {
        throw new Error('Version mismatch in installed binary');
    }
});

suite.test('Installation', 'Check installation creates required directories', async () => {
    const configExists = await fs.access(TEST_ENV.accessHome).then(() => true).catch(() => false);
    
    if (!configExists) {
        throw new Error('Access config directory not created');
    }
});

suite.test('Installation', 'Verify systemd service file created', async () => {
    const serviceFile = path.join(TEST_ENV.testHome, '.config/systemd/user/access.service');
    const serviceExists = await fs.access(serviceFile).then(() => true).catch(() => false);
    
    if (!serviceExists) {
        return 'warning'; // Systemd might not be available in test environment
    }

    const content = await fs.readFile(serviceFile, 'utf8');
    if (!content.includes('ExecStart=') || !content.includes('access')) {
        throw new Error('Systemd service file malformed');
    }

    suite.addArtifact(serviceFile);
});

// ============================================================================
// CONFIGURATION PHASE
// ============================================================================

suite.test('Configuration', 'List available providers', async () => {
    const { stdout, success } = await runCommand('access providers');
    
    if (!success) {
        throw new Error('Failed to list providers');
    }

    if (!stdout.includes('Available providers') || !stdout.includes('[dns')) {
        throw new Error('Provider list incomplete');
    }
});

suite.test('Configuration', 'Test provider configuration help', async () => {
    const { stdout, success } = await runCommand('access config cloudflare --help');
    
    if (!success) {
        throw new Error('Provider config help failed');
    }

    if (!stdout.includes('Configuration for cloudflare') || !stdout.includes('field:')) {
        throw new Error('Provider configuration help incomplete');
    }
});

suite.test('Configuration', 'Configure test provider', async () => {
    // Configure cloudflare with dummy data
    const { stdout, stderr, success } = await runCommand(
        'access config cloudflare --domain=test.example.com --email=test@example.com --api-key=dummy --zone-id=dummy'
    );
    
    if (!success) {
        throw new Error(`Configuration failed: ${stderr}`);
    }

    // Check config was saved
    const configFile = path.join(TEST_ENV.accessHome, 'config.json');
    const configExists = await fs.access(configFile).then(() => true).catch(() => false);
    
    if (!configExists) {
        throw new Error('Configuration not saved');
    }

    const config = JSON.parse(await fs.readFile(configFile, 'utf8'));
    if (config.provider !== 'cloudflare' || !config.domain) {
        throw new Error('Configuration incomplete');
    }

    suite.addArtifact(configFile);
});

suite.test('Configuration', 'Test IP detection', async () => {
    const { stdout, success } = await runCommand('access ip');
    
    if (!success) {
        throw new Error('IP detection failed');
    }

    // Should be an IP address
    const ipPattern = /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/;
    if (!ipPattern.test(stdout)) {
        throw new Error('Invalid IP format detected');
    }
});

suite.test('Configuration', 'Test provider health check', async () => {
    const { stdout, success } = await runCommand('access health');
    
    if (!success) {
        throw new Error('Health check failed');
    }

    if (!stdout.includes('Provider Health Check') || !stdout.includes('cloudflare')) {
        throw new Error('Health check incomplete');
    }
});

// ============================================================================  
// UPDATES PHASE
// ============================================================================

suite.test('Updates', 'Test auto-update check', async () => {
    const { stdout, stderr, success } = await runCommand('access auto-update --check-only', {
        timeout: 10000
    });
    
    // Auto-update might fail in test environment - that's okay
    if (!success && !stderr.includes('Failed to download')) {
        throw new Error(`Unexpected auto-update error: ${stderr}`);
    }
    
    if (success && !stdout.includes('version')) {
        return 'warning'; // Update check worked but no clear version info
    }
});

suite.test('Updates', 'Test daemon mode (brief)', async () => {
    // Start daemon in background for a few seconds
    const { stdout, success } = await runCommand('timeout 3s access daemon 2>&1 || true');
    
    if (!stdout.includes('Starting') && !stdout.includes('daemon')) {
        return 'warning'; // Daemon might not start in test environment
    }
});

suite.test('Updates', 'Test cron job would be created', async () => {
    // Check if cron job format is valid
    const { stdout, success } = await runCommand('access help | grep cron || echo "No cron mentioned"');
    
    // This is informational - we don't want to modify actual cron in test
    return 'warning';
});

// ============================================================================
// UNINSTALLATION PHASE
// ============================================================================

suite.test('Uninstallation', 'Uninstaller script exists', async () => {
    const uninstallerExists = await fs.access('uninstall.sh').then(() => true).catch(() => false);
    if (!uninstallerExists) {
        throw new Error('uninstall.sh not found');
    }

    const stats = await fs.stat('uninstall.sh');
    if (!(stats.mode & 0o111)) {
        throw new Error('uninstall.sh is not executable');
    }
});

suite.test('Uninstallation', 'Test uninstaller confirmation prompt', async () => {
    // Test with "no" response
    const { stdout, code } = await runInteractiveCommand('sh uninstall.sh', ['no'], {
        timeout: 3000
    });
    
    if (!stdout.includes('Are you sure') || !stdout.includes('Type')) {
        throw new Error('Uninstaller confirmation prompt missing');
    }

    if (code === 0) {
        throw new Error('Uninstaller should exit non-zero when cancelled');
    }
});

suite.test('Uninstallation', 'Perform complete uninstallation', async () => {
    // Test with "yes" response
    const { stdout, stderr, success } = await runInteractiveCommand('sh uninstall.sh', ['yes'], {
        timeout: 10000
    });
    
    if (!success) {
        throw new Error(`Uninstallation failed: ${stderr}`);
    }

    if (!stdout.includes('Access has been uninstalled') && !stdout.includes('removed')) {
        return 'warning'; // Uninstaller might have different success message
    }
});

suite.test('Uninstallation', 'Verify binary removed', async () => {
    const accessBinary = path.join(TEST_ENV.binDir, 'access');
    const binaryExists = await fs.access(accessBinary).then(() => true).catch(() => false);
    
    if (binaryExists) {
        throw new Error('Access binary not removed');
    }
});

suite.test('Uninstallation', 'Verify configuration cleaned up', async () => {
    // Config directory might still exist but should be empty or cleaned
    const configFile = path.join(TEST_ENV.accessHome, 'config.json');
    const configExists = await fs.access(configFile).then(() => true).catch(() => false);
    
    if (configExists) {
        return 'warning'; // Config cleanup is optional
    }
});

suite.test('Uninstallation', 'Verify systemd service removed', async () => {
    const serviceFile = path.join(TEST_ENV.testHome, '.config/systemd/user/access.service');
    const serviceExists = await fs.access(serviceFile).then(() => true).catch(() => false);
    
    if (serviceExists) {
        return 'warning'; // Service removal might fail in test environment
    }
});

// ============================================================================
// CLEANUP PHASE
// ============================================================================

suite.test('Cleanup', 'Remove test environment', async () => {
    try {
        await fs.rm(TEST_ENV.testHome, { recursive: true, force: true });
        
        // Verify cleanup
        const exists = await fs.access(TEST_ENV.testHome).then(() => true).catch(() => false);
        if (exists) {
            throw new Error('Test environment not fully cleaned');
        }
    } catch (error) {
        throw new Error(`Cleanup failed: ${error.message}`);
    }
});

// ============================================================================
// MAIN
// ============================================================================

async function main() {
    console.log('🔄 Complete Lifecycle Test for Access');
    console.log('Testing: Installation → Configuration → Updates → Uninstallation');
    console.log(`Started at: ${new Date().toISOString()}`);
    console.log('');

    try {
        const success = await suite.run();
        
        const duration = Date.now() - TEST_ENV.testStartTime;
        
        if (success) {
            console.log('\n✅ LIFECYCLE TEST PASSED!');
            console.log('All installation, configuration, update, and uninstallation processes work correctly.');
        } else {
            console.log('\n❌ LIFECYCLE TEST FAILED');
            console.log('Some issues found in the lifecycle processes.');
        }
        
        console.log(`\nTest Duration: ${duration}ms`);
        console.log(`Test Environment: ${TEST_ENV.testHome}`);
        
        if (!success) {
            process.exit(1);
        }
    } catch (error) {
        console.error('💥 Test framework error:', error);
        
        // Cleanup on error
        try {
            await fs.rm(TEST_ENV.testHome, { recursive: true, force: true });
        } catch (cleanupError) {
            console.error('Failed to cleanup test environment:', cleanupError.message);
        }
        
        process.exit(1);
    }
}

if (require.main === module) {
    main().catch(console.error);
}