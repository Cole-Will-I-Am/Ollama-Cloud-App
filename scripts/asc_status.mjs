#!/usr/bin/env node
// Read-only App Store Connect status check. No writes, no submissions.
import crypto from "node:crypto";

const apiBase = "https://api.appstoreconnect.apple.com/v1";
const bundleId = process.env.BUNDLE_ID || "com.colecantcode.ollamacloud";
const token = makeToken();

function requireEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function base64url(input) {
  return Buffer.from(input).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function makeToken() {
  const keyId = requireEnv("ASC_KEY_ID");
  const issuerId = requireEnv("ASC_ISSUER_ID");
  const privateKey = Buffer.from(requireEnv("ASC_KEY_P8_BASE64"), "base64").toString("utf8");
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const payload = { iss: issuerId, iat: now, exp: now + 20 * 60, aud: "appstoreconnect-v1" };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signature = crypto.sign("sha256", Buffer.from(signingInput), { key: privateKey, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${base64url(signature)}`;
}

async function api(method, path) {
  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  if (!response.ok) {
    throw new Error(`${method} ${path} failed with ${response.status}: ${JSON.stringify(payload.errors || payload)}`);
  }
  return payload;
}

function q(params) {
  return new URLSearchParams(params).toString();
}

async function main() {
  const apps = await api("GET", `/apps?${q({ "filter[bundleId]": bundleId })}`);
  const app = apps.data?.[0];
  if (!app) throw new Error(`No app found for bundleId ${bundleId}`);
  const appId = app.id;
  console.log(`App: ${app.attributes?.name} (${bundleId}) id=${appId}\n`);

  const versions = await api("GET", `/apps/${appId}/appStoreVersions?${q({ limit: "10" })}`);
  console.log("=== App Store Versions ===");
  for (const v of versions.data || []) {
    const a = v.attributes || {};
    console.log(`  ${a.versionString}  state=${a.appStoreState}  platform=${a.platform}  created=${a.createdDate}`);
  }

  console.log("\n=== Review Submissions ===");
  const subs = await api("GET", `/apps/${appId}/reviewSubmissions?${q({ limit: "10" })}`);
  for (const s of subs.data || []) {
    const a = s.attributes || {};
    console.log(`  ${s.id}  state=${a.state}  platform=${a.platform}  submitted=${a.submittedDate || "-"}`);
  }

  console.log("\n=== Recent Builds (TestFlight) ===");
  const builds = await api("GET", `/builds?${q({ "filter[app]": appId, limit: "8", sort: "-uploadedDate" })}`);
  for (const b of builds.data || []) {
    const a = b.attributes || {};
    console.log(`  build ${a.version}  processing=${a.processingState}  expired=${a.expired}  uploaded=${a.uploadedDate}`);
  }
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
