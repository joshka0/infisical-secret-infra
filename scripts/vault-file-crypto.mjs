#!/usr/bin/env node
import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const KEY_ENV = "LOCAL_VAULT_FILE_ENCRYPTION_KEY";

function usage() {
  console.error(`Usage:
  vault-file-crypto.mjs encrypt <input> <output.enc>
  vault-file-crypto.mjs decrypt <input.enc> <output> [--force]

Requires ${KEY_ENV} in the environment.
`);
}

function fail(message, code = 2) {
  console.error(message);
  process.exit(code);
}

function getKey() {
  const raw = process.env[KEY_ENV];
  if (!raw) fail(`${KEY_ENV}=missing`, 2);

  const compact = raw.trim();
  const decoded = Buffer.from(compact, "base64");
  if (decoded.length >= 32) return decoded.subarray(0, 32);

  return createHash("sha256").update(compact, "utf8").digest();
}

function atomicWrite(path, data, mode = 0o600) {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const tmp = `${path}.tmp-${process.pid}-${Date.now()}`;
  writeFileSync(tmp, data, { mode });
  renameSync(tmp, path);
}

function encrypt(input, output) {
  const key = getKey();
  const plaintext = readFileSync(input);
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = cipher.getAuthTag();
  const sourceStat = statSync(input);

  const payload = {
    version: 1,
    alg: "aes-256-gcm",
    iv: iv.toString("base64"),
    tag: tag.toString("base64"),
    ciphertext: ciphertext.toString("base64"),
    plaintext_sha256: createHash("sha256").update(plaintext).digest("hex"),
    plaintext_bytes: plaintext.length,
    source_mode: (sourceStat.mode & 0o777).toString(8),
    created_at: new Date().toISOString(),
  };

  atomicWrite(output, `${JSON.stringify(payload, null, 2)}\n`);
  console.log(`encrypted=true`);
  console.log(`output=${output}`);
  console.log(`plaintext_bytes=${plaintext.length}`);
  console.log(`plaintext_sha256=${payload.plaintext_sha256}`);
}

function decrypt(input, output, force) {
  const key = getKey();
  if (!force) {
    try {
      statSync(output);
      fail(`Refusing to overwrite existing output: ${output}`, 2);
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
  }

  const payload = JSON.parse(readFileSync(input, "utf8"));
  if (payload.version !== 1 || payload.alg !== "aes-256-gcm") {
    fail(`Unsupported encrypted payload: ${input}`, 2);
  }

  const decipher = createDecipheriv(
    "aes-256-gcm",
    key,
    Buffer.from(payload.iv, "base64"),
  );
  decipher.setAuthTag(Buffer.from(payload.tag, "base64"));
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(payload.ciphertext, "base64")),
    decipher.final(),
  ]);
  const sha256 = createHash("sha256").update(plaintext).digest("hex");
  if (sha256 !== payload.plaintext_sha256) {
    fail(`Plaintext hash verification failed: ${input}`, 1);
  }

  atomicWrite(output, plaintext);
  console.log(`decrypted=true`);
  console.log(`output=${output}`);
  console.log(`plaintext_bytes=${plaintext.length}`);
  console.log(`plaintext_sha256=${sha256}`);
}

const [command, input, output, ...rest] = process.argv.slice(2);
if (!command || !input || !output) {
  usage();
  process.exit(2);
}

if (command === "encrypt") {
  encrypt(input, output);
} else if (command === "decrypt") {
  decrypt(input, output, rest.includes("--force"));
} else {
  usage();
  process.exit(2);
}
