---
name: "Code Reviewer"
description: "AI-powered code review assistant that analyzes code for bugs, security issues, and best practices. Use when reviewing pull requests, refactoring code, or improving code quality."
---

# Code Reviewer

## What This Skill Does

The Code Reviewer skill helps you perform thorough code reviews by:

1. **Finding bugs** - Identifies potential runtime errors, edge cases, and logic issues
2. **Security analysis** - Detects common security vulnerabilities (OWASP Top 10)
3. **Best practices** - Suggests improvements following language-specific conventions
4. **Performance** - Highlights performance bottlenecks and optimization opportunities

## Prerequisites

- Claude Code 2.0+
- Git repository with code to review

## Quick Start

```bash
# Review a specific file
"Review this file for issues: src/auth/login.ts"

# Review recent changes
"Review my git diff for any problems"

# Review a pull request
"Review PR #123 and provide feedback"
```

## Step-by-Step Guide

### Step 1: Select Code to Review

You can review code in several ways:

- Paste code directly
- Reference a file path
- Provide a git diff
- Link to a pull request

### Step 2: Request Review

Ask for a code review with specific focus areas:

```
Review this code focusing on:
- Security vulnerabilities
- Error handling
- Performance issues
- Code style
```

### Step 3: Apply Suggestions

The reviewer will provide:

- **Critical issues** - Must fix before merging
- **Warnings** - Should consider fixing
- **Suggestions** - Nice-to-have improvements
- **Praise** - What's done well

## Configuration

You can customize the review by specifying:

- **Language**: Focus on language-specific issues
- **Framework**: Consider framework conventions (React, Express, etc.)
- **Severity**: Filter by issue severity
- **Categories**: Focus on specific issue types

## Review Categories

### Security

- SQL injection
- XSS vulnerabilities
- Authentication issues
- Authorization flaws
- Secret exposure

### Quality

- Code duplication
- Complex functions
- Missing tests
- Poor naming
- Dead code

### Performance

- N+1 queries
- Memory leaks
- Unnecessary computations
- Missing caching

## Troubleshooting

### Issue: Review is too general

**Solution**: Provide more context about the codebase and specific areas of concern.

### Issue: Missing language-specific suggestions

**Solution**: Specify the programming language and any frameworks being used.

## Resources

- [OWASP Top 10](https://owasp.org/Top10/)
- [Clean Code Principles](https://clean-code-developer.com/)
- [Security Best Practices](https://cheatsheetseries.owasp.org/)
