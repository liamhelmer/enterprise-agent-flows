---
name: "API Tester"
description: "HTTP API testing and documentation tool. Use when testing REST APIs, debugging endpoints, or documenting API behavior."
---

# API Tester

## What This Skill Does

The API Tester skill helps you:

1. **Test APIs** - Send HTTP requests and analyze responses
2. **Debug endpoints** - Troubleshoot API issues with detailed output
3. **Document APIs** - Generate documentation from API interactions
4. **Validate responses** - Check response schemas and status codes

## Prerequisites

- curl installed (for making HTTP requests)
- API endpoint to test

## Quick Start

```bash
# Test a GET endpoint
"Test the GET /api/users endpoint"

# Test with authentication
"Test POST /api/login with username and password"

# Validate response
"Verify the /api/products response matches the schema"
```

## Step-by-Step Guide

### Step 1: Define the Request

Specify the HTTP method, URL, headers, and body:

```
Test the following API:
- Method: POST
- URL: https://api.example.com/users
- Headers: Content-Type: application/json
- Body: { "name": "John", "email": "john@example.com" }
```

### Step 2: Execute and Analyze

The skill will:

1. Make the HTTP request
2. Display the response status and headers
3. Parse and format the response body
4. Highlight any issues

### Step 3: Document Results

Get formatted documentation:

```
Document the API response for /api/users
```

## Request Types

### GET Request

```
GET /api/users
Headers:
  Authorization: Bearer <token>
```

### POST Request

```
POST /api/users
Headers:
  Content-Type: application/json
Body:
  {
    "name": "John Doe",
    "email": "john@example.com"
  }
```

### PUT Request

```
PUT /api/users/123
Headers:
  Content-Type: application/json
Body:
  {
    "name": "Jane Doe"
  }
```

### DELETE Request

```
DELETE /api/users/123
Headers:
  Authorization: Bearer <token>
```

## Response Analysis

The skill analyzes responses for:

- **Status codes** - Success (2xx), redirect (3xx), client error (4xx), server error (5xx)
- **Response time** - Latency measurements
- **Headers** - Content type, caching, CORS
- **Body** - JSON/XML parsing and validation
- **Errors** - Common API error patterns

## Configuration

### Environment Variables

```bash
export API_BASE_URL=https://api.example.com
export API_TOKEN=your-token-here
```

### Request Defaults

Set default headers or authentication for all requests.

## Troubleshooting

### Issue: Connection refused

**Symptoms**: curl: (7) Failed to connect

**Solution**: Verify the API server is running and the URL is correct.

### Issue: 401 Unauthorized

**Symptoms**: API returns 401 status

**Solution**: Check authentication token or credentials.

### Issue: SSL certificate error

**Symptoms**: SSL certificate problem

**Solution**: Verify certificate or use `-k` flag for testing (not recommended for production).

## Resources

- [HTTP Status Codes](https://httpstatuses.com/)
- [REST API Best Practices](https://restfulapi.net/)
- [curl Documentation](https://curl.se/docs/)
