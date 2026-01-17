/**
 * Utility functions for Claude Plugin Marketplace
 */

import { createHash } from "crypto";
import { readFile, stat, readdir } from "fs/promises";
import { join, relative, extname } from "path";
import { glob } from "glob";
import * as semver from "semver";
import type {
  PluginManifest,
  ValidationResult,
  ValidationError,
  ValidationWarning,
} from "./types.js";
import {
  IGNORE_PATTERNS,
  MAX_PLUGIN_SIZE,
  MAX_FILE_SIZE,
  MAX_FILES_COUNT,
} from "./constants.js";

/**
 * Generate a slug from a plugin name
 */
export function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

/**
 * Generate a unique ID for a plugin
 */
export function generateId(): string {
  return crypto.randomUUID();
}

/**
 * Calculate checksum for a file or content
 */
export function checksum(content: string | Buffer): string {
  return createHash("sha256").update(content).digest("hex");
}

/**
 * Parse semver version string
 */
export function parseVersion(version: string): semver.SemVer | null {
  return semver.parse(version);
}

/**
 * Compare two versions
 */
export function compareVersions(v1: string, v2: string): number {
  return semver.compare(v1, v2);
}

/**
 * Check if version satisfies a range
 */
export function satisfiesVersion(version: string, range: string): boolean {
  return semver.satisfies(version, range);
}

/**
 * Get the next version based on release type
 */
export function incrementVersion(
  version: string,
  release: "major" | "minor" | "patch",
): string | null {
  return semver.inc(version, release);
}

/**
 * Deep merge objects
 */
export function deepMerge<T extends Record<string, any>>(
  target: T,
  source: Partial<T>,
): T {
  const output = { ...target };

  for (const key in source) {
    if (source[key] !== undefined) {
      if (
        typeof source[key] === "object" &&
        source[key] !== null &&
        !Array.isArray(source[key]) &&
        typeof target[key] === "object" &&
        target[key] !== null &&
        !Array.isArray(target[key])
      ) {
        output[key] = deepMerge(target[key], source[key] as any);
      } else {
        output[key] = source[key] as T[Extract<keyof T, string>];
      }
    }
  }

  return output;
}

/**
 * Format bytes to human readable string
 */
export function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 Bytes";

  const k = 1024;
  const sizes = ["Bytes", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));

  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
}

/**
 * Format date to ISO string
 */
export function formatDate(date: Date = new Date()): string {
  return date.toISOString();
}

/**
 * Get all files in a directory matching patterns
 */
export async function getFiles(
  dir: string,
  ignorePatterns: string[] = IGNORE_PATTERNS,
): Promise<string[]> {
  const files = await glob("**/*", {
    cwd: dir,
    nodir: true,
    ignore: ignorePatterns,
    dot: false,
  });

  return files.map((f) => join(dir, f));
}

/**
 * Calculate total size of files
 */
export async function calculateSize(files: string[]): Promise<number> {
  let totalSize = 0;

  for (const file of files) {
    const stats = await stat(file);
    totalSize += stats.size;
  }

  return totalSize;
}

/**
 * Validate plugin size and file count
 */
export async function validatePluginSize(
  dir: string,
): Promise<{
  valid: boolean;
  errors: string[];
  totalSize: number;
  fileCount: number;
}> {
  const errors: string[] = [];
  const files = await getFiles(dir);
  const fileCount = files.length;

  if (fileCount > MAX_FILES_COUNT) {
    errors.push(
      `Plugin has too many files (${fileCount}). Maximum allowed: ${MAX_FILES_COUNT}`,
    );
  }

  let totalSize = 0;

  for (const file of files) {
    const stats = await stat(file);

    if (stats.size > MAX_FILE_SIZE) {
      const relativePath = relative(dir, file);
      errors.push(
        `File "${relativePath}" is too large (${formatBytes(stats.size)}). ` +
          `Maximum allowed: ${formatBytes(MAX_FILE_SIZE)}`,
      );
    }

    totalSize += stats.size;
  }

  if (totalSize > MAX_PLUGIN_SIZE) {
    errors.push(
      `Plugin total size (${formatBytes(totalSize)}) exceeds maximum (${formatBytes(MAX_PLUGIN_SIZE)})`,
    );
  }

  return {
    valid: errors.length === 0,
    errors,
    totalSize,
    fileCount,
  };
}

/**
 * Read and parse a JSON file
 */
export async function readJsonFile<T>(filepath: string): Promise<T> {
  const content = await readFile(filepath, "utf-8");
  return JSON.parse(content) as T;
}

/**
 * Check if a path exists and is a directory
 */
export async function isDirectory(path: string): Promise<boolean> {
  try {
    const stats = await stat(path);
    return stats.isDirectory();
  } catch {
    return false;
  }
}

/**
 * Check if a path exists and is a file
 */
export async function isFile(path: string): Promise<boolean> {
  try {
    const stats = await stat(path);
    return stats.isFile();
  } catch {
    return false;
  }
}

/**
 * Get file extension
 */
export function getExtension(filename: string): string {
  return extname(filename).toLowerCase();
}

/**
 * Create an empty validation result
 */
export function createValidationResult(): ValidationResult {
  return {
    valid: true,
    errors: [],
    warnings: [],
  };
}

/**
 * Add error to validation result
 */
export function addValidationError(
  result: ValidationResult,
  path: string,
  message: string,
  code: string,
): void {
  result.valid = false;
  result.errors.push({ path, message, code });
}

/**
 * Add warning to validation result
 */
export function addValidationWarning(
  result: ValidationResult,
  path: string,
  message: string,
  code: string,
): void {
  result.warnings.push({ path, message, code });
}

/**
 * Truncate string to max length
 */
export function truncate(str: string, maxLength: number): string {
  if (str.length <= maxLength) return str;
  return str.slice(0, maxLength - 3) + "...";
}

/**
 * Escape HTML entities
 */
export function escapeHtml(str: string): string {
  const htmlEntities: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  };

  return str.replace(/[&<>"']/g, (char) => htmlEntities[char]);
}

/**
 * Parse author string to object
 */
export function parseAuthor(
  author: string | { name: string; email?: string; url?: string },
): {
  name: string;
  email?: string;
  url?: string;
} {
  if (typeof author === "object") {
    return author;
  }

  // Parse "Name <email> (url)" format
  const match = author.match(/^([^<(]+)(?:\s*<([^>]+)>)?(?:\s*\(([^)]+)\))?$/);

  if (match) {
    return {
      name: match[1].trim(),
      email: match[2]?.trim(),
      url: match[3]?.trim(),
    };
  }

  return { name: author.trim() };
}

/**
 * Format author object to string
 */
export function formatAuthor(author: {
  name: string;
  email?: string;
  url?: string;
}): string {
  let result = author.name;
  if (author.email) result += ` <${author.email}>`;
  if (author.url) result += ` (${author.url})`;
  return result;
}
