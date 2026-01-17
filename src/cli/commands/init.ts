/**
 * Init command - initialize a new plugin project
 */

import chalk from "chalk";
import { mkdir, writeFile } from "fs/promises";
import { join } from "path";
import * as readline from "readline";
import type { PluginType, PluginCategory } from "../../core/types.js";
import {
  PLUGIN_TYPE_DESCRIPTIONS,
  CATEGORY_DESCRIPTIONS,
} from "../../core/constants.js";

interface InitOptions {
  type: string;
  category: string;
  interactive?: boolean;
}

interface PluginConfig {
  name: string;
  description: string;
  type: PluginType;
  category: PluginCategory;
  author: string;
}

export async function initCommand(
  name: string | undefined,
  options: InitOptions,
): Promise<void> {
  let config: PluginConfig;

  if (options.interactive !== false && !name) {
    config = await interactiveInit();
  } else {
    config = {
      name: name || "my-plugin",
      description: "A Claude Code plugin",
      type: options.type as PluginType,
      category: options.category as PluginCategory,
      author: process.env.USER || "Author",
    };
  }

  await createPlugin(config);
}

async function interactiveInit(): Promise<PluginConfig> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const question = (prompt: string): Promise<string> => {
    return new Promise((resolve) => {
      rl.question(prompt, resolve);
    });
  };

  console.log(chalk.bold("Create a new Claude Code plugin"));
  console.log("");

  const name = await question(chalk.cyan("Plugin name: "));
  const description = await question(chalk.cyan("Description: "));

  console.log("");
  console.log(chalk.bold("Plugin types:"));
  Object.entries(PLUGIN_TYPE_DESCRIPTIONS).forEach(([key, desc]) => {
    console.log(chalk.gray(`  ${key}: ${desc}`));
  });
  const type = (await question(chalk.cyan("Type (skill): "))) || "skill";

  console.log("");
  console.log(chalk.bold("Categories:"));
  Object.entries(CATEGORY_DESCRIPTIONS).forEach(([key, desc]) => {
    console.log(chalk.gray(`  ${key}: ${desc}`));
  });
  const category =
    (await question(chalk.cyan("Category (development): "))) || "development";

  const author =
    (await question(
      chalk.cyan(`Author (${process.env.USER || "Author"}): `),
    )) ||
    process.env.USER ||
    "Author";

  rl.close();

  return {
    name: name || "my-plugin",
    description: description || "A Claude Code plugin",
    type: type as PluginType,
    category: category as PluginCategory,
    author,
  };
}

async function createPlugin(config: PluginConfig): Promise<void> {
  const pluginDir = config.name;

  console.log("");
  console.log(chalk.blue(`Creating plugin: ${config.name}`));

  // Create directory structure
  await mkdir(pluginDir, { recursive: true });

  // Create plugin.json
  const manifest = {
    name: config.name,
    version: "1.0.0",
    description: config.description,
    type: config.type,
    category: config.category,
    author: {
      name: config.author,
    },
    license: "MIT",
    keywords: [],
    main: config.type === "skill" ? "SKILL.md" : "index.md",
  };

  await writeFile(
    join(pluginDir, "plugin.json"),
    JSON.stringify(manifest, null, 2),
  );

  // Create main file based on type
  if (config.type === "skill") {
    await createSkillFile(pluginDir, config);
  } else if (config.type === "command") {
    await createCommandFile(pluginDir, config);
  } else {
    await createGenericFile(pluginDir, config);
  }

  console.log("");
  console.log(chalk.green(`✓ Created plugin "${config.name}"`));
  console.log("");
  console.log("Files created:");
  console.log(chalk.gray(`  ${pluginDir}/plugin.json`));
  console.log(chalk.gray(`  ${pluginDir}/${manifest.main}`));
  console.log("");
  console.log("Next steps:");
  console.log(chalk.cyan(`  cd ${pluginDir}`));
  console.log(chalk.cyan("  # Edit the files to add your content"));
  console.log(chalk.cyan("  claude-plugins validate"));
  console.log(chalk.cyan("  claude-plugins install . --local"));
}

async function createSkillFile(
  dir: string,
  config: PluginConfig,
): Promise<void> {
  const content = `---
name: "${config.name}"
description: "${config.description}"
---

# ${config.name}

## What This Skill Does

[Describe what your skill does and its key features]

## Prerequisites

- Claude Code 2.0+
- [Any other requirements]

## Quick Start

\`\`\`bash
# Basic usage example
# Add your commands here
\`\`\`

## Step-by-Step Guide

### Step 1: Setup

[Describe the setup process]

### Step 2: Usage

[Describe how to use the skill]

### Step 3: Verification

[Describe how to verify it's working]

## Configuration

[Describe any configuration options]

## Troubleshooting

### Issue: Common Problem

**Symptoms**: What you see

**Solution**: How to fix it

## Resources

- [Link to documentation]
- [Link to related resources]
`;

  await writeFile(join(dir, "SKILL.md"), content);
}

async function createCommandFile(
  dir: string,
  config: PluginConfig,
): Promise<void> {
  const content = `# ${config.name}

${config.description}

## Usage

\`\`\`
/${config.name} [options]
\`\`\`

## Options

- \`--option1\`: Description of option 1
- \`--option2\`: Description of option 2

## Examples

### Basic Example

\`\`\`
/${config.name}
\`\`\`

### Advanced Example

\`\`\`
/${config.name} --option1 value
\`\`\`

## Notes

[Add any additional notes or caveats]
`;

  await writeFile(join(dir, "index.md"), content);
}

async function createGenericFile(
  dir: string,
  config: PluginConfig,
): Promise<void> {
  const content = `# ${config.name}

${config.description}

## Overview

[Describe what this plugin does]

## Installation

Install via the Claude Plugin Marketplace:

\`\`\`bash
claude-plugins install ${config.name}
\`\`\`

## Usage

[Describe how to use this plugin]

## Configuration

[Describe configuration options]

## Contributing

[Describe how to contribute]

## License

MIT
`;

  await writeFile(join(dir, "index.md"), content);
}
