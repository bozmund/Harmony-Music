/**
 * Harmony project Plan/Agent mode.
 *
 * Plan mode is read-only plus validation: inspect the problem, design a failing
 * test, run dart analyze / flutter test, then switch to Agent mode to edit.
 */

import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import * as readline from "node:readline";
import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Key } from "@earendil-works/pi-tui";

const WORKSPACE_ROOT = "C:\\MyRepositories\\Harmony-Music";
const MCP_SERVER = "C:\\MyRepositories\\Harmony-Music\\mcp\\flutter_dart_server.js";
const PLANS_DIRECTORY = path.join(WORKSPACE_ROOT, "plans");

const CUSTOM_TOOLS = ["harmony_flutter_test", "harmony_dart_analyze"];
const PLAN_MODE_TOOLS = ["read", "bash", "grep", "find", "ls", "questionnaire", ...CUSTOM_TOOLS];
const AGENT_MODE_TOOLS = ["read", "bash", "edit", "write", ...CUSTOM_TOOLS];
const PLAN_MODE_DISABLED_TOOLS = new Set<string>(["edit", "write"]);
const PLAN_MANAGED_TOOLS = new Set<string>([...PLAN_MODE_TOOLS, ...AGENT_MODE_TOOLS]);

type HarmonyMode = "agent" | "plan" | "plan-tdd";

interface PlanModeState {
	mode?: HarmonyMode;
	enabled?: boolean;
	toolsBeforePlanMode?: string[];
	lastReviewedPlanFingerprint?: string;
}

interface McpResponse {
	jsonrpc: "2.0";
	id?: number;
	result?: {
		content?: Array<{ type: string; text?: string }>;
		isError?: boolean;
	};
	error?: { code: number; message: string };
}

function uniqueToolNames(toolNames: string[]): string[] {
	return [...new Set(toolNames)];
}

function splitCommandChain(command: string): string[] {
	return command
		.split(/&&/)
		.map((part) => part.trim())
		.filter(Boolean);
}

function normalizeCommandPart(part: string): string {
	return part.replace(/^cmd\s*\/c\s+/i, "").trim();
}

