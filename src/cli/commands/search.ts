/**
 * Search command - search for plugins in the marketplace
 */

import chalk from "chalk";
import { RemoteRegistry } from "../../registry/registry.js";
import type {
  PluginCategory,
  PluginType,
  RegistryEntry,
} from "../../core/types.js";

interface SearchOptions {
  type?: string;
  category?: string;
  verified?: boolean;
  featured?: boolean;
  limit: string;
}

export async function searchCommand(
  query: string,
  options: SearchOptions,
): Promise<void> {
  const registry = new RemoteRegistry();

  console.log(chalk.blue(`Searching for "${query}"...`));
  console.log("");

  try {
    const result = await registry.search({
      query,
      type: options.type as PluginType | undefined,
      category: options.category as PluginCategory | undefined,
      verified: options.verified,
      featured: options.featured,
      limit: parseInt(options.limit, 10),
      sortBy: "downloads",
      sortOrder: "desc",
    });

    if (result.results.length === 0) {
      console.log(chalk.yellow("No plugins found matching your search."));
      console.log("");
      console.log("Tips:");
      console.log("  • Try a different search term");
      console.log("  • Remove filters to broaden the search");
      console.log("  • Check the plugin type or category");
      return;
    }

    console.log(
      chalk.bold(
        `Found ${result.total} plugin${result.total === 1 ? "" : "s"}:`,
      ),
    );
    console.log("");

    for (const plugin of result.results) {
      printPlugin(plugin);
    }

    if (result.total > result.results.length) {
      console.log("");
      console.log(
        chalk.gray(
          `Showing ${result.results.length} of ${result.total} results. Use --limit to see more.`,
        ),
      );
    }
  } catch (error) {
    console.error(
      chalk.red(
        `Error searching plugins: ${error instanceof Error ? error.message : "Unknown error"}`,
      ),
    );
    process.exit(1);
  }
}

function printPlugin(plugin: RegistryEntry): void {
  const badges: string[] = [];
  if (plugin.verified) badges.push(chalk.green("✓ verified"));
  if (plugin.featured) badges.push(chalk.yellow("★ featured"));
  if (plugin.deprecated) badges.push(chalk.red("⚠ deprecated"));

  console.log(chalk.bold.cyan(plugin.name) + chalk.gray(` v${plugin.version}`));

  if (badges.length > 0) {
    console.log("  " + badges.join(" "));
  }

  console.log("  " + chalk.white(plugin.description));
  console.log(
    "  " +
      chalk.gray(
        `${plugin.type} • ${plugin.category} • ${plugin.downloads} downloads`,
      ),
  );

  if (plugin.keywords.length > 0) {
    console.log("  " + chalk.gray("tags: " + plugin.keywords.join(", ")));
  }

  console.log("");
}
