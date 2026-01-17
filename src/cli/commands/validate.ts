/**
 * Validate command - validate a plugin
 */

import chalk from "chalk";
import {
  validatePlugin,
  formatValidationResult,
} from "../../validation/validator.js";
import { isDirectory } from "../../core/utils.js";

interface ValidateOptions {
  strict?: boolean;
}

export async function validateCommand(
  path: string = ".",
  options: ValidateOptions,
): Promise<void> {
  console.log(chalk.blue(`Validating plugin at: ${path}`));
  console.log("");

  if (!(await isDirectory(path))) {
    console.error(chalk.red(`Error: Directory not found: ${path}`));
    process.exit(1);
  }

  const result = await validatePlugin(path);

  console.log(formatValidationResult(result));
  console.log("");

  if (options.strict && result.warnings.length > 0) {
    console.log(chalk.yellow("Strict mode: treating warnings as errors"));
    process.exit(1);
  }

  if (!result.valid) {
    process.exit(1);
  }

  console.log(chalk.green("Plugin is valid and ready to publish!"));
}