function isSafeCd(part: string): boolean {
	const match = part.match(/^(?:cd|chdir)\s+(.+)$/i);
	if (!match) return false;
	const rawTarget = match[1].trim().replace(/^["']|["']$/g, "");
	let normalized = rawTarget.replace(/\//g, "\\").toLowerCase();
	if (normalized.startsWith("\\myrepositories\\harmony-music")) {
		normalized = `c:${normalized}`;
	}
	const workspace = WORKSPACE_ROOT.toLowerCase();
	return normalized === workspace || normalized.startsWith(`${workspace}\\`);
}

function isSafeGit(part: string): boolean {
	const command = normalizeCommandPart(part);
	const match = command.match(/^git\s+([a-z0-9-]+)\b(.*)$/i);
	if (!match) return false;

	const subcommand = match[1].toLowerCase();
	const args = match[2] ?? "";

	if (
		/\b(--output|--exec-path=|--git-dir=|--work-tree=)\b/i.test(args) ||
		/[<>|;]/.test(args)
	) {
		return false;
	}

	switch (subcommand) {
		case "status":
		case "log":
		case "show":
		case "diff":
		case "grep":
		case "blame":
		case "annotate":
		case "shortlog":
		case "whatchanged":
		case "range-diff":
		case "ls-files":
		case "ls-tree":
		case "ls-remote":
		case "show-ref":
		case "for-each-ref":
		case "rev-parse":
		case "rev-list":
		case "merge-base":
		case "name-rev":
		case "describe":
		case "cherry":
		case "cat-file":
		case "diff-files":
		case "diff-index":
		case "diff-tree":
		case "check-ignore":
		case "check-attr":
		case "check-mailmap":
		case "check-ref-format":
		case "count-objects":
		case "fsck":
		case "verify-commit":
		case "verify-tag":
		case "verify-pack":
		case "var":
		case "version":
		case "help":
			return true;
		case "branch":
			return !/\s-[dDmM]\b|--delete|--move|--copy|--set-upstream-to|--unset-upstream/i.test(args);
		case "tag":
			return /^\s*(?:$|--list\b|-l\b)/i.test(args);
		case "remote":
			return /^\s*(?:$|-v\b|show\b|get-url\b)/i.test(args);
		case "worktree":
			return /^\s+list\b/i.test(args);
		case "stash":
			return /^\s+(?:list|show)\b/i.test(args);
		case "reflog":
			return /^\s*(?:$|show\b)/i.test(args);
		case "config":
			return /^\s+(?:--get\b|--get-regexp\b|--list\b|--show-origin\s+--list\b)/i.test(args);
		default:
			return false;
	}
}

function isSafeNonGit(part: string): boolean {
	return [
		/^\s*cat\b/i,
		/^\s*head\b/i,
		/^\s*tail\b/i,
		/^\s*less\b/i,
		/^\s*more\b/i,
		/^\s*grep\b/i,
		/^\s*find\b/i,
		/^\s*ls\b/i,
		/^\s*dir\b/i,
		/^\s*pwd\b/i,
		/^\s*echo\b/i,
		/^\s*printf\b/i,
		/^\s*wc\b/i,
		/^\s*sort\b/i,
		/^\s*uniq\b/i,
		/^\s*diff\b/i,
		/^\s*file\b/i,
		/^\s*stat\b/i,
		/^\s*tree\b/i,
		/^\s*where\b/i,
		/^\s*type\b/i,
		/^\s*env\b/i,
		/^\s*printenv\b/i,
		/^\s*whoami\b/i,
		/^\s*date\b/i,
		/^\s*rg\b/i,
		/^\s*fd\b/i,
		/^\s*jq\b/i,
		/^\s*sed\s+-n\b/i,
		/^\s*awk\b/i,
		/^\s*node\s+--version\b/i,
		/^\s*dart\s+--version\b/i,
		/^\s*flutter\s+--version\b/i,
	].some((pattern) => pattern.test(part));
}

function isSafeCommand(command: string): boolean {
	if (/[<>|;]/.test(command)) return false;

	const parts = splitCommandChain(command);
	if (parts.length === 0) return false;

	return parts.every((rawPart) => {
		const part = normalizeCommandPart(rawPart);
		return isSafeCd(part) || isSafeGit(part) || isSafeNonGit(part);
	});
}

function validateRelativeWorkingDirectory(value: string | undefined): string {
	const workingDirectory = value?.trim() || ".";
	if (workingDirectory.includes("..") || /^[a-z]:/i.test(workingDirectory) || workingDirectory.startsWith("/") || workingDirectory.startsWith("\\")) {
		throw new Error("working_directory must be relative and stay inside Harmony-Music");
	}
	return workingDirectory;
}

function truncateText(value: string, maxChars: number): string {
	if (value.length <= maxChars) return value;
	return `${value.slice(0, maxChars)}\n\n[truncated to ${maxChars} characters]`;
}

function getAssistantText(message: unknown): string {
	const candidate = message as { role?: string; content?: unknown };
	if (candidate.role !== "assistant" || !Array.isArray(candidate.content)) return "";

	return candidate.content
		.filter((block): block is { type: string; text: string } => {
			if (!block || typeof block !== "object") return false;
			const content = block as { type?: unknown; text?: unknown };
			return content.type === "text" && typeof content.text === "string";
		})
		.map((block) => block.text)
		.join("\n")
		.trim();
}

function hasCompletedPlan(text: string, mode: HarmonyMode): boolean {
	const heading = mode === "plan-tdd" ? "TDD Plan" : "Plan";
	const pattern = new RegExp(`^\\s*(?:#{1,6}\\s*)?(?:\\*{1,2})?${heading}:?(?:\\*{1,2})?\\s*$`, "im");
	return pattern.test(text);
}

function fingerprintPlan(text: string): string {
	return createHash("sha256").update(text).digest("hex");
}

function planSlug(text: string): string {
	const firstLine = text.split(/\r?\n/).map((line) => line.trim()).find(Boolean) ?? "plan";
	const slug = firstLine
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-+|-+$/g, "")
		.slice(0, 48);
	return slug || "plan";
}

function saveAcceptedPlan(text: string, acceptedMode: HarmonyMode): string {
	fs.mkdirSync(PLANS_DIRECTORY, { recursive: true });
	const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
	const baseName = `${timestamp}-${planSlug(text)}`;
	let filePath = path.join(PLANS_DIRECTORY, `${baseName}.md`);
	let suffix = 2;
	while (fs.existsSync(filePath)) {
		filePath = path.join(PLANS_DIRECTORY, `${baseName}-${suffix}.md`);
		suffix += 1;
	}

	const savedAt = new Date().toISOString();
	fs.writeFileSync(
		filePath,
		`# Accepted Harmony Plan\n\nSaved: ${savedAt}\nMode: ${acceptedMode === "plan-tdd" ? "PLAN:TDD" : "PLAN"}\n\n${text}\n`,
		"utf8",
	);
	return filePath;
}

async function callMcpTool(
	name: "flutter" | "dart",
	args: string[],
	options: { workingDirectory?: string; timeoutMs?: number; maxOutputChars?: number },
): Promise<{ text: string; isError: boolean }> {
	let nextId = 1;
	const pending = new Map<number, (response: McpResponse) => void>();
	const child: ChildProcessWithoutNullStreams = spawn("node", [MCP_SERVER], {
		cwd: WORKSPACE_ROOT,
		windowsHide: true,
	});

	const rl = readline.createInterface({ input: child.stdout, crlfDelay: Infinity });
	rl.on("line", (line) => {
		try {
			const response = JSON.parse(line) as McpResponse;
			if (typeof response.id === "number") {
				pending.get(response.id)?.(response);
				pending.delete(response.id);
			}
		} catch {
			// Ignore non-JSON server output.
		}
	});

	let stderr = "";
	child.stderr.on("data", (chunk) => {
		stderr = truncateText(`${stderr}${chunk.toString()}`, 20000);
	});

	const request = (method: string, params?: unknown, timeoutMs = 15000): Promise<McpResponse> => {
		const id = nextId++;
		const payload = { jsonrpc: "2.0", id, method, params };
		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => {
				pending.delete(id);
				reject(new Error(`MCP request timed out: ${method}`));
			}, timeoutMs);
			pending.set(id, (response) => {
				clearTimeout(timer);
				resolve(response);
			});
			child.stdin.write(`${JSON.stringify(payload)}\n`);
		});
	};

	try {
		await request("initialize", {}, 15000);
		await request("tools/list", {}, 15000);
		const timeoutMs = Math.max(1, Math.min(options.timeoutMs ?? 300000, 600000));
		const response = await request(
			"tools/call",
			{
				name,
				arguments: {
					args,
					working_directory: validateRelativeWorkingDirectory(options.workingDirectory),
					timeout_ms: timeoutMs,
					max_output_chars: Math.max(1000, Math.min(options.maxOutputChars ?? 60000, 200000)),
				},
			},
			timeoutMs + 15000,
		);

		if (response.error) {
			return { text: `MCP error ${response.error.code}: ${response.error.message}`, isError: true };
		}
		const text = response.result?.content?.map((item) => item.text ?? "").join("\n") ?? "";
		return { text: stderr ? `${text}\n\nserver stderr:\n${stderr}` : text, isError: response.result?.isError === true };
	} finally {
		rl.close();
		child.kill();
	}
}

