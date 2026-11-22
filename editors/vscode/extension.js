// punk-lang for VS Code: `punk fmt` as the formatter of .punk files, and the
// problems of `punk check --json` as diagnostics. Plain JavaScript without
// dependencies, so there is nothing to build.

const vscode = require("vscode");
const { execFile } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const SEVERITY = {
  error: vscode.DiagnosticSeverity.Error,
  warning: vscode.DiagnosticSeverity.Warning,
  info: vscode.DiagnosticSeverity.Information,
};

function punkCommand(uri) {
  const configured = vscode.workspace.getConfiguration("punk", uri).get("path") || "punk";
  // A relative path such as `zig-out/bin/punk` is relative to the workspace folder.
  if (configured.includes("/") && !path.isAbsolute(configured)) {
    const folder = vscode.workspace.getWorkspaceFolder(uri);
    if (folder) return path.join(folder.uri.fsPath, configured);
  }
  return configured;
}

function run(command, args, cwd) {
  return new Promise((resolve) => {
    execFile(command, args, { cwd, maxBuffer: 16 * 1024 * 1024, timeout: 60_000 }, (error, stdout, stderr) => {
      resolve({ error, code: error && typeof error.code === "number" ? error.code : 0, stdout, stderr });
    });
  });
}

function notFound(result, command, output) {
  if (result.error && result.error.code === "ENOENT") {
    output.appendLine(`punk-lang: '${command}' not found. Install punk or set "punk.path".`);
    return true;
  }
  return false;
}

// `punk fmt` rewrites files in place, so the formatter lays out a copy of the
// editor's text in a temporary file and replaces the whole document with it.
async function format(document, output) {
  const command = punkCommand(document.uri);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "punk-fmt-"));
  const file = path.join(dir, path.basename(document.fileName) || "Main.punk");
  try {
    fs.writeFileSync(file, document.getText());
    const result = await run(command, ["fmt", file], dir);
    if (notFound(result, command, output)) return [];
    if (result.code !== 0) {
      output.appendLine(`punk fmt failed:\n${result.stdout}${result.stderr}`);
      return [];
    }
    const formatted = fs.readFileSync(file, "utf8");
    if (formatted === document.getText()) return [];
    const all = new vscode.Range(document.positionAt(0), document.positionAt(document.getText().length));
    return [vscode.TextEdit.replace(all, formatted)];
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function toDiagnostic(problem) {
  const line = Math.max((problem.line || 1) - 1, 0);
  const column = Math.max((problem.column || 1) - 1, 0);
  const endLine = Math.max((problem.endLine || problem.line || 1) - 1, line);
  let endColumn = Math.max((problem.endColumn || problem.column || 1) - 1, 0);
  if (endLine === line && endColumn <= column) endColumn = column + 1;
  const range = new vscode.Range(line, column, endLine, endColumn);
  const message = problem.title && !problem.message.startsWith(problem.title)
    ? `${problem.title}: ${problem.message}`
    : problem.message;
  const diagnostic = new vscode.Diagnostic(range, message, SEVERITY[problem.severity] ?? vscode.DiagnosticSeverity.Error);
  diagnostic.source = "punk";
  if (problem.code) diagnostic.code = problem.code;
  return diagnostic;
}

// Checks the file on disk (the saved version), from its own folder, so that
// the relative paths in its header and imports resolve.
async function check(document, diagnostics, output) {
  if (document.languageId !== "punk" || document.uri.scheme !== "file") return;
  const command = punkCommand(document.uri);
  const result = await run(command, ["check", "--json", document.fileName], path.dirname(document.fileName));
  if (notFound(result, command, output)) return;
  let report;
  try {
    report = JSON.parse(result.stdout);
  } catch {
    output.appendLine(`punk check gave no JSON:\n${result.stdout}${result.stderr}`);
    return;
  }
  const byFile = new Map();
  for (const problem of report.problems || []) {
    const file = problem.file ? path.resolve(path.dirname(document.fileName), problem.file) : document.fileName;
    if (!byFile.has(file)) byFile.set(file, []);
    byFile.get(file).push(toDiagnostic(problem));
  }
  diagnostics.set(document.uri, byFile.get(document.fileName) || []);
  for (const [file, list] of byFile) {
    if (file !== document.fileName) diagnostics.set(vscode.Uri.file(file), list);
  }
}

function activate(context) {
  const output = vscode.window.createOutputChannel("punk-lang");
  const diagnostics = vscode.languages.createDiagnosticCollection("punk");
  context.subscriptions.push(output, diagnostics);

  context.subscriptions.push(
    vscode.languages.registerDocumentFormattingEditProvider("punk", {
      provideDocumentFormattingEdits: (document) => format(document, output),
    }),
    vscode.workspace.onDidSaveTextDocument((document) => {
      if (vscode.workspace.getConfiguration("punk", document.uri).get("checkOnSave")) {
        check(document, diagnostics, output);
      }
    }),
    vscode.workspace.onDidOpenTextDocument((document) => {
      if (vscode.workspace.getConfiguration("punk", document.uri).get("checkOnSave")) {
        check(document, diagnostics, output);
      }
    }),
    vscode.workspace.onDidCloseTextDocument((document) => diagnostics.delete(document.uri)),
    vscode.commands.registerCommand("punk.check", () => {
      const editor = vscode.window.activeTextEditor;
      if (editor) check(editor.document, diagnostics, output);
    }),
  );
}

function deactivate() {}

module.exports = { activate, deactivate, toDiagnostic };
