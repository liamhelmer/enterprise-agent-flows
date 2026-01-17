/**
 * Plugin Registry - manages plugin discovery and installation
 */

import {
  readFile,
  writeFile,
  mkdir,
  rm,
  readdir,
  copyFile,
  stat,
} from "fs/promises";
import { join, dirname, basename, relative } from "path";
import { glob } from "glob";
import type {
  PluginManifest,
  RegistryEntry,
  SearchQuery,
  SearchResult,
  InstalledPlugin,
  InstallationStatus,
} from "../core/types.js";
import {
  USER_PLUGINS_DIR,
  USER_SKILLS_DIR,
  USER_COMMANDS_DIR,
  MANIFEST_FILENAME,
  CACHE_DIR,
  CACHE_TTL,
  REGISTRY_URL,
  REGISTRY_API_VERSION,
} from "../core/constants.js";
import {
  slugify,
  generateId,
  formatDate,
  readJsonFile,
  isDirectory,
  isFile,
  getFiles,
} from "../core/utils.js";

/**
 * Local plugin registry for installed plugins
 */
export class LocalRegistry {
  private installedPluginsPath: string;
  private installedPlugins: Map<string, InstalledPlugin> = new Map();
  private loaded = false;

  constructor(basePath?: string) {
    this.installedPluginsPath = join(
      basePath || USER_PLUGINS_DIR,
      "installed.json",
    );
  }

  /**
   * Load installed plugins from disk
   */
  async load(): Promise<void> {
    if (this.loaded) return;

    try {
      if (await isFile(this.installedPluginsPath)) {
        const data = await readJsonFile<Record<string, InstalledPlugin>>(
          this.installedPluginsPath,
        );
        this.installedPlugins = new Map(Object.entries(data));
      }
    } catch (error) {
      console.error("Error loading installed plugins:", error);
      this.installedPlugins = new Map();
    }

    this.loaded = true;
  }

  /**
   * Save installed plugins to disk
   */
  async save(): Promise<void> {
    const dir = dirname(this.installedPluginsPath);
    await mkdir(dir, { recursive: true });

    const data = Object.fromEntries(this.installedPlugins);
    await writeFile(this.installedPluginsPath, JSON.stringify(data, null, 2));
  }

  /**
   * Get all installed plugins
   */
  async getInstalled(): Promise<InstalledPlugin[]> {
    await this.load();
    return Array.from(this.installedPlugins.values());
  }

  /**
   * Get a specific installed plugin
   */
  async getPlugin(name: string): Promise<InstalledPlugin | undefined> {
    await this.load();
    return this.installedPlugins.get(name);
  }

  /**
   * Check if a plugin is installed
   */
  async isInstalled(name: string): Promise<boolean> {
    await this.load();
    return this.installedPlugins.has(name);
  }

  /**
   * Install a plugin from a local path
   */
  async installFromPath(sourcePath: string): Promise<InstalledPlugin> {
    await this.load();

    // Read manifest
    const manifestPath = join(sourcePath, MANIFEST_FILENAME);
    const manifest = await readJsonFile<PluginManifest>(manifestPath);

    // Determine target directory based on plugin type
    const targetDir = this.getTargetDirectory(manifest);
    const pluginDir = join(targetDir, manifest.name);

    // Create target directory
    await mkdir(pluginDir, { recursive: true });

    // Copy all files
    const files = await getFiles(sourcePath);
    for (const file of files) {
      const relativePath = relative(sourcePath, file);
      const targetPath = join(pluginDir, relativePath);
      await mkdir(dirname(targetPath), { recursive: true });
      await copyFile(file, targetPath);
    }

    // Create installed plugin record
    const installedPlugin: InstalledPlugin = {
      manifest,
      installedAt: formatDate(),
      installedVersion: manifest.version,
      path: pluginDir,
      status: "installed",
      enabled: true,
    };

    // Save to registry
    this.installedPlugins.set(manifest.name, installedPlugin);
    await this.save();

    return installedPlugin;
  }

  /**
   * Uninstall a plugin
   */
  async uninstall(name: string): Promise<void> {
    await this.load();

    const plugin = this.installedPlugins.get(name);
    if (!plugin) {
      throw new Error(`Plugin "${name}" is not installed`);
    }

    // Remove plugin directory
    if (await isDirectory(plugin.path)) {
      await rm(plugin.path, { recursive: true });
    }

    // Remove from registry
    this.installedPlugins.delete(name);
    await this.save();
  }

  /**
   * Enable a plugin
   */
  async enable(name: string): Promise<void> {
    await this.load();

    const plugin = this.installedPlugins.get(name);
    if (!plugin) {
      throw new Error(`Plugin "${name}" is not installed`);
    }

    plugin.enabled = true;
    await this.save();
  }

