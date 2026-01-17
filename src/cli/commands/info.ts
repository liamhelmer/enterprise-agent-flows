/**
 * Info command - show detailed plugin information
 */

import chalk from "chalk";
import { LocalRegistry, RemoteRegistry } from "../../registry/registry.js";
import type { PluginManifest, RegistryEntry } from "../../core/types.js";

interface InfoOptions {
  json?: boolean;
}

export async function infoCommand(
  plugin: string,
  options: InfoOptions,
): Promise<void> {
  const localRegistry = new LocalRegistry();
  const remoteRegistry = new RemoteRegistry();

  // Check if installed locally
  const localPlugin = await localRegistry.getPlugin(plugin);

  // Try to get from remote registry
  const remotePlugin = await remoteRegistry.getPlugin(plugin);

  if (!localPlugin && !remotePlugin) {
    console.error(chalk.red(`Plugin "${plugin}" not found.`));
    console.log("");
    console.log("Suggestions:");
    console.log("  • Check the plugin name spelling");
    console.log('  • Use "claude-plugins search" to find plugins');
    process.exit(1);
  }

  if (options.json) {
    const data = {
      local: localPlugin || null,
      remote: remotePlugin || null,
    };
    console.log(JSON.stringify(data, null, 2));
    return;
  }

  const manifest = localPlugin?.manifest || remotePlugin;
  if (!manifest) {
    console.error(chalk.red("Unable to retrieve plugin information."));
    process.exit(1);
  }

  // Display plugin info
  console.log("");
  console.log(
    chalk.bold.cyan(manifest.name) + chalk.gray(` v${manifest.version}`),
  );
  console.log("");

  // Status badges
  const badges: string[] = [];
  if (localPlugin) {
    badges.push(chalk.green("✓ installed"));
    if (!localPlugin.enabled) badges.push(chalk.gray("disabled"));
  }
  if (remotePlugin) {
    if (remotePlugin.verified) badges.push(chalk.blue("✓ verified"));
    if (remotePlugin.featured) badges.push(chalk.yellow("★ featured"));
    if (remotePlugin.deprecated) badges.push(chalk.red("⚠ deprecated"));
  }

  if (badges.length > 0) {
    console.log(badges.join(" "));
    console.log("");
  }

  // Description
  console.log(chalk.white(manifest.description));
  console.log("");

  // Details
  console.log(chalk.bold("Details"));
  console.log(chalk.gray("─".repeat(40)));
  console.log(`  Type:     ${manifest.type}`);
  console.log(`  Category: ${manifest.category}`);
  console.log(`  License:  ${manifest.license || "Not specified"}`);
  console.log(
    `  Author:   ${manifest.author.name}${manifest.author.email ? ` <${manifest.author.email}>` : ""}`,
  );

  if (manifest.homepage) {
    console.log(`  Homepage: ${manifest.homepage}`);
  }

  if (manifest.repository) {
    console.log(`  Repo:     ${manifest.repository.url}`);
  }

  console.log("");

  // Keywords
  if (manifest.keywords && manifest.keywords.length > 0) {
    console.log(chalk.bold("Keywords"));
    console.log(chalk.gray("─".repeat(40)));
    console.log(`  ${manifest.keywords.join(", ")}`);
    console.log("");
  }

  // Registry stats (if available)
  if (remotePlugin) {
    console.log(chalk.bold("Stats"));
    console.log(chalk.gray("─".repeat(40)));
    console.log(`  Downloads: ${remotePlugin.downloads.toLocaleString()}`);
    if (remotePlugin.rating !== undefined) {
      console.log(
        `  Rating:    ${"★".repeat(Math.round(remotePlugin.rating))}${"☆".repeat(5 - Math.round(remotePlugin.rating))} (${remotePlugin.rating.toFixed(1)})`,
      );
      console.log(`  Reviews:   ${remotePlugin.reviews}`);
    }
    console.log("");
  }

  // Installation info
  if (localPlugin) {
    console.log(chalk.bold("Installation"));
    console.log(chalk.gray("─".repeat(40)));
    console.log(`  Installed: ${localPlugin.installedAt}`);
    console.log(`  Version:   ${localPlugin.installedVersion}`);
    console.log(`  Path:      ${localPlugin.path}`);
    console.log(`  Enabled:   ${localPlugin.enabled ? "Yes" : "No"}`);

    if (
      localPlugin.latestVersion &&
      localPlugin.latestVersion !== localPlugin.installedVersion
    ) {
      console.log("");
      console.log(
        chalk.yellow(`  Update available: ${localPlugin.latestVersion}`),
      );
    }
    console.log("");
  }

  // Requirements (if any)
  if (manifest.requirements) {
    console.log(chalk.bold("Requirements"));
    console.log(chalk.gray("─".repeat(40)));
    if (manifest.requirements.claude) {
      console.log(`  Claude:  ${manifest.requirements.claude}`);
    }
    if (manifest.requirements.node) {
      console.log(`  Node.js: ${manifest.requirements.node}`);
    }
    if (manifest.requirements.os && manifest.requirements.os.length > 0) {
      console.log(`  OS:      ${manifest.requirements.os.join(", ")}`);
    }
    if (manifest.requirements.tools && manifest.requirements.tools.length > 0) {
      console.log(`  Tools:   ${manifest.requirements.tools.join(", ")}`);
    }
    console.log("");
  }

  // Install command
  if (!localPlugin) {
    console.log(chalk.bold("Install"));
    console.log(chalk.gray("─".repeat(40)));
    console.log(chalk.cyan(`  claude-plugins install ${manifest.name}`));
    console.log("");
  }
}
