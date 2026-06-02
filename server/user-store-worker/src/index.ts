interface Env {
  GITHUB_TOKEN: string;
  GITHUB_OWNER: string;
  GITHUB_REPO: string;
  SESSION_SECRET: string;
  CATALOG_GITHUB_TOKEN?: string;
  CATALOG_GITHUB_OWNER?: string;
  CATALOG_GITHUB_REPO?: string;
  CATALOG_GITHUB_REF?: string;
  CATALOG_GITHUB_PATH?: string;
  CATALOG_CACHE_TTL_SECONDS?: string;
  CATALOG_EDGE_BASE_URL?: string;
  CATALOG_EDGE_PATH?: string;
  CATALOG_BUCKET?: R2Bucket;
  GOOGLE_CLIENT_ID?: string;
  APPLE_BUNDLE_ID?: string;
  CORS_ORIGIN?: string;
}

type JsonMap = Record<string, unknown>;

type VerifiedIdentity = {
  provider: 'google' | 'apple';
  providerUserId: string;
  email: string;
  displayName: string;
  photoUrl: string;
};

type GitHubFile = {
  data: JsonMap;
  sha: string;
};

const defaultProfilePhotoUrl = 'https://raw.githubusercontent.com/Hash-Studios/Prism/master/assets/icon/ios.png';
const allowedMediaImageHosts = new Set(['media.wallpics.app', 'backend.wallpics.app']);
const allowedMediaImageExtensions = new Set(['.jpg', '.jpeg', '.png', '.webp']);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(env) });
    }

    try {

      if (request.method === 'GET' && url.pathname === '/v1/catalog') {
        return catalogResponse('prism_index.json', request, env);
      }

      const catalogMatch = url.pathname.match(/^\/v1\/catalog\/([A-Za-z0-9_.-]+\.json)$/);
      if (catalogMatch && request.method === 'GET') {
        return catalogResponse(catalogMatch[1], request, env);
      }

      if (request.method === 'GET' && url.pathname === '/v1/media/image') {
        return mediaImageResponse(request, env);
      }

      if (request.method === 'POST' && url.pathname === '/v1/users/sign-in') {
        return jsonResponse(await handleSignIn(request, env), env);
      }

      const userMatch = url.pathname.match(/^\/v1\/users\/([^/]+)$/);
      if (userMatch && request.method === 'GET') {
        return jsonResponse(await handleGetUser(userMatch[1], request, env), env);
      }
      if (userMatch && request.method === 'PATCH') {
        return jsonResponse(await handlePatchUser(userMatch[1], request, env), env);
      }

      const logoutMatch = url.pathname.match(/^\/v1\/users\/([^/]+)\/logout$/);
      if (logoutMatch && request.method === 'POST') {
        return jsonResponse(await handleLogout(logoutMatch[1], request, env), env);
      }

      return jsonResponse({ error: 'Not found' }, env, 404);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unexpected error';
      return jsonResponse({ error: message }, env, statusForError(message));
    }
  },
};


async function catalogResponse(fileName: string, request: Request, env: Env): Promise<Response> {
  const safeFileName = safeCatalogFileName(fileName);
  const cacheKey = new Request(request.url, request);
  const cached = await caches.default.match(cacheKey);
  if (cached) {
    return withCors(cached, env);
  }

  const response = await catalogStorageResponse(safeFileName, env);
  if (!response) {
    return jsonResponse({ error: 'Catalog file not found' }, env, 404);
  }
  if (!response.ok) {
    throw new Error(`Catalog read failed: ${response.status}`);
  }

  const ttl = Math.max(60, numberValue(env.CATALOG_CACHE_TTL_SECONDS || 900));
  const catalog = new Response(response.body, {
    status: 200,
    headers: {
      ...corsHeaders(env),
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': `public, max-age=${ttl}, stale-while-revalidate=${ttl * 4}`,
    },
  });
  await caches.default.put(cacheKey, catalog.clone());
  return catalog;
}


