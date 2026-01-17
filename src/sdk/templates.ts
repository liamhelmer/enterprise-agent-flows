/**
 * Plugin Templates - Pre-built templates for common plugin types
 */

import type {
  PluginManifest,
  PluginType,
  PluginCategory,
} from "../core/types.js";

/**
 * Template for a skill plugin
 */
export function skillTemplate(options: {
  name: string;
  description: string;
  author: string;
  category?: PluginCategory;
}): PluginManifest {
  return {
    name: options.name,
    version: "1.0.0",
    description: options.description,
    type: "skill",
    category: options.category || "development",
    author: { name: options.author },
    license: "MIT",
    keywords: [],
    main: "SKILL.md",
    dependencies: [],
  };
}

/**
 * Template for a command plugin
 */
export function commandTemplate(options: {
  name: string;
  description: string;
  author: string;
  category?: PluginCategory;
}): PluginManifest {
  return {
    name: options.name,
    version: "1.0.0",
    description: options.description,
    type: "command",
    category: options.category || "utilities",
    author: { name: options.author },
    license: "MIT",
    keywords: [],
    main: "index.md",
    dependencies: [],
  };
}

/**
 * Template for an MCP server plugin
 */
export function mcpServerTemplate(options: {
  name: string;
  description: string;
  author: string;
  category?: PluginCategory;
}): PluginManifest {
  return {
    name: options.name,
    version: "1.0.0",
    description: options.description,
    type: "mcp-server",
    category: options.category || "integration",
    author: { name: options.author },
    license: "MIT",
    keywords: ["mcp", "server"],
    main: "mcp-server.json",
    dependencies: [],
    requirements: {
      node: ">=18.0.0",
    },
  };
}

/**
 * Template for a hook plugin
 */
export function hookTemplate(options: {
  name: string;
  description: string;
  author: string;
  category?: PluginCategory;
}): PluginManifest {
  return {
    name: options.name,
    version: "1.0.0",
    description: options.description,
    type: "hook",
    category: options.category || "automation",
    author: { name: options.author },
    license: "MIT",
    keywords: ["hook"],
    main: "hooks.json",
    dependencies: [],
  };
}

/**
 * Template for a workflow plugin
 */
export function workflowTemplate(options: {
  name: string;
  description: string;
  author: string;
  category?: PluginCategory;
}): PluginManifest {
  return {
    name: options.name,
    version: "1.0.0",
    description: options.description,
    type: "workflow",
    category: options.category || "automation",
    author: { name: options.author },
    license: "MIT",
    keywords: ["workflow", "automation"],
    main: "workflow.json",
    dependencies: [],
  };
}

/**
 * SKILL.md template content
 */
export function skillMarkdownTemplate(options: {
  name: string;
  description: string;
}): string {
  return `---
name: "${options.name}"
description: "${options.description}"
---

# ${options.name}

## What This Skill Does

${options.description}

## Prerequisites

- Claude Code 2.0+

## Quick Start

\`\`\`bash
# Basic usage
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
}

/**
 * Command markdown template content
 */
export function commandMarkdownTemplate(options: {
  name: string;
  description: string;
}): string {
  return `# ${options.name}

${options.description}

## Usage

\`\`\`
/${options.name} [options]
\`\`\`

## Options

- \`--option1\`: Description of option 1
- \`--option2\`: Description of option 2

## Examples

### Basic Example

\`\`\`
/${options.name}
\`\`\`

### Advanced Example

\`\`\`
/${options.name} --option1 value
\`\`\`

## Notes

[Add any additional notes or caveats]
`;
}

/**
 * MCP server template content
 */
export function mcpServerConfigTemplate(options: {
  name: string;
  description: string;
}): object {
  return {
    name: options.name,
    description: options.description,
    version: "1.0.0",
    transport: "stdio",
    command: "node",
    args: ["dist/index.js"],
    tools: [],
    resources: [],
  };
}

/**
 * Hooks template content
 */
export function hooksConfigTemplate(options: { name: string }): object {
  return {
    name: options.name,
    hooks: [
      {
        event: "pre-task",
        script: "scripts/pre-task.sh",
        description: "Run before starting a task",
      },
      {
        event: "post-task",
        script: "scripts/post-task.sh",
        description: "Run after completing a task",
      },
    ],
  };
}

/**
 * Workflow template content
 */
export function workflowConfigTemplate(options: {
  name: string;
  description: string;
}): object {
  return {
    name: options.name,
    description: options.description,
    version: "1.0.0",
    steps: [
      {
        id: "step-1",
        name: "First Step",
        type: "task",
        description: "Description of the first step",
        action: "command-to-run",
      },
      {
        id: "step-2",
        name: "Second Step",
        type: "task",
        description: "Description of the second step",
        action: "command-to-run",
        dependsOn: ["step-1"],
      },
    ],
    variables: {},
  };
}