  /**
   * Disable a plugin
   */
  async disable(name: string): Promise<void> {
    await this.load();

    const plugin = this.installedPlugins.get(name);
    if (!plugin) {
      throw new Error(`Plugin "${name}" is not installed`);
    }

    plugin.enabled = false;
    await this.save();
  }

  /**
   * Get target directory for plugin type
   */
  private getTargetDirectory(manifest: PluginManifest): string {
    switch (manifest.type) {
      case "skill":
        return USER_SKILLS_DIR;
      case "command":
        return USER_COMMANDS_DIR;
      default:
        return USER_PLUGINS_DIR;
    }
  }
}

/**
 * Remote plugin registry client
 */
export class RemoteRegistry {
  private baseUrl: string;
  private cacheDir: string;

  constructor(baseUrl: string = REGISTRY_URL) {
    this.baseUrl = `${baseUrl}/${REGISTRY_API_VERSION}`;
    this.cacheDir = CACHE_DIR;
  }

  /**
   * Search for plugins
   */
  async search(query: SearchQuery): Promise<SearchResult> {
    const params = new URLSearchParams();

    if (query.query) params.set("q", query.query);
    if (query.type) params.set("type", query.type);
    if (query.category) params.set("category", query.category);
    if (query.keywords?.length)
      params.set("keywords", query.keywords.join(","));
    if (query.author) params.set("author", query.author);
    if (query.verified !== undefined)
      params.set("verified", String(query.verified));
    if (query.featured !== undefined)
      params.set("featured", String(query.featured));
    params.set("sortBy", query.sortBy);
    params.set("sortOrder", query.sortOrder);
    params.set("page", String(query.page));
    params.set("limit", String(query.limit));

    const url = `${this.baseUrl}/plugins?${params}`;

    try {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`Registry request failed: ${response.statusText}`);
      }
      return (await response.json()) as SearchResult;
    } catch (error) {
      // Return empty results if registry is unavailable
      console.warn("Registry unavailable:", error);
      return {
        total: 0,
        page: query.page,
        limit: query.limit,
        results: [],
      };
    }
  }

  /**
   * Get a plugin by name
   */
  async getPlugin(name: string): Promise<RegistryEntry | null> {
    try {
      const response = await fetch(`${this.baseUrl}/plugins/${name}`);
      if (!response.ok) {
        if (response.status === 404) return null;
        throw new Error(`Registry request failed: ${response.statusText}`);
      }
      return (await response.json()) as RegistryEntry;
    } catch (error) {
      console.warn("Registry unavailable:", error);
      return null;
    }
  }

  /**
   * Get featured plugins
   */
  async getFeatured(limit = 10): Promise<RegistryEntry[]> {
    const result = await this.search({
      featured: true,
      sortBy: "downloads",
      sortOrder: "desc",
      limit,
    });
    return result.results;
  }

  /**
   * Get popular plugins
   */
  async getPopular(limit = 10): Promise<RegistryEntry[]> {
    const result = await this.search({
      sortBy: "downloads",
      sortOrder: "desc",
      limit,
    });
    return result.results;
  }

  /**
   * Get recently updated plugins
   */
  async getRecent(limit = 10): Promise<RegistryEntry[]> {
    const result = await this.search({
      sortBy: "updated",
      sortOrder: "desc",
      limit,
    });
    return result.results;
  }
}

/**
 * Scan local directories for plugins
 */
export async function scanLocalPlugins(): Promise<PluginManifest[]> {
  const plugins: PluginManifest[] = [];

  // Scan skills directory
  if (await isDirectory(USER_SKILLS_DIR)) {
    const skillDirs = await readdir(USER_SKILLS_DIR);
    for (const dir of skillDirs) {
      const manifestPath = join(USER_SKILLS_DIR, dir, MANIFEST_FILENAME);
      if (await isFile(manifestPath)) {
        try {
          const manifest = await readJsonFile<PluginManifest>(manifestPath);
          plugins.push(manifest);
        } catch (error) {
          console.warn(
            `Error reading plugin manifest at ${manifestPath}:`,
            error,
          );
        }
      }
    }
  }

  // Scan commands directory
  if (await isDirectory(USER_COMMANDS_DIR)) {
    const commandDirs = await readdir(USER_COMMANDS_DIR);
    for (const dir of commandDirs) {
      const manifestPath = join(USER_COMMANDS_DIR, dir, MANIFEST_FILENAME);
      if (await isFile(manifestPath)) {
        try {
          const manifest = await readJsonFile<PluginManifest>(manifestPath);
          plugins.push(manifest);
        } catch (error) {
          console.warn(
            `Error reading plugin manifest at ${manifestPath}:`,
            error,
          );
        }
      }
    }
  }

  return plugins;
}
