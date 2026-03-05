function normalizeModelName(value) {
  return String(value || '').trim().toLowerCase();
}

function allowlistHasModel(allowedModels, modelName) {
  if (!(allowedModels instanceof Set) || allowedModels.size === 0) {
    return true;
  }
  const target = normalizeModelName(modelName);
  for (const item of allowedModels) {
    if (normalizeModelName(item) === target) {
      return true;
    }
  }
  return false;
}

function buildSeerSystemPrompt(config) {
  const alias = config.seerAliasName || 'SEER';
  const upstream = config.seerUpstreamModel || 'qwen3.5:397b-cloud';

  return [
    `You are ${alias}, the in-app product and codebase expert for the Ollama Cloud iOS app.`,
    'Primary goal: help users succeed quickly with accurate, actionable guidance for this app.',
    '',
    'Operating mode:',
    '- Provide direct answers first, then short numbered steps.',
    '- Use exact UI labels when possible (for example: Parameters, Reasoning Scaffold, Model Picker, Settings).',
    '- Keep answers concise by default, expand only when asked.',
    '- Reasoning scaffolds are guidance for thought process, not rigid output rules.',
    '',
    'Restraints:',
    '- Never claim to have performed actions in the app or backend unless explicitly provided in the conversation.',
    '- Never invent model availability, API behavior, file paths, or settings. If uncertain, say what is unknown.',
    '- Never provide or request secrets (API keys, tokens, credentials).',
    '- Prefer safe, reversible actions. Call out destructive actions before suggesting them.',
    '',
    `Model routing note: alias ${alias} is backed by ${upstream}.`,
    '',
    'Codebase knowledge snapshot (2026-03-05):',
    '- iOS app root: OllamaCloud/Sources/',
    '- App entry and SwiftData schema: App/OllamaCloudApp.swift',
    '- Conversation and message models: Models/Conversation.swift, Models/Message.swift',
    '- Chat runtime: Services/StreamingChatService.swift',
    '- API client and transport: Services/OllamaAPIClient.swift',
    '- Main chat UI: Views/ChatView.swift',
    '- Model selection UI: Views/ModelPickerView.swift',
    '- Parameters UI and system prompt/scaffold controls: Views/ParametersView.swift',
    '- Reasoning scaffold runtime/compiler: Services/ReasoningScaffoldCompiler.swift and Services/ReasoningScaffoldResolver.swift',
    '- Scaffold data model and account scoping: Models/ReasoningScaffold.swift and Utils/AccountScope.swift',
    '- Scaffold management UI: Views/ScaffoldLibraryView.swift and Views/ScaffoldBuilderView.swift',
    '- Backend relay root: backend/src/server.mjs',
    '- Backend config and env parsing: backend/src/config.mjs',
    '- Backend reliability primitives: backend/src/upstream.mjs, backend/src/rate-limit.mjs, backend/src/metrics.mjs',
    '',
    'Known product behavior:',
    '- Request assembly order is scaffold system block first, then user system prompt, then conversation history.',
    '- One active scaffold per conversation; missing/mismatched scaffold references auto-clear.',
    '- Chat supports streaming content and streaming thinking.',
    '- Model list is fetched from /api/tags; chat streams through /api/chat.',
    '',
    'When users ask for implementation help:',
    '- Reference concrete files and likely touch points.',
    '- Suggest minimal, testable patches.',
    '- If behavior depends on environment or rollout flags, say so explicitly.',
  ].join('\n');
}

export function isSeerAliasRequest(modelName, config) {
  if (!config.seerModelEnabled) return false;
  return normalizeModelName(modelName) === normalizeModelName(config.seerAliasName);
}

export function isModelAllowedForRequest({ requestedModel, isSeerRequest, config }) {
  if (!(config.allowedModels instanceof Set) || config.allowedModels.size === 0) {
    return true;
  }

  if (isSeerRequest) {
    return allowlistHasModel(config.allowedModels, config.seerAliasName)
      || allowlistHasModel(config.allowedModels, config.seerUpstreamModel);
  }

  return allowlistHasModel(config.allowedModels, requestedModel);
}

export function filterTagsByAllowlist(models, allowedModels) {
  if (!(allowedModels instanceof Set) || allowedModels.size === 0) {
    return Array.isArray(models) ? models : [];
  }
  return (Array.isArray(models) ? models : []).filter((model) => allowlistHasModel(allowedModels, model?.name));
}

export function maybeAppendSeerAliasModel({ payload, config, upstreamModels }) {
  if (!config.seerModelEnabled || !Array.isArray(payload.models)) {
    return;
  }

  const upstreamHasBacking = (Array.isArray(upstreamModels) ? upstreamModels : [])
    .some((model) => normalizeModelName(model?.name) === normalizeModelName(config.seerUpstreamModel));
  if (!upstreamHasBacking) {
    return;
  }

  if (!isModelAllowedForRequest({
    requestedModel: config.seerAliasName,
    isSeerRequest: true,
    config,
  })) {
    return;
  }

  const alreadyPresent = payload.models
    .some((model) => normalizeModelName(model?.name) === normalizeModelName(config.seerAliasName));
  if (alreadyPresent) {
    return;
  }

  payload.models.unshift({
    name: config.seerAliasName,
    model: config.seerAliasName,
    modified_at: null,
    size: null,
  });
}

export function transformChatBodyForSeer(body, config) {
  if (!isSeerAliasRequest(body?.model, config)) {
    return { body, isSeerRequest: false };
  }

  const messages = Array.isArray(body.messages) ? body.messages : [];
  const seerSystemMessage = {
    role: 'system',
    content: buildSeerSystemPrompt(config),
  };

  return {
    isSeerRequest: true,
    body: {
      ...body,
      model: config.seerUpstreamModel,
      messages: [seerSystemMessage, ...messages],
    },
  };
}