const flutterTestTool = defineTool({
	name: "harmony_flutter_test",
	label: "Harmony Flutter Test",
	description: "Run Harmony-Music tests through the repository-local Flutter SDK.",
	promptSnippet: "Run Harmony-Music flutter test commands through the project MCP server",
	promptGuidelines: [
		"Use harmony_flutter_test to run targeted tests before and after fixes in Harmony-Music.",
		"Use harmony_flutter_test with args like ['test', 'test/player_safe_area_test.dart']; do not use it for formatting or code generation.",
	],
	parameters: Type.Object({
		args: Type.Array(Type.String(), {
			description: "Flutter args. Must start with 'test'. Example: ['test', 'test/player_safe_area_test.dart'].",
		}),
		working_directory: Type.Optional(Type.String({ description: "Workspace-relative directory, defaults to repository root." })),
		timeout_ms: Type.Optional(Type.Number({ description: "Timeout in milliseconds; capped at 600000." })),
		max_output_chars: Type.Optional(Type.Number({ description: "Max output chars; capped at 200000." })),
	}),
	async execute(_toolCallId, params) {
		if (params.args[0] !== "test") {
			return {
				content: [{ type: "text", text: "Blocked: harmony_flutter_test only allows flutter test commands." }],
				isError: true,
			};
		}
		const result = await callMcpTool("flutter", params.args, {
			workingDirectory: params.working_directory,
			timeoutMs: params.timeout_ms,
			maxOutputChars: params.max_output_chars,
		});
		return { content: [{ type: "text", text: result.text }], isError: result.isError };
	},
});

