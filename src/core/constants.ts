/**
 * Constants for Claude Plugin Marketplace
 */

import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { homedir } from "os";

// Get directory paths
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Plugin directories
export const CLAUDE_DIR = ".claude";
export const SKILLS_DIR = "skills";
export const COMMANDS_DIR = "commands";
export const PLUGINS_DIR = "plugins";

// Default paths
export const USER_CLAUDE_DIR = join(homedir(), CLAUDE_DIR);
export const USER_SKILLS_DIR = join(USER_CLAUDE_DIR, SKILLS_DIR);
export const USER_COMMANDS_DIR = join(USER_CLAUDE_DIR, COMMANDS_DIR);
export const USER_PLUGINS_DIR = join(USER_CLAUDE_DIR, PLUGINS_DIR);

// Plugin manifest filename
export const MANIFEST_FILENAME = "plugin.json";
export const SKILL_FILENAME = "SKILL.md";
export const COMMAND_FILENAME = "*.md";

// Registry
export const REGISTRY_URL = "https://registry.claude-plugins.dev";
export const REGISTRY_API_VERSION = "v1";

// Cache
export const CACHE_DIR = join(USER_CLAUDE_DIR, ".cache", "plugins");
export const CACHE_TTL = 3600 * 1000; // 1 hour in milliseconds

// Validation limits
export const MAX_PLUGIN_SIZE = 10 * 1024 * 1024; // 10MB
export const MAX_FILE_SIZE = 1 * 1024 * 1024; // 1MB per file
export const MAX_FILES_COUNT = 100;
export const MAX_NAME_LENGTH = 50;
export const MAX_DESCRIPTION_LENGTH = 500;
export const MAX_KEYWORDS = 10;
export const MAX_KEYWORD_LENGTH = 30;

// Version constraints
export const MIN_CLAUDE_VERSION = "2.0.0";

// File patterns to ignore during packaging
export const IGNORE_PATTERNS = [
  "node_modules/**",
  ".git/**",
  ".gitignore",
  ".DS_Store",
  "Thumbs.db",
  "*.log",
  "*.tmp",
  ".env",
  ".env.*",
  "dist/**",
  "build/**",
  "coverage/**",
  ".nyc_output/**",
  "*.test.ts",
  "*.spec.ts",
  "__tests__/**",
];

// Required files for different plugin types
export const REQUIRED_FILES: Record<string, string[]> = {
  skill: [SKILL_FILENAME],
  command: [], // Commands just need a .md file
  hook: ["hooks.json"],
  "mcp-server": ["mcp-server.json"],
  "mcp-tool": ["mcp-tool.json"],
  template: ["template.json"],
  workflow: ["workflow.json"],
  extension: [], // Extensions are flexible
};

// Plugin type descriptions
export const PLUGIN_TYPE_DESCRIPTIONS: Record<string, string> = {
  skill:
    "Claude Code skill with SKILL.md - provides reusable instructions and workflows",
  command: "Claude Code command - adds slash commands to Claude",
  hook: "Hook integration - runs code at specific lifecycle events",
  "mcp-server":
    "MCP server - provides tools and resources via Model Context Protocol",
  "mcp-tool": "MCP tool - individual tool for MCP servers",
  template:
    "Project template - scaffolds new projects with predefined structure",
  workflow: "Workflow automation - defines automated multi-step processes",
  extension:
    "General extension - flexible plugin type for custom functionality",
};

// Category descriptions
export const CATEGORY_DESCRIPTIONS: Record<string, string> = {
  development: "Tools for software development and coding",
  productivity: "Tools to improve workflow efficiency",
  automation: "Automated tasks and processes",
  integration: "Integrations with external services and APIs",
  "ai-ml": "AI and machine learning tools",
  data: "Data processing and analysis",
  security: "Security scanning and vulnerability detection",
  testing: "Testing frameworks and utilities",
  documentation: "Documentation generation and management",
  devops: "DevOps and CI/CD tools",
  utilities: "General utility tools",
  other: "Other plugins",
};
