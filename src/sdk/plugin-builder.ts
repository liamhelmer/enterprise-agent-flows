/**
 * Plugin Builder - Fluent API for creating plugins
 */

import { writeFile, mkdir } from "fs/promises";
import { join } from "path";
import type {
  PluginManifest,
  PluginType,
  PluginCategory,
  PluginAuthor,
  PluginDependency,
  PluginRequirements,
} from "../core/types.js";
import {
  validatePlugin,
  formatValidationResult,
} from "../validation/validator.js";

/**
 * Fluent builder for creating plugin manifests
 */
export class PluginBuilder {
  private manifest: Partial<PluginManifest> = {
    version: "1.0.0",
    license: "MIT",
    keywords: [],
    dependencies: [],
  };

  /**
   * Set the plugin name
   */
  name(name: string): this {
    this.manifest.name = name;
    return this;
  }

  /**
   * Set the plugin version
   */
  version(version: string): this {
    this.manifest.version = version;
    return this;
  }

  /**
   * Set the plugin description
   */
  description(description: string): this {
    this.manifest.description = description;
    return this;
  }

  /**
   * Set the plugin type
   */
  type(type: PluginType): this {
    this.manifest.type = type;
    return this;
  }

  /**
   * Set the plugin category
   */
  category(category: PluginCategory): this {
    this.manifest.category = category;
    return this;
  }

  /**
   * Set the plugin author
   */
  author(author: string | PluginAuthor): this {
    if (typeof author === "string") {
      this.manifest.author = { name: author };
    } else {
      this.manifest.author = author;
    }
    return this;
  }

  /**
   * Set the plugin license
   */
  license(license: string): this {
    this.manifest.license = license;
    return this;
  }

  /**
   * Set the plugin homepage
   */
  homepage(url: string): this {
    this.manifest.homepage = url;
    return this;
  }

  /**
   * Set the plugin repository
   */
  repository(
    url: string,
    type: "git" | "github" | "gitlab" | "bitbucket" = "github",
  ): this {
    this.manifest.repository = { type, url };
    return this;
  }

  /**
   * Set the bugs URL
   */
  bugs(url: string): this {
    this.manifest.bugs = url;
    return this;
  }

  /**
   * Add keywords
   */
  keywords(...keywords: string[]): this {
    this.manifest.keywords = [...(this.manifest.keywords || []), ...keywords];
    return this;
  }

  /**
   * Set the main entry point
   */
  main(main: string): this {
    this.manifest.main = main;
    return this;
  }

  /**
   * Set the files to include
   */
  files(...files: string[]): this {
    this.manifest.files = files;
    return this;
  }

  /**
   * Add a dependency
   */
  dependency(name: string, version: string, optional = false): this {
    this.manifest.dependencies = [
      ...(this.manifest.dependencies || []),
      { name, version, optional },
    ];
    return this;
  }

  /**
   * Set requirements
   */
  requirements(requirements: PluginRequirements): this {
    this.manifest.requirements = requirements;
    return this;
  }

  /**
   * Require a specific Claude version
   */
  requiresClaude(version: string): this {
    this.manifest.requirements = {
      ...this.manifest.requirements,
      claude: version,
    };
    return this;
  }

  /**
   * Require a specific Node.js version
   */
  requiresNode(version: string): this {
    this.manifest.requirements = {
      ...this.manifest.requirements,
      node: version,
    };
    return this;
  }

  /**
   * Mark as private (not publishable)
   */
  private(isPrivate = true): this {
    this.manifest.private = isPrivate;
    return this;
  }

  /**
   * Set pricing info
   */
  pricing(
    type: "free" | "freemium" | "paid" | "subscription",
    price?: number,
  ): this {
    this.manifest.pricing = { type, price };
    return this;
  }

  /**
   * Build the manifest
   */
  build(): PluginManifest {
    // Validate required fields
    if (!this.manifest.name) {
      throw new Error("Plugin name is required");
    }
    if (!this.manifest.description) {
      throw new Error("Plugin description is required");
    }
    if (!this.manifest.type) {
      throw new Error("Plugin type is required");
    }
    if (!this.manifest.category) {
      throw new Error("Plugin category is required");
    }
    if (!this.manifest.author) {
      throw new Error("Plugin author is required");
    }

    // Set default main based on type
    if (!this.manifest.main) {
      this.manifest.main =
        this.manifest.type === "skill" ? "SKILL.md" : "index.md";
    }

    return this.manifest as PluginManifest;
  }

  /**
   * Write the manifest to a file
   */
  async write(dir: string): Promise<void> {
    const manifest = this.build();
    await mkdir(dir, { recursive: true });
    await writeFile(
      join(dir, "plugin.json"),
      JSON.stringify(manifest, null, 2),
    );
  }

  /**
   * Validate the built manifest
   */
  async validate(dir: string): Promise<boolean> {
    const result = await validatePlugin(dir);
    if (!result.valid) {
      console.error(formatValidationResult(result));
    }
    return result.valid;
  }
}

/**
 * Create a new plugin builder
 */
export function createPlugin(): PluginBuilder {
  return new PluginBuilder();
}

/**
 * Quick plugin creation helper
 */
export function definePlugin(options: {
  name: string;
  description: string;
  type: PluginType;
  category: PluginCategory;
  author: string | PluginAuthor;
  version?: string;
  license?: string;
  keywords?: string[];
}): PluginManifest {
  const builder = new PluginBuilder()
    .name(options.name)
    .description(options.description)
    .type(options.type)
    .category(options.category)
    .author(options.author);

  if (options.version) builder.version(options.version);
  if (options.license) builder.license(options.license);
  if (options.keywords) builder.keywords(...options.keywords);

  return builder.build();
}
