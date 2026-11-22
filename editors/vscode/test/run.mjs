// Tests the TextMate grammar with the tokenizer VS Code itself uses
// (vscode-textmate and vscode-oniguruma): a few lines with the scopes they
// must get, and every .punk file in examples/ without an `invalid` scope.
//
//     npm ci && npm test        (from editors/vscode)

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const vsctm = require("vscode-textmate");
const oniguruma = require("vscode-oniguruma");

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const repo = path.resolve(root, "../..");

const wasm = fs.readFileSync(require.resolve("vscode-oniguruma/release/onig.wasm"));
await oniguruma.loadWASM(wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength));

const registry = new vsctm.Registry({
  onigLib: Promise.resolve({
    createOnigScanner: (patterns) => new oniguruma.OnigScanner(patterns),
    createOnigString: (s) => new oniguruma.OnigString(s),
  }),
  loadGrammar: async (scope) => {
    if (scope !== "source.punk") return null;
    const file = path.join(root, "syntaxes/punk.tmLanguage.json");
    return vsctm.parseRawGrammar(fs.readFileSync(file, "utf8"), file);
  },
});
const grammar = await registry.loadGrammar("source.punk");

function tokenize(text) {
  let state = vsctm.INITIAL;
  const tokens = [];
  text.split("\n").forEach((line, number) => {
    const result = grammar.tokenizeLine(line, state);
    for (const t of result.tokens) {
      tokens.push({ line: number + 1, text: line.slice(t.startIndex, t.endIndex), scopes: t.scopes });
    }
    state = result.ruleStack;
  });
  return tokens;
}

let failures = 0;
function fail(message) {
  failures += 1;
  console.log(`FAIL ${message}`);
}

// [source, token text, a scope it must have] (the first token with that text).
const cases = [
  ['app [main!] { Platform: platform "../platforms/cli/main.roc" }', "app", "keyword.other.header.punk"],
  ['app [main!] { Platform: platform "../platforms/cli/main.roc" }', "platform", "keyword.other.header.punk"],
  ['app [main!] { Platform: platform "../platforms/cli/main.roc" }', "main!", "entity.name.function.effect.punk"],
  ["import Platform.Http exposing [Request, Response]", "import", "keyword.control.import.punk"],
  ["import Platform.Http exposing [Request, Response]", "exposing", "keyword.control.import.punk"],
  ["import Platform.Http exposing [Request, Response]", "Platform.Http", "entity.name.namespace.punk"],
  ["import Json.Decode as D", "as", "keyword.control.import.punk"],
  ["-- a comment", " a comment", "comment.line.double-dash.punk"],
  ["{- a {- nested -} block -}", " block ", "comment.block.punk"],
  ["{-| docs -}", " docs ", "comment.block.documentation.punk"],
  ["type alias Point = { x : Int }", "alias", "keyword.other.type.punk"],
  ["type alias Point = { x : Int }", "Point", "entity.name.type.punk"],
  ["type Shape = Circle Float | Rect Float Float", "Shape", "entity.name.type.punk"],
  ["type Shape = Circle Float | Rect Float Float", "Circle", "entity.name.type.punk"],
  ["add : Int -> Int -> Int", "add", "entity.name.function.punk"],
  ["add : Int -> Int -> Int", "->", "keyword.operator.arrow.punk"],
  ["add = fn a, b ->", "fn", "keyword.other.function.punk"],
  ["add = fn a, b ->", "add", "entity.name.function.punk"],
  ["main! = fn () ->", "main!", "entity.name.function.punk"],
  ["    case shape of", "case", "keyword.control.conditional.punk"],
  ["    case shape of", "of", "keyword.control.conditional.punk"],
  ["    if n < 0 then -1 else 1", "then", "keyword.control.conditional.punk"],
  ["    xs |> fold into 0 with add", "|>", "keyword.operator.pipe.punk"],
  ["    xs |> fold into 0 with add", "fold", "keyword.control.loop.punk"],
  ["    xs |> fold into 0 with add", "with", "keyword.control.loop.punk"],
  ["    total = try (count! x)", "try", "keyword.control.flow.punk"],
  ["    total = try (count! x)", "count!", "entity.name.function.effect.punk"],
  ["    Stdout.line! \"n = ${String.fromInt n}\"", "line!", "variable.function.punk"],
  ["    Stdout.line! \"n = ${String.fromInt n}\"", "${", "punctuation.section.interpolation.begin.punk"],
  ["    Stdout.line! \"n = ${String.fromInt n}\"", "fromInt", "variable.function.punk"],
  ["    Stdout.line! \"a\\nb\"", "\\n", "constant.character.escape.punk"],
  ["    x = 'a'", "'a'", "string.quoted.single.punk"],
  ["    x = 0xff + 1_000 + 3.14", "0xff", "constant.numeric.hex.punk"],
  ["    x = 0xff + 1_000 + 3.14", "1_000", "constant.numeric.integer.punk"],
  ["    x = 0xff + 1_000 + 3.14", "3.14", "constant.numeric.float.punk"],
  ["    List.map .name people", "name", "entity.name.function.accessor.punk"],
  ["    person.name", "name", "variable.other.member.punk"],
  ["    pair.0", "0", "variable.other.member.punk"],
  ["    a /= b && c", "/=", "keyword.operator.comparison.punk"],
  ["    xs ++ ys", "++", "keyword.operator.punk"],
  ["    ok = True", "True", "constant.language.boolean.punk"],
  ["table links : Link\n    key id\n    read everyone", "table", "keyword.other.table.punk"],
  ["table links : Link\n    key id\n    read everyone", "links", "entity.name.table.punk"],
  ["table links : Link\n    key id\n    read everyone", "key", "keyword.other.table.punk"],
  ["table links : Link\n    key id\n    read everyone", "everyone", "constant.language.policy.punk"],
  ["    var x = 1", "var", "invalid.deprecated.punk"],
];

for (const [source, text, scope] of cases) {
  const token = tokenize(source).find((t) => t.text === text);
  if (!token) fail(`${JSON.stringify(source)}: no token ${JSON.stringify(text)}`);
  else if (!token.scopes.includes(scope)) {
    fail(`${JSON.stringify(source)}: ${JSON.stringify(text)} is ${token.scopes.join(" ")}, not ${scope}`);
  }
}

// Every example: no `invalid` scope, and the grammar is back at the top level
// at the end of the file (no comment or string left open).
function punkFiles(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) return entry.name === "node_modules" || entry.name === "target" ? [] : punkFiles(file);
    return entry.name.endsWith(".punk") ? [file] : [];
  });
}

const files = [...punkFiles(path.join(repo, "examples")), ...punkFiles(path.join(repo, "packages"))];
for (const file of files) {
  const text = fs.readFileSync(file, "utf8");
  const tokens = tokenize(text);
  for (const t of tokens) {
    if (t.scopes.some((s) => s.startsWith("invalid"))) {
      fail(`${path.relative(repo, file)}:${t.line}: ${JSON.stringify(t.text)} is ${t.scopes.join(" ")}`);
    }
  }
  const last = tokens[tokens.length - 1];
  const open = last && last.scopes.find((s) => s.startsWith("comment.block") || s.startsWith("string"));
  if (open && last.text.trim() !== "") fail(`${path.relative(repo, file)}: ends inside ${open}`);
}

console.log(`${cases.length} cases, ${files.length} example files, ${failures} failure(s)`);
process.exit(failures === 0 ? 0 : 1);