async function mediaImageResponse(request: Request, env: Env): Promise<Response> {
  const requestUrl = new URL(request.url);
  const source = mediaImageSource(requestUrl.searchParams.get('src'));
  const width = clampNumber(numberValue(requestUrl.searchParams.get('w') || 540), 120, 1400);
  const quality = clampNumber(numberValue(requestUrl.searchParams.get('q') || 72), 45, 92);
  const ttl = Math.max(3600, numberValue(env.CATALOG_CACHE_TTL_SECONDS || 86400));
  const cacheKey = new Request(mediaImageCacheUrl(requestUrl, source, width, quality), { method: 'GET' });
  const cached = await caches.default.match(cacheKey);
  if (cached) {
    return withCors(cached, env);
  }

  const upstream = await fetch(source.toString(), {
    cf: {
      cacheEverything: true,
      cacheTtl: ttl,
      image: {
        width,
        fit: 'scale-down',
        format: 'webp',
        quality,
        metadata: 'none',
        sharpen: 1,
      },
    },
  });
  if (!upstream.ok) {
    return jsonResponse({ error: 'Media image not found' }, env, upstream.status === 404 ? 404 : 502);
  }

  const headers = new Headers(upstream.headers);
  for (const [key, value] of Object.entries(corsHeaders(env))) {
    headers.set(key, value);
  }
  headers.set('Cache-Control', `public, max-age=${ttl}, stale-while-revalidate=${ttl * 7}`);
  headers.set('Content-Type', headers.get('Content-Type') || 'image/webp');
  const response = new Response(upstream.body, { status: 200, headers });
  await caches.default.put(cacheKey, response.clone());
  return response;
}

function mediaImageSource(value: unknown): URL {
  const raw = stringValue(value);
  const source = new URL(raw);
  if (source.protocol !== 'https:' || !allowedMediaImageHosts.has(source.hostname)) {
    throw new Error('Invalid media image source');
  }
  const path = source.pathname.toLowerCase();
  if (![...allowedMediaImageExtensions].some((extension) => path.endsWith(extension))) {
    throw new Error('Invalid media image source');
  }
  return source;
}

function mediaImageCacheUrl(requestUrl: URL, source: URL, width: number, quality: number): string {
  const cacheUrl = new URL(requestUrl.origin);
  cacheUrl.pathname = '/v1/media/image';
  cacheUrl.searchParams.set('src', source.toString());
  cacheUrl.searchParams.set('w', String(width));
  cacheUrl.searchParams.set('q', String(quality));
  return cacheUrl.toString();
}

async function catalogStorageResponse(fileName: string, env: Env): Promise<Response | null> {
  const bucket = env.CATALOG_BUCKET;
  if (bucket) {
    const object = await bucket.get(catalogObjectKey(fileName, env));
    if (object) {
      return new Response(object.body, {
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
      });
    }
  }

  const edgeBaseUrl = stringValue(env.CATALOG_EDGE_BASE_URL);
  if (edgeBaseUrl) {
    const edgeResponse = await fetch(catalogEdgeUrl(fileName, env));
    if (edgeResponse.status === 404) {
      return null;
    }
    if (edgeResponse.ok) {
      return edgeResponse;
    }
  }

  const githubResponse = await fetch(catalogRawUrl(fileName, env), { headers: catalogGithubHeaders(env) });
  if (githubResponse.status === 404) {
    return null;
  }
  return githubResponse;
}

function withCors(response: Response, env: Env): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(corsHeaders(env))) {
    headers.set(key, value);
  }
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

function catalogRawUrl(fileName: string, env: Env): string {
  const owner = stringValue(env.CATALOG_GITHUB_OWNER) || env.GITHUB_OWNER;
  const repo = stringValue(env.CATALOG_GITHUB_REPO) || env.GITHUB_REPO;
  const ref = stringValue(env.CATALOG_GITHUB_REF) || 'main';
  const prefix = normalizePathPrefix(stringValue(env.CATALOG_GITHUB_PATH) || 'public/catalog');
  const path = `${prefix}/${fileName}`;
  return `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/contents/${path.split('/').map(encodeURIComponent).join('/')}?ref=${encodeURIComponent(ref)}`;
}

