/**
 * Publish command - publish a plugin to the marketplace
 */

import chalk from "chalk";
import {
  validatePlugin,
  formatValidationResult,
} from "../../validation/validator.js";
import {
  isDirectory,
  readJsonFile,
  validatePluginSize,
  formatBytes,
} from "../../core/utils.js";
import { MANIFEST_FILENAME } from "../../core/constants.js";
import { join } from "path";
import type { PluginManifest } from "../../core/types.js";

interface PublishOptions {
  dryRun?: boolean;
  tag: string;
}

export async function publishCommand(
  path: string = ".",
  options: PublishOptions,
): Promise<void> {
  console.log(
    chalk.blue(
      `${options.dryRun ? "[DRY RUN] " : ""}Publishing plugin from: ${path}`,
    ),
  );
  console.log("");

  // Check directory exists
  if (!(await isDirectory(path))) {
    console.error(chalk.red(`Error: Directory not found: ${path}`));
    process.exit(1);
  }

  // Validate the plugin
  console.log("Step 1/4: Validating plugin...");
  const validationResult = await validatePlugin(path);

  if (!validationResult.valid) {
    console.error(chalk.red("Validation failed:"));
    console.error(formatValidationResult(validationResult));
    process.exit(1);
  }

  if (validationResult.warnings.length > 0) {
    console.log(chalk.yellow("Warnings:"));
    for (const warning of validationResult.warnings) {
      console.log(chalk.yellow(`  ⚠ ${warning.message}`));
    }
  }

  console.log(chalk.green("  ✓ Validation passed"));

  // Check plugin size
  console.log("Step 2/4: Checking plugin size...");
  const sizeResult = await validatePluginSize(path);

  console.log(chalk.gray(`  Total size: ${formatBytes(sizeResult.totalSize)}`));
  console.log(chalk.gray(`  File count: ${sizeResult.fileCount}`));
  console.log(chalk.green("  ✓ Size check passed"));

  // Read manifest
  console.log("Step 3/4: Reading manifest...");
  const manifestPath = join(path, MANIFEST_FILENAME);
  const manifest = await readJsonFile<PluginManifest>(manifestPath);

  console.log(chalk.gray(`  Name: ${manifest.name}`));
  console.log(chalk.gray(`  Version: ${manifest.version}`));
  console.log(chalk.gray(`  Type: ${manifest.type}`));
  console.log(chalk.gray(`  Category: ${manifest.category}`));
  console.log(chalk.green("  ✓ Manifest loaded"));

  // Publish
  console.log("Step 4/4: Publishing...");

  if (options.dryRun) {
    console.log(chalk.yellow("  [DRY RUN] Skipping actual publish"));
    console.log("");
    console.log(chalk.green("✓ Dry run complete. Plugin is ready to publish."));
    console.log("");
    console.log("To publish for real, run:");
    console.log(chalk.cyan(`  claude-plugins publish ${path}`));
    return;
  }

  // Note: Actual registry publishing not yet implemented
  console.log("");
  console.log(
    chalk.yellow("Note: Remote registry publishing is not yet available."),
  );
  console.log("");
  console.log("For now, you can:");
  console.log("  1. Share your plugin via GitHub or npm");
  console.log("  2. Install locally with: claude-plugins install . --local");
  console.log("");
  console.log("Your plugin is valid and ready for distribution!");
}
