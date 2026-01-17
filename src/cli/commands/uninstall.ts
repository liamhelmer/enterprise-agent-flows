/**
 * Uninstall command - remove a plugin
 */

import chalk from "chalk";
import { LocalRegistry } from "../../registry/registry.js";
import * as readline from "readline";

interface UninstallOptions {
  force?: boolean;
}

export async function uninstallCommand(
  plugin: string,
  options: UninstallOptions,
): Promise<void> {
  const registry = new LocalRegistry();

  // Check if plugin is installed
  const installed = await registry.getPlugin(plugin);
  if (!installed) {
    console.log(chalk.yellow(`Plugin "${plugin}" is not installed.`));
    return;
  }

  // Confirm uninstall unless --force is used
  if (!options.force) {
    const confirmed = await confirm(
      `Are you sure you want to uninstall "${plugin}"? This action cannot be undone.`,
    );

    if (!confirmed) {
      console.log(chalk.gray("Uninstall cancelled."));
      return;
    }
  }

  try {
    console.log(chalk.blue(`Uninstalling ${plugin}...`));
    await registry.uninstall(plugin);
    console.log(chalk.green(`✓ Successfully uninstalled "${plugin}"`));
  } catch (error) {
    console.error(
      chalk.red(
        `Error uninstalling plugin: ${error instanceof Error ? error.message : "Unknown error"}`,
      ),
    );
    process.exit(1);
  }
}

function confirm(message: string): Promise<boolean> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(`${message} (y/N) `, (answer) => {
      rl.close();
      resolve(answer.toLowerCase() === "y" || answer.toLowerCase() === "yes");
    });
  });
}
