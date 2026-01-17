/**
 * List command - list installed plugins
 */

import chalk from "chalk";
import { LocalRegistry } from "../../registry/registry.js";
import type { PluginType } from "../../core/types.js";

interface ListOptions {
  all?: boolean;
  type?: string;
  outdated?: boolean;
}

export async function listCommand(options: ListOptions): Promise<void> {
  const registry = new LocalRegistry();

  const plugins = await registry.getInstalled();

  if (plugins.length === 0) {
    console.log(chalk.yellow("No plugins installed."));
    console.log("");
    console.log("Get started by installing a plugin:");
    console.log(chalk.cyan("  claude-plugins search <query>"));
    console.log(chalk.cyan("  claude-plugins install <plugin>"));
    return;
  }

  // Filter plugins
  let filteredPlugins = plugins;

  if (!options.all) {
    filteredPlugins = filteredPlugins.filter((p) => p.enabled);
  }

  if (options.type) {
    filteredPlugins = filteredPlugins.filter(
      (p) => p.manifest.type === options.type,
    );
  }

  if (options.outdated) {
    filteredPlugins = filteredPlugins.filter(
      (p) => p.latestVersion && p.installedVersion !== p.latestVersion,
    );
  }

  if (filteredPlugins.length === 0) {
    console.log(chalk.yellow("No plugins match the specified filters."));
    return;
  }

  console.log(chalk.bold(`Installed plugins (${filteredPlugins.length}):`));
  console.log("");

  for (const plugin of filteredPlugins) {
    const status: string[] = [];

    if (!plugin.enabled) {
      status.push(chalk.gray("[disabled]"));
    }

    if (
      plugin.latestVersion &&
      plugin.installedVersion !== plugin.latestVersion
    ) {
      status.push(chalk.yellow(`[update: ${plugin.latestVersion}]`));
    }

    const statusStr = status.length > 0 ? " " + status.join(" ") : "";

    console.log(
      chalk.cyan(plugin.manifest.name) +
        chalk.gray(`@${plugin.installedVersion}`) +
        statusStr,
    );

    console.log(chalk.gray(`  ${plugin.manifest.description}`));
    console.log(
      chalk.gray(
        `  Type: ${plugin.manifest.type} | Category: ${plugin.manifest.category}`,
      ),
    );
    console.log(chalk.gray(`  Path: ${plugin.path}`));
    console.log("");
  }
}
