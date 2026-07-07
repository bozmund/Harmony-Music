#!/usr/bin/env node

const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const readline = require("node:readline");

const workspaceRoot = path.resolve(__dirname, "..");
const flutterRoot = path.join(workspaceRoot, ".flutter");
const flutterBin = path.join(
  flutterRoot,
  "bin",
  process.platform === "win32" ? "flutter.bat" : "flutter",
);
const dartBin = path.join(
  flutterRoot,
  "bin",
  process.platform === "win32" ? "dart.bat" : "dart",
);

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function errorResponse(id, code, message) {
  send({
    jsonrpc: "2.0",
    id,
    error: { code, message },
  });
}

function resolveWorkingDirectory(value) {
  const cwd = path.resolve(workspaceRoot, value || ".");
  const relative = path.relative(workspaceRoot, cwd);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error("working_directory must stay inside the workspace");
  }
  return cwd;
}

function normalizeArgs(args) {
  if (args == null) return [];
  if (!Array.isArray(args)) {
    throw new Error("args must be an array of strings");
  }
  return args.map((arg) => {
    if (typeof arg !== "string") {
      throw new Error("args must be an array of strings");
    }
    return arg;
  });
}

function runCommand(command, params) {
  const args = normalizeArgs(params.args);
  const cwd = resolveWorkingDirectory(params.working_directory);
  const timeoutMs = Number.isFinite(params.timeout_ms)
    ? Math.max(1, Math.min(params.timeout_ms, 10 * 60 * 1000))
    : 120000;
  const maxOutputChars = Number.isFinite(params.max_output_chars)
    ? Math.max(1000, Math.min(params.max_output_chars, 200000))
    : 60000;

  return new Promise((resolve) => {
    const env = {
      ...process.env,
      FLUTTER_ROOT: flutterRoot,
      PATH: `${path.join(flutterRoot, "bin")}${path.delimiter}${process.env.PATH || ""}`,
    };
    const child = spawn(command, args, {
      cwd,
      env,
      shell: process.platform === "win32",
      windowsHide: true,
    });

    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill();
    }, timeoutMs);

    const append = (current, chunk) => {
      const next = current + chunk.toString();
      if (next.length <= maxOutputChars) return next;
      return next.slice(next.length - maxOutputChars);
    };

    child.stdout.on("data", (chunk) => {
      stdout = append(stdout, chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr = append(stderr, chunk);
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      resolve({
        exitCode: 1,
        stdout,
        stderr: `${stderr}${stderr ? "\n" : ""}${error.message}`,
        timedOut,
      });
    });
    child.on("close", (exitCode) => {
      clearTimeout(timer);
      resolve({ exitCode, stdout, stderr, timedOut });
    });
  });
}

const toolInputSchema = {
  type: "object",
  properties: {
    args: {
      type: "array",
      items: { type: "string" },
      description: "Command arguments, for example ['analyze'] or ['test', 'test/foo_test.dart'].",
    },
    working_directory: {
      type: "string",
      description: "Optional workspace-relative working directory. Defaults to the repository root.",
    },
    timeout_ms: {
      type: "number",
      description: "Optional timeout in milliseconds. Defaults to 120000; capped at 600000.",
    },
    max_output_chars: {
      type: "number",
      description: "Optional max combined output characters retained per stream. Defaults to 60000.",
    },
  },
  required: ["args"],
  additionalProperties: false,
};

const tools = [
  {
    name: "flutter",
    description: "Run the repository-local .flutter SDK's flutter command.",
    inputSchema: toolInputSchema,
  },
  {
    name: "dart",
    description: "Run the repository-local .flutter SDK's dart command.",
    inputSchema: toolInputSchema,
  },
];

async function handleRequest(request) {
  const { id, method, params = {} } = request;
  try {
    if (method === "initialize") {
      send({
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {} },
          serverInfo: {
            name: "harmony-flutter-dart",
            version: "1.0.0",
          },
        },
      });
      return;
    }

    if (method === "tools/list") {
      send({ jsonrpc: "2.0", id, result: { tools } });
      return;
    }

    if (method === "tools/call") {
      if (!fs.existsSync(flutterBin) || !fs.existsSync(dartBin)) {
        throw new Error("Missing local .flutter SDK binaries");
      }
      const name = params.name;
      const command = name === "flutter" ? flutterBin : name === "dart" ? dartBin : null;
      if (command == null) {
        throw new Error(`Unknown tool: ${name}`);
      }
      const result = await runCommand(command, params.arguments || {});
      const text = [
        `cwd: ${resolveWorkingDirectory((params.arguments || {}).working_directory)}`,
        `command: ${name} ${normalizeArgs((params.arguments || {}).args).join(" ")}`,
        `exitCode: ${result.exitCode}`,
        result.timedOut ? "timedOut: true" : null,
        result.stdout ? `\nstdout:\n${result.stdout}` : null,
        result.stderr ? `\nstderr:\n${result.stderr}` : null,
      ]
        .filter(Boolean)
        .join("\n");
      send({
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text }],
          isError: result.exitCode !== 0 || result.timedOut,
        },
      });
      return;
    }

    if (id != null) {
      errorResponse(id, -32601, `Unknown method: ${method}`);
    }
  } catch (error) {
    errorResponse(id, -32000, error instanceof Error ? error.message : String(error));
  }
}

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

rl.on("line", (line) => {
  if (!line.trim()) return;
  try {
    const request = JSON.parse(line);
    void handleRequest(request);
  } catch (error) {
    errorResponse(null, -32700, error instanceof Error ? error.message : String(error));
  }
});
