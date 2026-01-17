#!/usr/bin/env node

/**
 * Claude Plugins CLI - Command line interface for plugin management
 */

import { Command } from "commander";
import chalk from "chalk";
import { searchCommand } from "./commands/search.js";
import { installCommand } from "./commands/install.js";
import { uninstallCommand } from "./commands/uninstall.js";
import { listCommand } from "./commands/list.js";
import { validateCommand } from "./commands/validate.js";
import { initCommand } from "./commands/init.js";
import { publishCommand } from "./commands/publish.js";
import { infoCommand } from "./commands/info.js";

const program = new Command();

program
  .name("claude-plugins")
  .description(
    "Claude Plugin Marketplace - discover, install, and manage Claude Code plugins",
  )
  .version("1.0.0");

// Search for plugins
program
  .command("search <query>")
  .description("Search for plugins in the marketplace")
  .option(
    "-t, --type <type>",
    "Filter by plugin type (skill, command, hook, mcp-server, etc.)",
  )
  .option("-c, --category <category>", "Filter by category")
  .option("--verified", "Only show verified plugins")
  .option("--featured", "Only show featured plugins")
  .option("-l, --limit <number>", "Number of results to show", "10")
  .action(searchCommand);

// Install a plugin
program
  .command("install <plugin>")
  .alias("i")
  .description("Install a plugin from the marketplace or local path")
  .option("--local", "Install from a local directory")
  .option("--force", "Force reinstall if already installed")
  .action(installCommand);

// Uninstall a plugin
program
  .command("uninstall <plugin>")
  .alias("remove")
  .alias("rm")
  .description("Uninstall a plugin")
  .option("--force", "Force uninstall without confirmation")
  .action(uninstallCommand);

// List installed plugins
program
  .command("list")
  .alias("ls")
  .description("List installed plugins")
  .option("-a, --all", "Show all plugins including disabled")
  .option("-t, --type <type>", "Filter by plugin type")
  .option("--outdated", "Show only outdated plugins")
  .action(listCommand);

// Validate a plugin
program
  .command("validate [path]")
  .description("Validate a plugin in the specified directory")
  .option("--strict", "Use strict validation mode")
  .action(validateCommand);

// Initialize a new plugin
program
  .command("init [name]")
  .description("Initialize a new plugin project")
  .option(
    "-t, --type <type>",
    "Plugin type (skill, command, hook, etc.)",
    "skill",
  )
  .option("-c, --category <category>", "Plugin category", "development")
  .option("--no-interactive", "Skip interactive prompts")
  .action(initCommand);

// Publish a plugin
program
  .command("publish [path]")
  .description("Publish a plugin to the marketplace")
  .option("--dry-run", "Validate without publishing")
  .option("--tag <tag>", "Publish with a specific tag", "latest")
  .action(publishCommand);

// Show plugin info
program
  .command("info <plugin>")
  .description("Show detailed information about a plugin")
  .option("--json", "Output as JSON")
  .action(infoCommand);

// Enable a plugin
program
  .command("enable <plugin>")
  .description("Enable a disabled plugin")
  .action(async (plugin: string) => {
    const { LocalRegistry } = await import("../registry/registry.js");
    const registry = new LocalRegistry();
    try {
      await registry.enable(plugin);
      console.log(chalk.green(`✓ Plugin "${plugin}" enabled`));
    } catch (error) {
      console.error(
        chalk.red(
          `Error: ${error instanceof Error ? error.message : "Unknown error"}`,
        ),
      );
      process.exit(1);
    }
  });

// Disable a plugin
program
  .command("disable <plugin>")
  .description("Disable a plugin without uninstalling")
  .action(async (plugin: string) => {
    const { LocalRegistry } = await import("../registry/registry.js");
    const registry = new LocalRegistry();
    try {
      await registry.disable(plugin);
      console.log(chalk.green(`✓ Plugin "${plugin}" disabled`));
    } catch (error) {
      console.error(
        chalk.red(
          `Error: ${error instanceof Error ? error.message : "Unknown error"}`,
        ),
      );
      process.exit(1);
    }
  });

// Parse and run
program.parse();
