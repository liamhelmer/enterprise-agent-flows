/**
 * Install command - install a plugin
 */

import chalk from "chalk";
import { LocalRegistry, RemoteRegistry } from "../../registry/registry.js";
import {
  validatePlugin,
  formatValidationResult,
} from "../../validation/validator.js";
import { isDirectory } from "../../core/utils.js";

interface InstallOptions {
  local?: boolean;
  force?: boolean;
}

export async function installCommand(
  plugin: string,
  options: InstallOptions,
): Promise<void> {
  const localRegistry = new LocalRegistry();

  // Check if already installed
  if (!options.force && (await localRegistry.isInstalled(plugin))) {
    console.log(chalk.yellow(`Plugin "${plugin}" is already installed.`));
    console.log("Use --force to reinstall.");
    return;
  }

  if (options.local) {
    await installFromLocal(plugin, localRegistry);
  } else {
    await installFromRegistry(plugin, localRegistry);
  }
}

async function installFromLocal(
  path: string,
  localRegistry: LocalRegistry,
): Promise<void> {
  console.log(chalk.blue(`Installing plugin from local path: ${path}`));

  // Validate the plugin
  if (!(await isDirectory(path))) {
    console.error(chalk.red(`Error: Directory not found: ${path}`));
    process.exit(1);
  }

  console.log("Validating plugin...");
  const validationResult = await validatePlugin(path);

  if (!validationResult.valid) {
    console.error(chalk.red("Plugin validation failed:"));
    console.error(formatValidationResult(validationResult));
    process.exit(1);
  }

  if (validationResult.warnings.length > 0) {
    console.log(chalk.yellow("Warnings:"));
    for (const warning of validationResult.warnings) {
      console.log(chalk.yellow(`  ⚠ ${warning.message}`));
    }
  }

  try {
    console.log("Installing plugin...");
    const installed = await localRegistry.installFromPath(path);
    console.log("");
    console.log(
      chalk.green(
        `✓ Successfully installed ${installed.manifest.name}@${installed.manifest.version}`,
      ),
    );
    console.log(chalk.gray(`  Location: ${installed.path}`));
  } catch (error) {
    console.error(
      chalk.red(
        `Error installing plugin: ${error instanceof Error ? error.message : "Unknown error"}`,
      ),
    );
    process.exit(1);
  }
}

async function installFromRegistry(
  pluginName: string,
  localRegistry: LocalRegistry,
): Promise<void> {
  console.log(chalk.blue(`Installing plugin: ${pluginName}`));

  const remoteRegistry = new RemoteRegistry();

  // Fetch plugin info
  console.log("Fetching plugin information...");
  const pluginInfo = await remoteRegistry.getPlugin(pluginName);

  if (!pluginInfo) {
    console.error(
      chalk.red(`Plugin "${pluginName}" not found in the registry.`),
    );
    console.log("");
    console.log("Suggestions:");
    console.log("  • Check the plugin name spelling");
    console.log('  • Use "claude-plugins search" to find plugins');
    console.log("  • Use --local to install from a local directory");
    process.exit(1);
  }

  if (pluginInfo.deprecated) {
    console.log(chalk.yellow(`⚠ Warning: This plugin is deprecated.`));
    if (pluginInfo.deprecationMessage) {
      console.log(chalk.yellow(`  ${pluginInfo.deprecationMessage}`));
    }
  }

  // For now, show a message about registry being unavailable
  console.log("");
  console.log(
    chalk.yellow("Note: Remote registry installation is not yet available."),
  );
  console.log("To install a plugin, use:");
  console.log("");
  console.log(chalk.cyan(`  claude-plugins install /path/to/plugin --local`));
  console.log("");
}
