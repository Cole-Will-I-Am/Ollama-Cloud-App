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
    if (a.state !== "COMPLETE") {
      try {
        const items = await api("GET", `/reviewSubmissions/${s.id}/items?${q({ limit: "20" })}`);
        for (const it of items.data || []) {
          const ia = it.attributes || {};
          console.log(`      item ${it.id} state=${ia.state} removed=${ia.removed}`);
        }
      } catch (e) { console.log(`      (items: ${e.message})`); }
    }
  }

  console.log("\n=== Version build + export compliance ===");
  const verId = versions.data?.[0]?.id;
  if (verId) {
    const ver = await api("GET", `/appStoreVersions/${verId}?${q({ "include": "build", "fields[builds]": "version,processingState,usesNonExemptEncryption,uploadedDate" })}`);
    const b = ver.included?.find((x) => x.type === "builds");
    if (b) {
      const a = b.attributes || {};
      console.log(`  attached build ${a.version}  usesNonExemptEncryption=${a.usesNonExemptEncryption}  processing=${a.processingState}`);
    } else {
      console.log("  (no build attached to version)");
    }
    // appStoreVersionSubmission tells us if a submission object exists/was created
    try {
      const avs = await api("GET", `/appStoreVersions/${verId}/appStoreVersionSubmission`);
      console.log(`  appStoreVersionSubmission: ${avs.data?.id || "none"}`);
    } catch (e) { console.log(`  appStoreVersionSubmission: ${e.message}`); }
  }

  console.log("\n=== Submission readiness (editable version) ===");
  if (verId) {
    try {
      const locs = await api("GET", `/appStoreVersions/${verId}/appStoreVersionLocalizations?${q({ limit: "10" })}`);
      for (const loc of locs.data || []) {
        const a = loc.attributes || {};
        let shots = 0;
        try {
          const sets = await api("GET", `/appStoreVersionLocalizations/${loc.id}/appScreenshotSets?${q({ include: "appScreenshots", limit: "50" })}`);
          shots = (sets.included || []).filter((x) => x.type === "appScreenshots").length;
        } catch (e) {}
        console.log(`  [${a.locale}] description=${a.description ? "yes" : "MISSING"} supportUrl=${a.supportUrl ? "yes" : "MISSING"} promotionalText=${a.promotionalText ? "yes" : "-"} screenshots=${shots}`);
        console.log(`      keywords: ${JSON.stringify(a.keywords || "")}`);
      }
    } catch (e) { console.log(`  (localizations: ${e.message})`); }
    try {
      const ar = await api("GET", `/appStoreVersions/${verId}/ageRatingDeclaration`);
      console.log(`  ageRatingDeclaration: ${ar.data ? "set" : "MISSING"}`);
    } catch (e) { console.log(`  ageRatingDeclaration: ${e.message.includes("404") ? "MISSING" : e.message}`); }
  }
  try {
    const infos = await api("GET", `/apps/${appId}/appInfos?${q({ include: "primaryCategory", limit: "5" })}`);
    for (const info of infos.data || []) {
      const a = info.attributes || {};
      let ageRating = "MISSING";
      try {
        const ar = await api("GET", `/appInfos/${info.id}/ageRatingDeclaration`);
        ageRating = ar.data ? "set" : "MISSING";
      } catch (e) { ageRating = e.message.includes("404") ? "MISSING" : e.message; }
      console.log(`  appInfo ${info.id} state=${a.appStoreState || a.state || "?"} ageRatingDeclaration=${ageRating}`);
      try {
        const ilocs = await api("GET", `/appInfos/${info.id}/appInfoLocalizations?${q({ limit: "10" })}`);
        for (const il of ilocs.data || []) {
          const ia = il.attributes || {};
          console.log(`      [${ia.locale}] name=${JSON.stringify(ia.name || "")} subtitle=${JSON.stringify(ia.subtitle || "")}`);
        }
      } catch (e) { console.log(`      (appInfoLocalizations: ${e.message})`); }
    }
  } catch (e) { console.log(`  (appInfos: ${e.message})`); }

  console.log("\n=== Recent Builds (TestFlight) ===");
  const builds = await api("GET", `/builds?${q({ "filter[app]": appId, limit: "8", sort: "-uploadedDate" })}`);
  for (const b of builds.data || []) {
    const a = b.attributes || {};
    console.log(`  build ${a.version}  processing=${a.processingState}  encryption=${a.usesNonExemptEncryption}  expired=${a.expired}`);
  }
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