function catalogObjectKey(fileName: string, env: Env): string {
  const prefix = normalizePathPrefix(
    stringValue(env.CATALOG_EDGE_PATH) || stringValue(env.CATALOG_GITHUB_PATH) || 'public/catalog',
  );
  return prefix ? `${prefix}/${fileName}` : fileName;
}

function catalogEdgeUrl(fileName: string, env: Env): string {
  const base = stringValue(env.CATALOG_EDGE_BASE_URL).replace(/\/+$/, '');
  const prefix = normalizePathPrefix(stringValue(env.CATALOG_EDGE_PATH));
  const path = prefix ? `${prefix}/${fileName}` : fileName;
  return `${base}/${path.split('/').map(encodeURIComponent).join('/')}`;
}

function catalogGithubHeaders(env: Env): HeadersInit {
  return {
    Accept: 'application/vnd.github.raw',
    Authorization: `Bearer ${stringValue(env.CATALOG_GITHUB_TOKEN) || env.GITHUB_TOKEN}`,
    'User-Agent': 'PrismCatalogWorker',
    'X-GitHub-Api-Version': '2022-11-28',
  };
}

function safeCatalogFileName(value: string): string {
  const fileName = value.trim();
  if (!/^prism_[A-Za-z0-9_]+\.json$/.test(fileName)) {
    throw new Error('Invalid catalog file');
  }
  return fileName;
}

function normalizePathPrefix(value: string): string {
  return value.split('/').map((part) => part.trim()).filter(Boolean).join('/');
}

async function handleSignIn(request: Request, env: Env): Promise<JsonMap> {
  requireEnv(env);
  const body = await readJson(request);
  const provider = stringValue(body.provider).toLowerCase();
  const identityToken = stringValue(body.identityToken);
  if (identityToken.length === 0) {
    throw new Error('Missing identity token');
  }

  const identity = provider === 'google'
    ? await verifyGoogleIdentity(identityToken, body, env)
    : provider === 'apple'
      ? await verifyAppleIdentity(identityToken, body, env)
      : undefined;

  if (!identity) {
    throw new Error('Unsupported auth provider');
  }

  const userId = appUserId(identity.provider, identity.providerUserId);
  const path = userPath(userId);
  const now = new Date().toISOString();
  const existing = await readGithubJson(path, env);
  const user = normalizeUser({
    ...defaultUserData(userId, identity, now),
    ...(existing?.data ?? {}),
    id: userId,
    email: chooseEmail(existing?.data.email, identity.email),
    name: chooseString(identity.displayName, existing?.data.name, 'Prism User'),
    profilePhoto: chooseString(identity.photoUrl, existing?.data.profilePhoto, defaultProfilePhotoUrl),
    username: chooseString(existing?.data.username, usernameFrom(identity.displayName, identity.email, userId)),
    lastLoginAt: now,
    loggedIn: true,
    authProvider: identity.provider,
    providerUserIdHash: sha1Hex(identity.providerUserId),
    githubUserDocPath: path,
    updatedAt: now,
  });

  await writeGithubJson(path, user, existing?.sha, `Sync Prism user ${userId}`, env);
  return { user, sessionToken: await signSession({ sub: userId, provider: identity.provider }, env) };
}

async function handleGetUser(encodedUserId: string, request: Request, env: Env): Promise<JsonMap> {
  const userId = decodeURIComponent(encodedUserId);
  await requireSession(request, env, userId);
  const file = await readGithubJson(userPath(userId), env);
  if (!file) {
    throw new Error('User not found');
  }
  return { user: normalizeUser(file.data) };
}

async function handlePatchUser(encodedUserId: string, request: Request, env: Env): Promise<JsonMap> {
  const userId = decodeURIComponent(encodedUserId);
  await requireSession(request, env, userId);
  const body = await readJson(request);
  const updates = allowedUserUpdates(asMap(body.data));
  const path = userPath(userId);
  const existing = await readGithubJson(path, env);
  if (!existing) {
    throw new Error('User not found');
  }
  const user = normalizeUser({ ...existing.data, ...updates, id: userId, updatedAt: new Date().toISOString() });
  await writeGithubJson(path, user, existing.sha, `Update Prism user ${userId}`, env);
  return { user };
}

