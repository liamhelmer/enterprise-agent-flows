/**
 * Plugin Validator - validates plugin manifests and content
 */

import { readFile, access, stat } from "fs/promises";
import { join, extname } from "path";
import * as yaml from "js-yaml";
import {
  PluginManifest,
  ValidationResult,
  type PluginType,
} from "../core/types.js";
import {
  MANIFEST_FILENAME,
  SKILL_FILENAME,
  REQUIRED_FILES,
  MAX_NAME_LENGTH,
  MAX_DESCRIPTION_LENGTH,
} from "../core/constants.js";
import {
  createValidationResult,
  addValidationError,
  addValidationWarning,
  isDirectory,
  isFile,
  getFiles,
  validatePluginSize,
  readJsonFile,
} from "../core/utils.js";

/**
 * Validate a plugin directory
 */
export async function validatePlugin(
  pluginPath: string,
): Promise<ValidationResult> {
  const result = createValidationResult();

  // Check if path exists and is a directory
  if (!(await isDirectory(pluginPath))) {
    addValidationError(
      result,
      pluginPath,
      "Plugin path does not exist or is not a directory",
      "INVALID_PATH",
    );
    return result;
  }

  // Check for plugin.json
  const manifestPath = join(pluginPath, MANIFEST_FILENAME);
  if (!(await isFile(manifestPath))) {
    addValidationError(
      result,
      manifestPath,
      `Missing ${MANIFEST_FILENAME} manifest file`,
      "MISSING_MANIFEST",
    );
    return result;
  }

  // Parse and validate manifest
  let manifest: unknown;
  try {
    manifest = await readJsonFile(manifestPath);
  } catch (error) {
    addValidationError(
      result,
      manifestPath,
      `Invalid JSON in ${MANIFEST_FILENAME}: ${error instanceof Error ? error.message : "Unknown error"}`,
      "INVALID_JSON",
    );
    return result;
  }

  // Validate manifest against schema
  const manifestResult = PluginManifest.safeParse(manifest);
  if (!manifestResult.success) {
    for (const issue of manifestResult.error.issues) {
      addValidationError(
        result,
        `${MANIFEST_FILENAME}:${issue.path.join(".")}`,
        issue.message,
        "SCHEMA_ERROR",
      );
    }
    return result;
  }

  const validatedManifest = manifestResult.data;

  // Validate required files based on plugin type
  await validateRequiredFiles(result, pluginPath, validatedManifest.type);

  // Validate main entry point
  await validateMainEntry(result, pluginPath, validatedManifest);

  // Validate plugin size
  const sizeResult = await validatePluginSize(pluginPath);
  if (!sizeResult.valid) {
    for (const error of sizeResult.errors) {
      addValidationError(result, pluginPath, error, "SIZE_ERROR");
    }
  }

  // Additional validations
  validateName(result, validatedManifest.name);
  validateDescription(result, validatedManifest.description);
  validateKeywords(result, validatedManifest.keywords);
  validateVersion(result, validatedManifest.version);

  // Skill-specific validation
  if (validatedManifest.type === "skill") {
    await validateSkill(result, pluginPath);
  }

  return result;
}

/**
 * Validate required files for plugin type
 */
async function validateRequiredFiles(
  result: ValidationResult,
  pluginPath: string,
  pluginType: PluginType,
): Promise<void> {
  const requiredFiles = REQUIRED_FILES[pluginType] || [];

  for (const file of requiredFiles) {
    const filePath = join(pluginPath, file);
    if (!(await isFile(filePath))) {
      addValidationError(
        result,
        filePath,
        `Missing required file: ${file} (required for ${pluginType} plugins)`,
        "MISSING_REQUIRED_FILE",
      );
    }
  }
}

/**
 * Validate main entry point
 */
async function validateMainEntry(
  result: ValidationResult,
  pluginPath: string,
  manifest: PluginManifest,
): Promise<void> {
  const mainPath = join(pluginPath, manifest.main);
  if (!(await isFile(mainPath))) {
    addValidationError(
      result,
      mainPath,
      `Main entry point "${manifest.main}" not found`,
      "MISSING_MAIN",
    );
  }
}

/**
 * Validate plugin name
 */
function validateName(result: ValidationResult, name: string): void {
  if (name.length > MAX_NAME_LENGTH) {
    addValidationError(
      result,
      "name",
      `Plugin name exceeds maximum length of ${MAX_NAME_LENGTH} characters`,
      "NAME_TOO_LONG",
    );
  }

  if (!/^[a-z0-9-]+$/.test(name)) {
    addValidationError(
      result,
      "name",
      "Plugin name must be lowercase alphanumeric with hyphens only",
      "INVALID_NAME_FORMAT",
    );
  }

  if (name.startsWith("-") || name.endsWith("-")) {
    addValidationError(
      result,
      "name",
      "Plugin name cannot start or end with a hyphen",
      "INVALID_NAME_FORMAT",
    );
  }

  // Reserved names
  const reservedNames = [
    "claude",
    "anthropic",
    "official",
    "admin",
    "api",
    "www",
    "app",
  ];
  if (reservedNames.includes(name)) {
    addValidationError(
      result,
      "name",
      `Plugin name "${name}" is reserved`,
      "RESERVED_NAME",
    );
  }
}