const dartAnalyzeTool = defineTool({
	name: "harmony_dart_analyze",
	label: "Harmony Dart Analyze",
	description: "Run a whole-workspace Harmony-Music dart analyze checkpoint through the repository-local Dart SDK.",
	promptSnippet: "Run Harmony-Music dart analyze through the project MCP server",
	promptGuidelines: [
		"Use harmony_dart_analyze after a completed change set or before handoff, not after every small edit.",
		"Prefer focused harmony_flutter_test checks while iterating; use this tool as the whole-workspace analyzer checkpoint.",
		"Use harmony_dart_analyze with args like ['analyze']; do not use it for dart format.",
	],
	parameters: Type.Object({
		args: Type.Array(Type.String(), {
			description: "Dart args. Must start with 'analyze'. Example: ['analyze'].",
		}),
		working_directory: Type.Optional(Type.String({ description: "Workspace-relative directory, defaults to repository root." })),
		timeout_ms: Type.Optional(Type.Number({ description: "Timeout in milliseconds; capped at 600000." })),
		max_output_chars: Type.Optional(Type.Number({ description: "Max output chars; capped at 200000." })),
	}),
	async execute(_toolCallId, params) {
		if (params.args[0] !== "analyze") {
			return {
				content: [{ type: "text", text: "Blocked: harmony_dart_analyze only allows dart analyze commands." }],
				isError: true,
			};
		}
		const result = await callMcpTool("dart", params.args, {
			workingDirectory: params.working_directory,
			timeoutMs: params.timeout_ms,
			maxOutputChars: params.max_output_chars,
		});
		return { content: [{ type: "text", text: result.text }], isError: result.isError };
	},
});