async function handleLogout(encodedUserId: string, request: Request, env: Env): Promise<JsonMap> {
  const userId = decodeURIComponent(encodedUserId);
  await requireSession(request, env, userId);
  const path = userPath(userId);
  const existing = await readGithubJson(path, env);
  if (!existing) {
    return { ok: true };
  }
  await writeGithubJson(
    path,
    normalizeUser({ ...existing.data, loggedIn: false, lastLogoutAt: new Date().toISOString(), updatedAt: new Date().toISOString() }),
    existing.sha,
    `Mark Prism user logged out ${userId}`,
    env,
  );
  return { ok: true };
}

async function verifyGoogleIdentity(token: string, body: JsonMap, env: Env): Promise<VerifiedIdentity> {
  const url = new URL('https://oauth2.googleapis.com/tokeninfo');
  url.searchParams.set('id_token', token);
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error('Google identity token rejected');
  }
  const claims = asMap(await response.json());
  if (env.GOOGLE_CLIENT_ID && stringValue(claims.aud) !== env.GOOGLE_CLIENT_ID) {
    throw new Error('Google identity token audience mismatch');
  }
  const providerUserId = stringValue(claims.sub);
  if (providerUserId.length === 0) {
    throw new Error('Google identity token missing subject');
  }
  return {
    provider: 'google',
    providerUserId,
    email: stringValue(claims.email),
    displayName: chooseString(claims.name, body.displayNameHint, stringValue(claims.email).split('@')[0], 'Prism User'),
    photoUrl: chooseString(claims.picture, body.photoUrlHint, defaultProfilePhotoUrl),
  };
}