/**
 * Validate description
 */
function validateDescription(
  result: ValidationResult,
  description: string,
): void {
  if (description.length > MAX_DESCRIPTION_LENGTH) {
    addValidationError(
      result,
      "description",
      `Description exceeds maximum length of ${MAX_DESCRIPTION_LENGTH} characters`,
      "DESCRIPTION_TOO_LONG",
    );
  }

  if (description.length < 10) {
    addValidationWarning(
      result,
      "description",
      "Description is very short - consider adding more detail",
      "SHORT_DESCRIPTION",
    );
  }
}

/**
 * Validate keywords
 */
function validateKeywords(result: ValidationResult, keywords: string[]): void {
  if (keywords.length > 10) {
    addValidationError(
      result,
      "keywords",
      "Maximum 10 keywords allowed",
      "TOO_MANY_KEYWORDS",
    );
  }

  for (const keyword of keywords) {
    if (keyword.length > 30) {
      addValidationError(
        result,
        "keywords",
        `Keyword "${keyword}" exceeds maximum length of 30 characters`,
        "KEYWORD_TOO_LONG",
      );
    }
  }
}

/**
 * Validate version
 */
function validateVersion(result: ValidationResult, version: string): void {
  const semverRegex = /^\d+\.\d+\.\d+(-[a-z0-9.]+)?$/i;
  if (!semverRegex.test(version)) {
    addValidationError(
      result,
      "version",
      "Version must follow semantic versioning (e.g., 1.0.0)",
      "INVALID_VERSION",
    );
  }
}

/**
 * Validate skill-specific requirements
 */
async function validateSkill(
  result: ValidationResult,
  pluginPath: string,
): Promise<void> {
  const skillPath = join(pluginPath, SKILL_FILENAME);

  if (!(await isFile(skillPath))) {
    addValidationError(
      result,
      skillPath,
      "Skills must have a SKILL.md file",
      "MISSING_SKILL_FILE",
    );
    return;
  }

  // Read and validate SKILL.md
  const content = await readFile(skillPath, "utf-8");

  // Check for frontmatter
  const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
  if (!frontmatterMatch) {
    addValidationError(
      result,
      skillPath,
      "SKILL.md must start with YAML frontmatter (---)",
      "MISSING_FRONTMATTER",
    );
    return;
  }

  // Parse frontmatter
  try {
    const frontmatter = yaml.load(frontmatterMatch[1]) as Record<
      string,
      unknown
    >;

    if (!frontmatter.name) {
      addValidationError(
        result,
        skillPath,
        'SKILL.md frontmatter must include "name" field',
        "MISSING_SKILL_NAME",
      );
    }

    if (!frontmatter.description) {
      addValidationError(
        result,
        skillPath,
        'SKILL.md frontmatter must include "description" field',
        "MISSING_SKILL_DESCRIPTION",
      );
    }

    if (typeof frontmatter.name === "string" && frontmatter.name.length > 64) {
      addValidationError(
        result,
        skillPath,
        "SKILL.md name must be 64 characters or less",
        "SKILL_NAME_TOO_LONG",
      );
    }

    if (
      typeof frontmatter.description === "string" &&
      frontmatter.description.length > 1024
    ) {
      addValidationError(
        result,
        skillPath,
        "SKILL.md description must be 1024 characters or less",
        "SKILL_DESCRIPTION_TOO_LONG",
      );
    }
  } catch (error) {
    addValidationError(
      result,
      skillPath,
      `Invalid YAML in SKILL.md frontmatter: ${error instanceof Error ? error.message : "Unknown error"}`,
      "INVALID_FRONTMATTER",
    );
  }

  // Check for required sections
  const body = content.replace(/^---\n[\s\S]*?\n---\n?/, "");

  if (!body.includes("## What This Skill Does")) {
    addValidationWarning(
      result,
      skillPath,
      'SKILL.md should include "## What This Skill Does" section',
      "MISSING_SKILL_SECTION",
    );
  }

  if (!body.includes("## Quick Start")) {
    addValidationWarning(
      result,
      skillPath,
      'SKILL.md should include "## Quick Start" section',
      "MISSING_SKILL_SECTION",
    );
  }
}

/**
 * Format validation results for display
 */
export function formatValidationResult(result: ValidationResult): string {
  const lines: string[] = [];

  if (result.valid) {
    lines.push("✅ Plugin validation passed");
  } else {
    lines.push("❌ Plugin validation failed");
  }

  if (result.errors.length > 0) {
    lines.push("");
    lines.push("Errors:");
    for (const error of result.errors) {
      lines.push(`  • ${error.path}: ${error.message} [${error.code}]`);
    }
  }

  if (result.warnings.length > 0) {
    lines.push("");
    lines.push("Warnings:");
    for (const warning of result.warnings) {
      lines.push(`  ⚠ ${warning.path}: ${warning.message} [${warning.code}]`);
    }
  }

  return lines.join("\n");
}