export default function harmonyPlanAgentMode(pi: ExtensionAPI): void {
	let mode: HarmonyMode = "agent";
	let toolsBeforePlanMode: string[] | undefined;
	let lastReviewedPlanFingerprint: string | undefined;

	pi.registerTool(flutterTestTool);
	pi.registerTool(dartAnalyzeTool);

	pi.registerFlag("plan", {
		description: "Start in Harmony TDD plan mode",
		type: "boolean",
		default: false,
	});

	function updateStatus(ctx: ExtensionContext): void {
		const label =
			mode === "agent" ? ctx.ui.theme.fg("success", "AGENT") : ctx.ui.theme.fg("warning", mode === "plan" ? "PLAN" : "PLAN:TDD");
		ctx.ui.setStatus("harmony-plan-agent-mode", label);
	}

	function getPlanModeTools(activeToolNames: string[]): string[] {
		return uniqueToolNames([
			...activeToolNames.filter((name) => !PLAN_MODE_DISABLED_TOOLS.has(name)),
			...PLAN_MODE_TOOLS,
		]);
	}

	function getAgentModeTools(activeToolNames: string[]): string[] {
		return uniqueToolNames([
			...AGENT_MODE_TOOLS,
			...activeToolNames.filter((name) => !PLAN_MANAGED_TOOLS.has(name)),
		]);
	}

	function enablePlanModeTools(): void {
		if (toolsBeforePlanMode === undefined) {
			toolsBeforePlanMode = pi.getActiveTools();
		}
		pi.setActiveTools(getPlanModeTools(toolsBeforePlanMode));
	}

	function restoreAgentModeTools(): void {
		pi.setActiveTools(toolsBeforePlanMode ?? getAgentModeTools(pi.getActiveTools()));
		toolsBeforePlanMode = undefined;
	}

	function persistState(): void {
		pi.appendEntry("harmony-plan-agent-mode", {
			mode,
			toolsBeforePlanMode,
			lastReviewedPlanFingerprint,
		});
	}

	function setMode(nextMode: HarmonyMode, ctx: ExtensionContext): void {
		const wasPlanning = mode !== "agent";
		const isPlanning = nextMode !== "agent";
		mode = nextMode;

		if (!wasPlanning && isPlanning) {
			lastReviewedPlanFingerprint = undefined;
			enablePlanModeTools();
		} else if (wasPlanning && !isPlanning) {
			restoreAgentModeTools();
		}

		if (mode === "agent") {
			ctx.ui.notify("Agent mode enabled. Edit/write restored.");
		} else if (mode === "plan") {
			ctx.ui.notify("Plan mode enabled. Edit/write disabled.");
		} else {
			ctx.ui.notify("Harmony TDD Plan mode enabled. Edit/write disabled; tests and analyze available.");
		}
		updateStatus(ctx);
		persistState();
	}

	function cycleMode(ctx: ExtensionContext): void {
		const nextMode: Record<HarmonyMode, HarmonyMode> = {
			agent: "plan",
			plan: "plan-tdd",
			"plan-tdd": "agent",
		};
		setMode(nextMode[mode], ctx);
	}

	pi.registerCommand("plan", {
		description: "Switch to Harmony Plan mode",
		handler: async (_args, ctx) => setMode("plan", ctx),
	});

	pi.registerCommand("plantdd", {
		description: "Switch to Harmony TDD Plan mode",
		handler: async (_args, ctx) => setMode("plan-tdd", ctx),
	});

	pi.registerCommand("agent", {
		description: "Switch to Harmony Agent mode",
		handler: async (_args, ctx) => setMode("agent", ctx),
	});

	pi.registerShortcut(Key.tab, {
		description: "Cycle Harmony Agent, Plan, and Plan:TDD modes",
		handler: async (ctx) => cycleMode(ctx),
	});

	pi.registerShortcut(Key.ctrlAlt("p"), {
		description: "Cycle Harmony Agent, Plan, and Plan:TDD modes",
		handler: async (ctx) => cycleMode(ctx),
	});

	pi.on("tool_call", async (event) => {
		if (mode === "agent" || event.toolName !== "bash") return;

		const command = event.input.command as string;
		if (!isSafeCommand(command)) {
			return {
				block: true,
				reason: `Harmony Plan mode blocked this bash command because it is not read-only. Use harmony_flutter_test or harmony_dart_analyze for validation, or press Tab to switch to Agent mode for edits.\nCommand: ${command}`,
			};
		}
	});

	pi.on("context", async (event) => {
		if (mode !== "agent") return;

		return {
			messages: event.messages.filter((m) => {
				const msg = m as { role?: string; customType?: string; content?: unknown };
				if (msg.customType === "harmony-plan-agent-mode-context") return false;
				if (msg.role !== "user") return true;
				if (typeof msg.content === "string") return !msg.content.includes("[HARMONY PLAN MODE ACTIVE]");
				return true;
			}),
		};
	});

	pi.on("before_agent_start", async () => {
		if (mode === "agent") return;

		if (mode === "plan") {
			return {
				message: {
					customType: "harmony-plan-agent-mode-context",
					content: `[HARMONY PLAN MODE ACTIVE]
You are in Harmony-Music Plan mode.

Inspect the problem, gather the necessary evidence, and propose the smallest safe implementation approach. Do not edit files in this mode. You may use read-only inspection, Harmony validation tools, and read-only Git commands.

When the plan is ready for review, end the response with this exact shape:

Plan:
1. First implementation step
2. Second implementation step`,
					display: false,
				},
			};
		}

		return {
			message: {
				customType: "harmony-plan-agent-mode-context",
				content: `[HARMONY TDD PLAN MODE ACTIVE]
You are in Harmony-Music TDD Plan mode.

This is a bounded planning task, not an open-ended investigation.
- Use at most three read/search tool calls to identify the relevant code and test location.
- Run at most one targeted validation only when it resolves a concrete uncertainty; validation is optional.
- Once you can name the likely files and a smallest failing test, stop investigating and write the plan.
- Do not re-check, final-review, or keep researching to make the plan more complete.
- If evidence is incomplete, state the assumption in the plan instead of making more tool calls.
- Do not edit files in Plan mode.

Available validation tools:
- harmony_flutter_test: run flutter test commands only.
- harmony_dart_analyze: run dart analyze commands only.

End the response immediately after this concise shape. Keep each item to one or two sentences:

TDD Plan:
1. Evidence and assumption
2. Smallest failing test
3. Expected failing command
4. Minimal implementation
5. Passing command
6. Focused follow-up validation

Plan mode may use read-only Git inspection, including git status, git log, git diff, and git show. Git state-changing commands remain forbidden unless the user explicitly requests that exact Git operation outside Plan mode.`,
				display: false,
			},
		};
	});

	pi.on("agent_end", async (event, ctx) => {
		if (mode === "agent" || !ctx.hasUI) return;

		const lastAssistant = [...event.messages].reverse().find((message) => getAssistantText(message).length > 0);
		const planText = lastAssistant ? getAssistantText(lastAssistant) : "";
		if (!planText || !hasCompletedPlan(planText, mode)) return;

		const fingerprint = fingerprintPlan(planText);
		if (fingerprint === lastReviewedPlanFingerprint) return;
		lastReviewedPlanFingerprint = fingerprint;
		persistState();

		const choice = await ctx.ui.select("Plan ready for review", ["Accept plan", "Refine plan", "Continue planning"]);
		if (choice === "Accept plan") {
			const savedPath = saveAcceptedPlan(planText, mode);
			ctx.ui.notify(`Accepted plan saved to ${savedPath}`);
			setMode("agent", ctx);
			return;
		}

		if (choice === "Refine plan") {
			const refinement = await ctx.ui.editor("Refine the plan:", "");
			if (refinement?.trim()) {
				pi.sendUserMessage(refinement.trim(), { deliverAs: "followUp" });
			}
		}
	});

	pi.on("session_start", async (_event, ctx) => {
		pi.setActiveTools(getAgentModeTools(pi.getActiveTools()));

		if (pi.getFlag("plan") === true) {
			mode = "plan-tdd";
		}

		const entries = ctx.sessionManager.getEntries();
		const planModeEntry = entries
			.filter((e: { type: string; customType?: string }) => e.type === "custom" && e.customType === "harmony-plan-agent-mode")
			.pop() as { data?: PlanModeState } | undefined;

		if (planModeEntry?.data) {
			mode = planModeEntry.data.mode ?? (planModeEntry.data.enabled === true ? "plan-tdd" : mode);
			toolsBeforePlanMode = planModeEntry.data.toolsBeforePlanMode ?? toolsBeforePlanMode;
			lastReviewedPlanFingerprint = planModeEntry.data.lastReviewedPlanFingerprint;
		}

		if (mode !== "agent") {
			enablePlanModeTools();
		}
		updateStatus(ctx);
	});
}