async function verifyAppleIdentity(token: string, body: JsonMap, env: Env): Promise<VerifiedIdentity> {
  const jwt = decodeJwt(token);
  const response = await fetch('https://appleid.apple.com/auth/keys');
  if (!response.ok) {
    throw new Error('Apple JWK fetch failed');
  }
  const jwks = asMap(await response.json());
  const keys = Array.isArray(jwks.keys) ? jwks.keys.map(asMap) : [];
  const key = keys.find((candidate) => stringValue(candidate.kid) === stringValue(jwt.header.kid));
  if (!key) {
    throw new Error('Apple identity token key not found');
  }
  const cryptoKey = await crypto.subtle.importKey(
    'jwk',
    key as unknown as JsonWebKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', cryptoKey, jwt.signature, jwt.signedData);
  if (!valid) {
    throw new Error('Apple identity token signature invalid');
  }
  if (stringValue(jwt.payload.iss) !== 'https://appleid.apple.com') {
    throw new Error('Apple identity token issuer invalid');
  }
  if (env.APPLE_BUNDLE_ID && !audienceContains(jwt.payload.aud, env.APPLE_BUNDLE_ID)) {
    throw new Error('Apple identity token audience mismatch');
  }
  const exp = Number(jwt.payload.exp ?? 0);
  if (!Number.isFinite(exp) || exp * 1000 < Date.now()) {
    throw new Error('Apple identity token expired');
  }
  const providerUserId = stringValue(jwt.payload.sub);
  if (providerUserId.length === 0) {
    throw new Error('Apple identity token missing subject');
  }
  const email = chooseString(jwt.payload.email, body.emailHint, fallbackEmail('apple', providerUserId));
  return {
    provider: 'apple',
    providerUserId,
    email,
    displayName: chooseString(body.displayNameHint, email.split('@')[0], 'Prism User'),
    photoUrl: defaultProfilePhotoUrl,
  };
}

async function readGithubJson(path: string, env: Env): Promise<GitHubFile | null> {
  const response = await fetch(githubContentsUrl(path, env), { headers: githubHeaders(env) });
  if (response.status === 404) {
    return null;
  }
  if (!response.ok) {
    throw new Error(`GitHub read failed: ${response.status}`);
  }
  const envelope = asMap(await response.json());
  const encoded = stringValue(envelope.content).replace(/\n/g, '');
  const sha = stringValue(envelope.sha);
  return { data: asMap(JSON.parse(new TextDecoder().decode(base64Decode(encoded)))), sha };
}

async function writeGithubJson(path: string, data: JsonMap, sha: string | undefined, message: string, env: Env): Promise<void> {
  const body: JsonMap = {
    message,
    content: base64Encode(new TextEncoder().encode(JSON.stringify(data, null, 2))),
  };
  if (sha) {
    body.sha = sha;
  }
  const response = await fetch(githubContentsUrl(path, env), {
    method: 'PUT',
    headers: { ...githubHeaders(env), 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    throw new Error(`GitHub write failed: ${response.status}`);
  }
}

function defaultUserData(userId: string, identity: VerifiedIdentity, now: string): JsonMap {
  return {
    name: identity.displayName,
    bio: '',
    createdAt: now,
    email: identity.email,
    username: usernameFrom(identity.displayName, identity.email, userId),
    followers: [],
    following: [],
    id: userId,
    lastLoginAt: now,
    links: {},
    premium: false,
    loggedIn: true,
    profilePhoto: identity.photoUrl || defaultProfilePhotoUrl,
    badges: [],
    coins: 0,
    subPrisms: [],
    transactions: [],
    coverPhoto: '',
    subscriptionTier: 'free',
    uploadsWeekStart: '',
    uploadsThisWeek: 0,
    authProvider: identity.provider,
    providerUserIdHash: sha1Hex(identity.providerUserId),
    githubUserDocPath: userPath(userId),
  };
}

function normalizeUser(data: JsonMap): JsonMap {
  return {
    username: stringValue(data.username),
    email: stringValue(data.email),
    id: stringValue(data.id),
    createdAt: stringValue(data.createdAt) || new Date().toISOString(),
    premium: data.premium === true,
    lastLoginAt: stringValue(data.lastLoginAt) || new Date().toISOString(),
    links: asStringMap(data.links),
    followers: asStringArray(data.followers),
    following: asStringArray(data.following),
    profilePhoto: stringValue(data.profilePhoto) || defaultProfilePhotoUrl,
    bio: stringValue(data.bio),
    loggedIn: data.loggedIn !== false,
    badges: Array.isArray(data.badges) ? data.badges : [],
    subPrisms: asStringArray(data.subPrisms),
    coins: numberValue(data.coins),
    transactions: Array.isArray(data.transactions) ? data.transactions : [],
    name: stringValue(data.name),
    coverPhoto: stringValue(data.coverPhoto),
    subscriptionTier: stringValue(data.subscriptionTier) || 'free',
    uploadsWeekStart: stringValue(data.uploadsWeekStart),
    uploadsThisWeek: numberValue(data.uploadsThisWeek),
    authProvider: stringValue(data.authProvider),
    providerUserIdHash: stringValue(data.providerUserIdHash),
    githubUserDocPath: stringValue(data.githubUserDocPath),
    updatedAt: stringValue(data.updatedAt),
    lastLogoutAt: stringValue(data.lastLogoutAt),
  };
}

function allowedUserUpdates(data: JsonMap): JsonMap {
  const updates: JsonMap = {};
  for (const key of ['username', 'name', 'bio', 'profilePhoto', 'coverPhoto']) {
    if (key in data) {
      updates[key] = stringValue(data[key]);
    }
  }
  if ('links' in data) {
    updates.links = asStringMap(data.links);
  }
  return updates;
}

async function signSession(payload: JsonMap, env: Env): Promise<string> {
  const sessionPayload = { ...payload, exp: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 30 };
  const encoded = base64UrlEncode(new TextEncoder().encode(JSON.stringify(sessionPayload)));
  const signature = await hmac(encoded, env.SESSION_SECRET);
  return `${encoded}.${base64UrlEncode(signature)}`;
}

async function requireSession(request: Request, env: Env, userId: string): Promise<JsonMap> {
  const header = request.headers.get('Authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length) : '';
  const [encodedPayload, encodedSignature] = token.split('.');
  if (!encodedPayload || !encodedSignature) {
    throw new Error('Missing session token');
  }
  const expected = await hmac(encodedPayload, env.SESSION_SECRET);
  if (!timingSafeEqual(base64UrlDecode(encodedSignature), expected)) {
    throw new Error('Invalid session token');
  }
  const payload = asMap(JSON.parse(new TextDecoder().decode(base64UrlDecode(encodedPayload))));
  if (stringValue(payload.sub) !== userId) {
    throw new Error('Session user mismatch');
  }
  const exp = Number(payload.exp ?? 0);
  if (!Number.isFinite(exp) || exp * 1000 < Date.now()) {
    throw new Error('Session expired');
  }
  return payload;
}

async function hmac(value: string, secret: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value)));
}

function decodeJwt(token: string): { header: JsonMap; payload: JsonMap; signedData: Uint8Array; signature: Uint8Array } {
  const parts = token.split('.');
  if (parts.length !== 3) {
    throw new Error('Invalid JWT format');
  }
  const signedText = `${parts[0]}.${parts[1]}`;
  return {
    header: asMap(JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[0])))),
    payload: asMap(JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1])))),
    signedData: new TextEncoder().encode(signedText),
    signature: base64UrlDecode(parts[2]),
  };
}

