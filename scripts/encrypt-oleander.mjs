import { createCipheriv, pbkdf2Sync, randomBytes } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";

function readArguments(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index]?.replace(/^--/, "");
    const value = argv[index + 1];
    if (!key || value === undefined) throw new Error(`Invalid argument near ${argv[index] ?? "end"}`);
    result[key] = value;
  }
  return result;
}

async function findHtmlFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...(await findHtmlFiles(entryPath)));
    if (entry.isFile() && entry.name.toLowerCase().endsWith(".html")) files.push(entryPath);
  }
  return files;
}

function encryptedDocument(payload) {
  const payloadJson = JSON.stringify(payload).replaceAll("<", "\\u003c");
  return `<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow, noarchive">
    <title>Oleander</title>
    <link rel="icon" href="/favicon.ico" sizes="any">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <style>
      @import url("https://fonts.googleapis.com/css2?family=Noto+Sans+HK:wght@400;600;700&display=swap");
      :root { --border: #ededed; --muted: #666; --paper: #fcfcfc; --ink: #161616; }
      * { box-sizing: border-box; color: var(--ink); font: inherit; }
      html, body { min-height: 100%; }
      body { align-items: center; background: var(--paper); display: grid; font: .9rem/1.5 "Noto Sans CJK HK", "Noto Sans HK", "Noto Sans", sans-serif; justify-content: center; margin: 0; padding: 3rem 1.5rem; }
      [hidden] { display: none !important; }
      .gate { border: 1px solid var(--border); border-radius: .75rem; box-shadow: 0 1px 2px var(--border); max-width: 60ch; padding: 3rem; width: min(100%, 60ch); }
      .path, .hint, .error { color: var(--muted); font-size: .76rem; }
      .path { margin-top: 0; }
      h1 { font-weight: 700; margin: 1.5em 0; }
      form { display: grid; gap: .75rem; }
      input { background: #f7f7f7; border: 1px solid var(--border); border-radius: .375rem; padding: .75rem; width: 100%; }
      input:focus-visible, button:focus-visible, a:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
      button { background: var(--ink); border: 1px solid var(--ink); border-radius: .375rem; color: var(--paper); cursor: pointer; justify-self: start; padding: .75rem 1.5rem; }
      button:hover { opacity: .82; }
      .error { min-height: 1.5em; margin: 0; }
      a { border-bottom: 1px dotted; text-decoration: none; }
      @media (max-width: 600px) { .gate { padding: 1.5rem; } }
    </style>
    <noscript><style>#oleander-gate { display: block !important; }</style></noscript>
  </head>
  <body>
    <section class="gate" id="oleander-gate" aria-labelledby="oleander-gate-title" hidden>
      <p class="path" aria-hidden="true">Gwok Hiujin / Oleander /</p>
      <h1 id="oleander-gate-title">Oleander</h1>
      <form id="oleander-gate-form">
        <label for="oleander-password">Password</label>
        <input id="oleander-password" name="password" type="password" minlength="5" maxlength="5" pattern="[a-z]{5}" autocomplete="current-password" autocapitalize="none" spellcheck="false" required>
        <p class="hint">请输入 5 个小写英文字母。你知道的，就是那 5 个小写英文字母。</p>
        <p class="error" id="oleander-gate-error" role="status" aria-live="polite"></p>
        <button type="submit">Enter</button>
      </form>
      <p><a href="/">../</a></p>
      <noscript><p>需要启用 JavaScript 才能解密这个分类。</p></noscript>
    </section>
    <script id="oleander-payload" type="application/json">${payloadJson}</script>
    <script>
      (() => {
        "use strict";
        const storageKey = "gwokhiujin:oleander:derived-key";
        const payload = JSON.parse(document.getElementById("oleander-payload").textContent);
        const gate = document.getElementById("oleander-gate");
        const form = document.getElementById("oleander-gate-form");
        const input = document.getElementById("oleander-password");
        const error = document.getElementById("oleander-gate-error");
        const encoder = new TextEncoder();
        const decoder = new TextDecoder();

        const fromBase64 = (value) => Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
        const toBase64 = (value) => {
          let binary = "";
          for (const byte of value) binary += String.fromCharCode(byte);
          return btoa(binary);
        };

        const deriveKey = async (password) => {
          const material = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]);
          const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt: fromBase64(payload.salt), iterations: payload.iterations, hash: "SHA-256" }, material, 256);
          return new Uint8Array(bits);
        };

        const decrypt = async (keyBytes) => {
          const key = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["decrypt"]);
          const plaintext = await crypto.subtle.decrypt({ name: "AES-GCM", iv: fromBase64(payload.iv), tagLength: 128 }, key, fromBase64(payload.data));
          return decoder.decode(plaintext);
        };

        const render = (html) => {
          document.open();
          document.write(html);
          document.close();
        };

        const restore = async () => {
          try {
            const saved = sessionStorage.getItem(storageKey);
            if (!saved) return false;
            render(await decrypt(fromBase64(saved)));
            return true;
          } catch (_) {
            sessionStorage.removeItem(storageKey);
            return false;
          }
        };

        const unlockOrShowGate = async () => {
          if (await restore()) return;
          gate.hidden = false;
          input.focus({ preventScroll: true });
        };

        if (document.readyState === "loading") {
          document.addEventListener("DOMContentLoaded", unlockOrShowGate, { once: true });
        } else {
          unlockOrShowGate();
        }

        form.addEventListener("submit", async (event) => {
          event.preventDefault();
          error.textContent = "";
          if (!/^[a-z]{5}$/.test(input.value)) {
            error.textContent = "请输入 5 个小写英文字母。";
            input.focus();
            return;
          }
          try {
            const keyBytes = await deriveKey(input.value);
            const html = await decrypt(keyBytes);
            sessionStorage.setItem(storageKey, toBase64(keyBytes));
            render(html);
          } catch (_) {
            error.textContent = "密码不正确。";
            input.select();
          }
        });
      })();
    </script>
  </body>
</html>
`;
}

const args = readArguments(process.argv.slice(2));
const inputRoot = path.resolve(args.input ?? "");
const outputRoot = path.resolve(args.output ?? "");
const configPath = path.resolve(args.config ?? "");
const password = process.env.OLEANDER_PASSWORD;

if (!existsSync(inputRoot)) throw new Error(`Input directory does not exist: ${inputRoot}`);
if (!existsSync(configPath)) throw new Error(`Encryption config does not exist: ${configPath}`);
if (!password) throw new Error("OLEANDER_PASSWORD is not set");

const config = JSON.parse(await readFile(configPath, "utf8"));
const salt = Buffer.from(config.salt, "base64");
const key = pbkdf2Sync(password, salt, config.iterations, 32, "sha256");
const htmlFiles = await findHtmlFiles(inputRoot);
if (htmlFiles.length === 0) throw new Error(`No HTML files found under ${inputRoot}`);

await rm(outputRoot, { recursive: true, force: true });
for (const inputPath of htmlFiles) {
  const plaintext = await readFile(inputPath, "utf8");
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const sealed = Buffer.concat([encrypted, cipher.getAuthTag()]);
  const payload = {
    version: config.version,
    iterations: config.iterations,
    salt: config.salt,
    iv: Buffer.from(iv).toString("base64"),
    data: sealed.toString("base64"),
  };
  const relativePath = path.relative(inputRoot, inputPath);
  const outputPath = path.join(outputRoot, relativePath);
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, encryptedDocument(payload), "utf8");
}

console.log(`Encrypted ${htmlFiles.length} Oleander HTML file(s).`);
