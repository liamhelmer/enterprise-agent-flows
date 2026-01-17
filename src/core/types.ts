/**
 * Core types for Claude Plugin Marketplace
 */

import { z } from "zod";

// Plugin Categories
export const PluginCategory = z.enum([
  "development",
  "productivity",
  "automation",
  "integration",
  "ai-ml",
  "data",
  "security",
  "testing",
  "documentation",
  "devops",
  "utilities",
  "other",
]);

export type PluginCategory = z.infer<typeof PluginCategory>;

// Plugin Type - what kind of plugin this is
export const PluginType = z.enum([
  "skill", // Claude Code skill (SKILL.md)
  "command", // Claude Code command (.md)
  "hook", // Hook integration
  "mcp-server", // MCP server plugin
  "mcp-tool", // MCP tool
  "template", // Project template
  "workflow", // Workflow automation
  "extension", // General extension
]);

export type PluginType = z.infer<typeof PluginType>;

// Plugin Author
export const PluginAuthor = z.object({
  name: z.string().min(1).max(100),
  email: z.string().email().optional(),
  url: z.string().url().optional(),
  github: z.string().optional(),
});

export type PluginAuthor = z.infer<typeof PluginAuthor>;

// Plugin Repository
export const PluginRepository = z.object({
  type: z.enum(["git", "github", "gitlab", "bitbucket"]).default("git"),
  url: z.string().url(),
});

export type PluginRepository = z.infer<typeof PluginRepository>;

// Plugin Dependency
export const PluginDependency = z.object({
  name: z.string(),
  version: z.string(),
  optional: z.boolean().default(false),
});

export type PluginDependency = z.infer<typeof PluginDependency>;

// Plugin Requirements
export const PluginRequirements = z.object({
  claude: z.string().optional(), // Claude Code version requirement
  node: z.string().optional(), // Node.js version requirement
  os: z.array(z.enum(["darwin", "linux", "win32"])).optional(),
  tools: z.array(z.string()).optional(), // Required CLI tools
});

export type PluginRequirements = z.infer<typeof PluginRequirements>;

// Plugin Configuration Schema
export const PluginConfigSchema = z.object({
  type: z.literal("object"),
  properties: z
    .record(
      z.object({
        type: z.string(),
        description: z.string().optional(),
        default: z.any().optional(),
        required: z.boolean().optional(),
      }),
    )
    .optional(),
});

export type PluginConfigSchema = z.infer<typeof PluginConfigSchema>;

// Plugin Manifest - the main plugin.json schema
export const PluginManifest = z.object({
  // Required fields
  name: z
    .string()
    .min(3, "Plugin name must be at least 3 characters")
    .max(50, "Plugin name must be at most 50 characters")
    .regex(
      /^[a-z0-9-]+$/,
      "Plugin name must be lowercase alphanumeric with hyphens",
    ),
  version: z
    .string()
    .regex(/^\d+\.\d+\.\d+(-[a-z0-9.]+)?$/i, "Version must be semver"),
  description: z
    .string()
    .min(10, "Description must be at least 10 characters")
    .max(500, "Description must be at most 500 characters"),

  // Plugin classification
  type: PluginType,
  category: PluginCategory,

  // Author information
  author: PluginAuthor,

  // Optional metadata
  license: z.string().default("MIT"),
  homepage: z.string().url().optional(),
  repository: PluginRepository.optional(),
  bugs: z.string().url().optional(),

  // Keywords for discovery
  keywords: z.array(z.string().max(30)).max(10).default([]),

  // Plugin content
  main: z.string().default("SKILL.md"), // Main entry point
  files: z.array(z.string()).optional(), // Files to include

  // Dependencies and requirements
  dependencies: z.array(PluginDependency).default([]),
  requirements: PluginRequirements.optional(),

  // Configuration
  config: PluginConfigSchema.optional(),

  // Pricing (for future marketplace features)
  pricing: z
    .object({
      type: z
        .enum(["free", "freemium", "paid", "subscription"])
        .default("free"),
      price: z.number().optional(),
      currency: z.string().default("USD"),
    })
    .optional(),

  // Publishing metadata
  private: z.boolean().default(false),
  publishedAt: z.string().datetime().optional(),
  updatedAt: z.string().datetime().optional(),
});

export type PluginManifest = z.infer<typeof PluginManifest>;

// Registry Entry - extends manifest with marketplace data
export const RegistryEntry = PluginManifest.extend({
  id: z.string().uuid(),
  slug: z.string(),
  downloads: z.number().default(0),
  rating: z.number().min(0).max(5).optional(),
  reviews: z.number().default(0),
  verified: z.boolean().default(false),
  featured: z.boolean().default(false),
  deprecated: z.boolean().default(false),
  deprecationMessage: z.string().optional(),
  versions: z
    .array(
      z.object({
        version: z.string(),
        publishedAt: z.string().datetime(),
        changelog: z.string().optional(),
      }),
    )
    .default([]),
});

export type RegistryEntry = z.infer<typeof RegistryEntry>;

// Search Query
export const SearchQuery = z.object({
  query: z.string().optional(),
  type: PluginType.optional(),
  category: PluginCategory.optional(),
  keywords: z.array(z.string()).optional(),
  author: z.string().optional(),
  verified: z.boolean().optional(),
  featured: z.boolean().optional(),
  sortBy: z
    .enum(["downloads", "rating", "updated", "name"])
    .default("downloads"),
  sortOrder: z.enum(["asc", "desc"]).default("desc"),
  page: z.number().min(1).default(1),
  limit: z.number().min(1).max(100).default(20),
});

export type SearchQuery = z.infer<typeof SearchQuery>;

// Search Result
export const SearchResult = z.object({
  total: z.number(),
  page: z.number(),
  limit: z.number(),
  results: z.array(RegistryEntry),
});

export type SearchResult = z.infer<typeof SearchResult>;

// Installation Status
export const InstallationStatus = z.enum([
  "not_installed",
  "installed",
  "outdated",
  "installing",
  "uninstalling",
  "error",
]);

export type InstallationStatus = z.infer<typeof InstallationStatus>;

// Installed Plugin
export const InstalledPlugin = z.object({
  manifest: PluginManifest,
  installedAt: z.string().datetime(),
  installedVersion: z.string(),
  latestVersion: z.string().optional(),
  path: z.string(),
  status: InstallationStatus,
  enabled: z.boolean().default(true),
});

export type InstalledPlugin = z.infer<typeof InstalledPlugin>;

// Validation Result
export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
  warnings: ValidationWarning[];
}

export interface ValidationError {
  path: string;
  message: string;
  code: string;
}

export interface ValidationWarning {
  path: string;
  message: string;
  code: string;
}

// Plugin Events
export type PluginEvent =
  | { type: "installed"; plugin: PluginManifest }
  | { type: "uninstalled"; pluginName: string }
  | { type: "updated"; plugin: PluginManifest; previousVersion: string }
  | { type: "enabled"; pluginName: string }
  | { type: "disabled"; pluginName: string }
  | { type: "error"; pluginName: string; error: Error };