async function readJson(request: Request): Promise<JsonMap> {
  return asMap(await request.json());
}

function requireEnv(env: Env): void {
  for (const key of ['GITHUB_TOKEN', 'GITHUB_OWNER', 'GITHUB_REPO', 'SESSION_SECRET']) {
    if (stringValue(env[key as keyof Env]).length === 0) {
      throw new Error(`Missing Worker secret: ${key}`);
    }
  }
}

function githubContentsUrl(path: string, env: Env): string {
  return `https://api.github.com/repos/${encodeURIComponent(env.GITHUB_OWNER)}/${encodeURIComponent(env.GITHUB_REPO)}/contents/${path.split('/').map(encodeURIComponent).join('/')}`;
}

function githubHeaders(env: Env): HeadersInit {
  return {
    Accept: 'application/vnd.github+json',
    Authorization: `Bearer ${env.GITHUB_TOKEN}`,
    'User-Agent': 'PrismUserStoreWorker',
    'X-GitHub-Api-Version': '2022-11-28',
  };
}

function jsonResponse(body: JsonMap, env: Env, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(env), 'Content-Type': 'application/json; charset=utf-8' },
  });
}

function corsHeaders(env: Env): HeadersInit {
  return {
    'Access-Control-Allow-Origin': env.CORS_ORIGIN || '*',
    'Access-Control-Allow-Methods': 'GET,POST,PATCH,OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization,Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

function statusForError(message: string): number {
  if (message.includes('not found')) {
    return 404;
  }
  if (message.includes('Missing') || message.includes('Invalid') || message.includes('mismatch') || message.includes('expired') || message.includes('rejected')) {
    return 401;
  }
  return 500;
}

function appUserId(provider: string, providerUserId: string): string {
  return `${safeSegment(provider)}_${sha1Hex(providerUserId || provider).slice(0, 20)}`;
}

function userPath(userId: string): string {
  return `users/${safeSegment(userId)}.json`;
}

function usernameFrom(displayName: string, email: string, userId: string): string {
  const source = displayName || (email.includes('@') ? email.split('@')[0] : '') || userId;
  const sanitized = source.replace(/[^A-Za-z0-9_]/g, '');
  return sanitized.length >= 3 ? sanitized : `user_${userId.slice(-8)}`;
}

function fallbackEmail(provider: string, providerUserId: string): string {
  return `${safeSegment(provider)}-${sha1Hex(providerUserId).slice(0, 12)}@users.prism.local`;
}

function chooseEmail(existing: unknown, incoming: unknown): string {
  const existingEmail = stringValue(existing);
  const incomingEmail = stringValue(incoming);
  if (incomingEmail.length > 0 && (existingEmail.length === 0 || existingEmail.endsWith('@users.prism.local'))) {
    return incomingEmail;
  }
  return existingEmail || incomingEmail;
}

function chooseString(...values: unknown[]): string {
  for (const value of values) {
    const candidate = stringValue(value);
    if (candidate.length > 0 && candidate !== 'null') {
      return candidate;
    }
  }
  return '';
}

function asMap(value: unknown): JsonMap {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as JsonMap;
  }
  return {};
}

function asStringMap(value: unknown): Record<string, string> {
  const map = asMap(value);
  return Object.fromEntries(Object.entries(map).map(([key, entry]) => [key, stringValue(entry)]).filter(([, entry]) => entry.length > 0));
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.map(stringValue).filter((entry) => entry.length > 0) : [];
}

function stringValue(value: unknown): string {
  return value == null ? '' : String(value).trim();
}

function numberValue(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function clampNumber(value: number, min: number, max: number): number {
  return Math.min(Math.max(Math.round(value), min), max);
}

function audienceContains(aud: unknown, expected: string): boolean {
  return Array.isArray(aud) ? aud.includes(expected) : stringValue(aud) === expected;
}

function safeSegment(value: string): string {
  return value.trim().toLowerCase().replace(/[^a-z0-9_-]+/g, '_') || 'user';
}

function timingSafeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) {
    return false;
  }
  let diff = 0;
  for (let index = 0; index < left.length; index += 1) {
    diff |= left[index] ^ right[index];
  }
  return diff === 0;
}

