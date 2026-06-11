#!/usr/bin/env node
import crypto from "node:crypto";

const apiBase = "https://api.appstoreconnect.apple.com/v1";
const bundleId = process.env.BUNDLE_ID || "com.colecantcode.ollamacloud";
const versionString = requireEnv("APP_VERSION");
const buildNumber = requireEnv("BUILD_NUMBER");
const submitForReview = parseBool(process.env.SUBMIT_FOR_REVIEW || "false");
const maxWaitMinutes = Number(process.env.MAX_WAIT_MINUTES || "30");

const token = makeToken();

function requireEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function parseBool(value) {
  return ["1", "true", "yes", "on"].includes(value.trim().toLowerCase());
}

function base64url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function makeToken() {
  const keyId = requireEnv("ASC_KEY_ID");
  const issuerId = requireEnv("ASC_ISSUER_ID");
  const privateKey = Buffer.from(requireEnv("ASC_KEY_P8_BASE64"), "base64").toString("utf8");
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const payload = {
    iss: issuerId,
    iat: now,
    exp: now + 20 * 60,
    aud: "appstoreconnect-v1"
  };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signature = crypto.sign("sha256", Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: "ieee-p1363"
  });
  return `${signingInput}.${base64url(signature)}`;
}

async function api(method, path, body) {
  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: body ? JSON.stringify(body) : undefined
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  if (!response.ok) {
    const error = new Error(`${method} ${path} failed with ${response.status}`);
    error.payload = payload;
    throw error;
  }
  return payload;
}

function query(params) {
  return new URLSearchParams(params).toString();
}

function summarizeError(error) {
  if (!error.payload?.errors) {
    return error.stack || String(error);
  }
  return error.payload.errors.map((item) => {
    const pieces = [
      item.status,
      item.code,
      item.title,
      item.detail
    ].filter(Boolean);
    const associated = item.meta?.associatedErrors
      ?.map((nested) => `  - ${nested.title || nested.code || "Associated error"}: ${nested.detail || ""}`)
      .join("\n");
    return associated ? `${pieces.join(" | ")}\n${associated}` : pieces.join(" | ");
  }).join("\n");
}

async function findApp() {
  const params = query({
    "filter[bundleId]": bundleId,
    limit: "1"
  });
  const response = await api("GET", `/apps?${params}`);
  const app = response.data?.[0];
  if (!app) {
    throw new Error(`No App Store Connect app found for bundle id ${bundleId}`);
  }
  console.log(`App: ${app.attributes?.name || app.id} (${app.id})`);
  return app;
}

async function findBuild(appId) {
  const deadline = Date.now() + maxWaitMinutes * 60_000;
  let lastSeen = "not found";

  while (Date.now() < deadline) {
    const params = query({
      "filter[app]": appId,
      "filter[version]": buildNumber,
      include: "preReleaseVersion",
      sort: "-uploadedDate",
      limit: "10"
    });
    const response = await api("GET", `/builds?${params}`);
    const included = new Map((response.included || []).map((item) => [item.id, item]));
    const build = (response.data || []).find((candidate) => {
      const preReleaseId = candidate.relationships?.preReleaseVersion?.data?.id;
      const preRelease = preReleaseId ? included.get(preReleaseId) : undefined;
      const preReleaseVersion = preRelease?.attributes?.version;
      return candidate.attributes?.version === buildNumber
        && (!preReleaseVersion || preReleaseVersion === versionString);
    });

    if (build) {
      const state = build.attributes?.processingState || "UNKNOWN";
      lastSeen = `${build.id} state=${state}`;
      if (state === "VALID") {
        console.log(`Build: ${versionString} (${buildNumber}) ${build.id}`);
        return build;
      }
      if (state === "FAILED" || state === "INVALID") {
        throw new Error(`Build ${versionString} (${buildNumber}) processing failed: ${state}`);
      }
    }

    console.log(`Waiting for build ${versionString} (${buildNumber}); last seen: ${lastSeen}`);
    await new Promise((resolve) => setTimeout(resolve, 60_000));
  }

  throw new Error(`Timed out waiting for build ${versionString} (${buildNumber}); last seen: ${lastSeen}`);
}

async function findOrCreateAppStoreVersion(appId) {
  const params = query({
    "filter[platform]": "IOS",
    "filter[versionString]": versionString,
    limit: "10"
  });
  const response = await api("GET", `/apps/${appId}/appStoreVersions?${params}`);
  const existing = response.data?.[0];
  if (existing) {
    console.log(`App Store version: ${versionString} ${existing.id} state=${existing.attributes?.appStoreState}`);
    return existing;
  }

  const created = await api("POST", "/appStoreVersions", {
    data: {
      type: "appStoreVersions",
      attributes: {
        platform: "IOS",
        versionString
      },
      relationships: {
        app: {
          data: { type: "apps", id: appId }
        }
      }
    }
  });
  console.log(`Created App Store version: ${versionString} ${created.data.id}`);
  return created.data;
}

async function attachBuild(appStoreVersionId, buildId) {
  await api("PATCH", `/appStoreVersions/${appStoreVersionId}/relationships/build`, {
    data: {
      type: "builds",
      id: buildId
    }
  });
  console.log(`Attached build ${buildId} to App Store version ${appStoreVersionId}`);
}

async function submit(appId, appStoreVersionId) {
  const reviewSubmission = await api("POST", "/reviewSubmissions", {
    data: {
      type: "reviewSubmissions",
      attributes: {
        platform: "IOS"
      },
      relationships: {
        app: {
          data: { type: "apps", id: appId }
        }
      }
    }
  });

  const reviewSubmissionId = reviewSubmission.data.id;
  console.log(`Review submission: ${reviewSubmissionId}`);

  await api("POST", "/reviewSubmissionItems", {
    data: {
      type: "reviewSubmissionItems",
      relationships: {
        reviewSubmission: {
          data: { type: "reviewSubmissions", id: reviewSubmissionId }
        },
        appStoreVersion: {
          data: { type: "appStoreVersions", id: appStoreVersionId }
        }
      }
    }
  });
  console.log(`Added App Store version ${appStoreVersionId} to review submission`);

  const submitted = await api("PATCH", `/reviewSubmissions/${reviewSubmissionId}`, {
    data: {
      type: "reviewSubmissions",
      id: reviewSubmissionId,
      attributes: {
        submitted: true
      }
    }
  });
  console.log(`Submitted for review: ${submitted.data.id} state=${submitted.data.attributes?.state}`);
}

try {
  const app = await findApp();
  const build = await findBuild(app.id);
  const appStoreVersion = await findOrCreateAppStoreVersion(app.id);
  await attachBuild(appStoreVersion.id, build.id);

  if (submitForReview) {
    await submit(app.id, appStoreVersion.id);
  } else {
    console.log("SUBMIT_FOR_REVIEW=false; stopping after attaching the build.");
  }
} catch (error) {
  console.error(summarizeError(error));
  process.exit(1);
}
