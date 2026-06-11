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
    const associatedErrors = normalizeAssociatedErrors(item.meta?.associatedErrors);
    const associated = associatedErrors
      .map((nested) => `  - ${nested.title || nested.code || "Associated error"}: ${nested.detail || JSON.stringify(nested)}`)
      .join("\n");
    return associated ? `${pieces.join(" | ")}\n${associated}` : pieces.join(" | ");
  }).join("\n");
}

function normalizeAssociatedErrors(value) {
  if (!value) {
    return [];
  }
  if (Array.isArray(value)) {
    return value;
  }
  if (typeof value === "object") {
    return Object.values(value).flatMap((item) => Array.isArray(item) ? item : [item]);
  }
  return [{ detail: String(value) }];
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

  const reusable = await findReusableAppStoreVersion(appId);
  if (reusable) {
    const currentVersion = reusable.attributes?.versionString;
    if (currentVersion !== versionString) {
      const updated = await api("PATCH", `/appStoreVersions/${reusable.id}`, {
        data: {
          type: "appStoreVersions",
          id: reusable.id,
          attributes: {
            versionString
          }
        }
      });
      console.log(`Updated App Store version ${reusable.id} from ${currentVersion} to ${versionString}`);
      return updated.data;
    }
    return reusable;
  }

  try {
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
  } catch (error) {
    await printKnownAppStoreVersions(appId);
    throw error;
  }
}

async function findReusableAppStoreVersion(appId) {
  const versions = await listAppStoreVersions(appId);
  const editableStates = new Set([
    "PREPARE_FOR_SUBMISSION",
    "READY_FOR_REVIEW",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED"
  ]);
  const reusable = versions.filter((version) => editableStates.has(version.attributes?.appStoreState));
  if (reusable.length === 1) {
    const version = reusable[0];
    console.log(
      `Reusing editable App Store version ${version.id} `
      + `version=${version.attributes?.versionString} state=${version.attributes?.appStoreState}`
    );
    return version;
  }
  if (reusable.length > 1) {
    console.log("Multiple editable App Store versions exist; not choosing one automatically.");
  }
  return undefined;
}

async function listAppStoreVersions(appId) {
  const params = query({
    "filter[platform]": "IOS",
    limit: "20"
  });
  const response = await api("GET", `/apps/${appId}/appStoreVersions?${params}`);
  return response.data || [];
}

async function printKnownAppStoreVersions(appId) {
  const versions = await listAppStoreVersions(appId);
  if (!versions.length) {
    console.log("No existing iOS App Store versions found.");
    return;
  }
  console.log("Existing iOS App Store versions:");
  for (const version of versions) {
    console.log(
      `- ${version.id} version=${version.attributes?.versionString} `
      + `state=${version.attributes?.appStoreState}`
    );
  }
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
  const { reviewSubmission, hasItem } = await findOrCreateReviewSubmission(appId, appStoreVersionId);
  const reviewSubmissionId = reviewSubmission.id;
  console.log(`Review submission: ${reviewSubmissionId} state=${reviewSubmission.attributes?.state}`);

  if (hasItem) {
    console.log(`App Store version ${appStoreVersionId} is already in review submission ${reviewSubmissionId}`);
  } else {
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
  }

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

async function findOrCreateReviewSubmission(appId, appStoreVersionId) {
  const existing = await listReviewSubmissions(appId);
  const reusableStates = new Set([
    "READY_FOR_REVIEW",
    "INCOMPLETE"
  ]);

  for (const submission of existing) {
    if (!reusableStates.has(submission.attributes?.state)) {
      continue;
    }
    if (await reviewSubmissionContainsAppStoreVersion(submission.id, appStoreVersionId)) {
      console.log(`Reusing review submission ${submission.id} because it already contains the app version`);
      return { reviewSubmission: submission, hasItem: true };
    }
  }

  const reusable = existing.find((submission) => reusableStates.has(submission.attributes?.state));
  if (reusable) {
    console.log(`Reusing review submission ${reusable.id} state=${reusable.attributes?.state}`);
    return { reviewSubmission: reusable, hasItem: false };
  }

  const created = await api("POST", "/reviewSubmissions", {
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
  return { reviewSubmission: created.data, hasItem: false };
}

async function listReviewSubmissions(appId) {
  const params = query({
    "filter[app]": appId,
    "filter[platform]": "IOS",
    limit: "10"
  });
  const response = await api("GET", `/reviewSubmissions?${params}`);
  return response.data || [];
}

async function reviewSubmissionContainsAppStoreVersion(reviewSubmissionId, appStoreVersionId) {
  const params = query({
    limit: "20"
  });
  const response = await api("GET", `/reviewSubmissions/${reviewSubmissionId}/items?${params}`);
  return (response.data || []).some((item) => {
    const related = item.relationships?.appStoreVersion?.data;
    return related?.type === "appStoreVersions" && related.id === appStoreVersionId;
  });
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