function base64Decode(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function base64Encode(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function base64UrlDecode(value: string): Uint8Array {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=');
  return base64Decode(normalized);
}

function base64UrlEncode(bytes: Uint8Array): string {
  return base64Encode(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function sha1Hex(value: string): string {
  // This is not for password storage; it only creates stable non-reversible GitHub document ids.
  const utf8 = new TextEncoder().encode(value);
  return Array.from(new Uint8Array(sha1(utf8))).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function sha1(bytes: Uint8Array): Uint8Array {
  const words: number[] = [];
  for (let index = 0; index < bytes.length; index += 1) {
    words[index >> 2] |= bytes[index] << (24 - (index % 4) * 8);
  }
  words[bytes.length >> 2] |= 0x80 << (24 - (bytes.length % 4) * 8);
  words[(((bytes.length + 8) >> 6) + 1) * 16 - 1] = bytes.length * 8;

  let h0 = 0x67452301;
  let h1 = 0xefcdab89;
  let h2 = 0x98badcfe;
  let h3 = 0x10325476;
  let h4 = 0xc3d2e1f0;

  for (let block = 0; block < words.length; block += 16) {
    const w = new Array<number>(80);
    for (let i = 0; i < 16; i += 1) w[i] = words[block + i] | 0;
    for (let i = 16; i < 80; i += 1) w[i] = rotateLeft(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);

    let a = h0;
    let b = h1;
    let c = h2;
    let d = h3;
    let e = h4;

    for (let i = 0; i < 80; i += 1) {
      let f: number;
      let k: number;
      if (i < 20) {
        f = (b & c) | (~b & d);
        k = 0x5a827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdc;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6;
      }
      const temp = (rotateLeft(a, 5) + f + e + k + w[i]) | 0;
      e = d;
      d = c;
      c = rotateLeft(b, 30);
      b = a;
      a = temp;
    }

    h0 = (h0 + a) | 0;
    h1 = (h1 + b) | 0;
    h2 = (h2 + c) | 0;
    h3 = (h3 + d) | 0;
    h4 = (h4 + e) | 0;
  }

  const out = new Uint8Array(20);
  for (const [index, value] of [h0, h1, h2, h3, h4].entries()) {
    out[index * 4] = (value >>> 24) & 0xff;
    out[index * 4 + 1] = (value >>> 16) & 0xff;
    out[index * 4 + 2] = (value >>> 8) & 0xff;
    out[index * 4 + 3] = value & 0xff;
  }
  return out;
}

function rotateLeft(value: number, bits: number): number {
  return (value << bits) | (value >>> (32 - bits));
}
