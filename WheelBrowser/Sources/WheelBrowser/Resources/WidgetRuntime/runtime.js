const dashboard = document.getElementById('dashboard');

const state = {
  widgets: [],
  isEditing: false,
  cache: new Map(),
  inFlight: new Map(),
  liveUpdates: new Map(),
};

function postMessage(type, payload = {}) {
  window.webkit?.messageHandlers?.widgetBridge?.postMessage({ type, payload });
}

function notifyHeight() {
  requestAnimationFrame(() => {
    postMessage('dashboardHeightChanged', {
      height: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight),
    });
  });
}

function manifestCacheKey(manifest) {
  return `${manifest.id}:${stableStringify({
    skillChain: manifest.skillChain,
    returns: manifest.returns,
    ttl: manifest.ttl,
  })}`;
}

function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item)).join(',')}]`;
  }

  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(',')}}`;
  }

  return JSON.stringify(value);
}

function base64EncodeUTF8(value) {
  const bytes = new TextEncoder().encode(String(value));
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function escapeHTML(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function escapeAttribute(value) {
  return escapeHTML(value);
}

function safeURLString(value) {
  if (typeof value !== 'string' || !value.trim()) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

function isCacheFresh(entry) {
  if (!entry) return false;
  if (entry.ttl === 0) return false;
  return Date.now() - entry.fetchedAt < entry.ttl * 1000;
}

function tokenizePath(path) {
  if (!path) return [];
  const tokens = [];
  const regex = /([^[.\]]+)|\[(\*|\d+|".+?"|'.+?')\]/g;
  let match;
  while ((match = regex.exec(path)) !== null) {
    const token = match[1] ?? match[2];
    if (token === '*') {
      tokens.push({ type: 'wildcard' });
    } else if (/^\d+$/.test(token)) {
      tokens.push({ type: 'index', value: Number(token) });
    } else {
      tokens.push({ type: 'field', value: token.replace(/^["']|["']$/g, '') });
    }
  }
  return tokens;
}

function getPathValue(value, path) {
  if (path == null || path === '') return value;

  const tokens = tokenizePath(path);
  const visit = (current, index) => {
    if (index >= tokens.length) return current;
    const token = tokens[index];

    if (token.type === 'wildcard') {
      if (!Array.isArray(current)) return [];
      return current.map((item) => visit(item, index + 1)).flat();
    }

    if (current == null) return undefined;

    if (token.type === 'index') {
      if (!Array.isArray(current)) return undefined;
      return visit(current[token.value], index + 1);
    }

    return visit(current[token.value], index + 1);
  };

  return visit(value, 0);
}

function resolveRef(value, context) {
  if (typeof value === 'string' && value.startsWith('$')) {
    const ref = value.slice(1);
    const dotIndex = ref.indexOf('.');
    if (dotIndex === -1) {
      return context[ref];
    }

    const root = ref.slice(0, dotIndex);
    const path = ref.slice(dotIndex + 1);
    return getPathValue(context[root], path);
  }

  if (Array.isArray(value)) {
    return value.map((item) => resolveRef(item, context));
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [key, resolveRef(nested, context)])
    );
  }

  return value;
}

function parseJsonPath(json, path) {
  const value = typeof json === 'string' ? JSON.parse(json) : json;
  return path ? getPathValue(value, path) : value;
}

function parseHtml({ html, selector, attribute, extractText = true, limit }) {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  const nodes = Array.from(doc.querySelectorAll(selector));
  const selected = typeof limit === 'number' ? nodes.slice(0, limit) : nodes;
  return selected.map((node) => {
    if (attribute) return node.getAttribute(attribute);
    return extractText === false ? node.innerHTML : node.textContent.trim();
  });
}

function extractWithRegex({ text, pattern, flags = 'g', group = 0 }) {
  const regex = new RegExp(pattern, flags);
  const matches = [];
  for (const match of text.matchAll(regex)) {
    matches.push(match[group] ?? '');
  }
  return matches;
}

function parseCsv({ csv, hasHeader = true, delimiter = ',' }) {
  const rows = [];
  let row = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < csv.length; i += 1) {
    const char = csv[i];
    const next = csv[i + 1];

    if (char === '"' && inQuotes && next === '"') {
      current += '"';
      i += 1;
    } else if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === delimiter && !inQuotes) {
      row.push(current);
      current = '';
    } else if ((char === '\n' || char === '\r') && !inQuotes) {
      if (char === '\r' && next === '\n') i += 1;
      row.push(current);
      rows.push(row);
      row = [];
      current = '';
    } else {
      current += char;
    }
  }

  if (current.length > 0 || row.length > 0) {
    row.push(current);
    rows.push(row);
  }

  if (!hasHeader) return rows;
  const [header = [], ...body] = rows;
  return body.map((values) =>
    Object.fromEntries(header.map((key, index) => [key, values[index] ?? '']))
  );
}

function tokenizeExpression(expression) {
  const tokens = [];
  let index = 0;
  while (index < expression.length) {
    const char = expression[index];
    if (/\s/.test(char)) {
      index += 1;
      continue;
    }
    if ('+-*/()'.includes(char)) {
      tokens.push({ type: char });
      index += 1;
      continue;
    }
    if (/\d|\./.test(char)) {
      let end = index + 1;
      while (end < expression.length && /[\d.]/.test(expression[end])) end += 1;
      tokens.push({ type: 'number', value: Number(expression.slice(index, end)) });
      index = end;
      continue;
    }
    if (expression.startsWith('item', index)) {
      let end = index + 4;
      while (end < expression.length && /[A-Za-z0-9_.[\]'"]/.test(expression[end])) end += 1;
      tokens.push({ type: 'itemPath', value: expression.slice(index, end) });
      index = end;
      continue;
    }
    throw new Error(`Unsupported transform expression token near '${expression.slice(index)}'`);
  }
  return tokens;
}

function evaluateArithmetic(expression, item) {
  const tokens = tokenizeExpression(expression);
  let index = 0;

  function peek() {
    return tokens[index];
  }

  function consume(type) {
    const token = tokens[index];
    if (!token || token.type !== type) {
      throw new Error(`Expected token '${type}'.`);
    }
    index += 1;
    return token;
  }

  function parsePrimary() {
    const token = peek();
    if (!token) throw new Error('Unexpected end of expression.');
    if (token.type === 'number') {
      index += 1;
      return token.value;
    }
    if (token.type === 'itemPath') {
      index += 1;
      const path = token.value.replace(/^item\.?/, '');
      const resolved = path ? getPathValue(item, path) : item;
      return Number(resolved ?? 0);
    }
    if (token.type === '(') {
      consume('(');
      const value = parseExpression();
      consume(')');
      return value;
    }
    if (token.type === '-') {
      consume('-');
      return -parsePrimary();
    }
    throw new Error(`Unexpected token '${token.type}'.`);
  }

  function parseTerm() {
    let value = parsePrimary();
    while (peek() && (peek().type === '*' || peek().type === '/')) {
      const operator = consume(peek().type).type;
      const right = parsePrimary();
      value = operator === '*' ? value * right : value / right;
    }
    return value;
  }

  function parseExpression() {
    let value = parseTerm();
    while (peek() && (peek().type === '+' || peek().type === '-')) {
      const operator = consume(peek().type).type;
      const right = parseTerm();
      value = operator === '+' ? value + right : value - right;
    }
    return value;
  }

  const value = parseExpression();
  if (index !== tokens.length) {
    throw new Error('Unexpected trailing expression tokens.');
  }
  return value;
}

function evaluateTransformExpression(expression, item) {
  const trimmed = expression.trim();

  let match = trimmed.match(/^new Date\((.+)\)\.toLocaleDateString\(\)$/);
  if (match) {
    return new Date(resolveExpressionValue(match[1], item)).toLocaleDateString();
  }

  match = trimmed.match(/^Math\.round\((.+)\)$/);
  if (match) {
    return Math.round(Number(resolveExpressionValue(match[1], item)));
  }

  match = trimmed.match(/^(.+)\.toFixed\((\d+)\)$/);
  if (match) {
    return Number(resolveExpressionValue(match[1], item)).toFixed(Number(match[2]));
  }

  return evaluateArithmetic(trimmed, item);
}

function resolveExpressionValue(expression, item) {
  const trimmed = expression.trim();
  if (trimmed.startsWith('item')) {
    const path = trimmed.replace(/^item\.?/, '');
    return path ? getPathValue(item, path) : item;
  }
  if (/^\d+(\.\d+)?$/.test(trimmed)) {
    return Number(trimmed);
  }
  return evaluateTransformExpression(trimmed, item);
}

function applyMapping(item, mapping) {
  return Object.fromEntries(
    Object.entries(mapping).map(([key, rule]) => {
      if (typeof rule !== 'string') return [key, rule];
      if (rule.startsWith('literal:')) return [key, rule.slice('literal:'.length)];
      if (rule.startsWith('expr:')) return [key, evaluateTransformExpression(rule.slice('expr:'.length), item)];
      return [key, getPathValue(item, rule)];
    })
  );
}

function transform({ data, mapping }) {
  if (Array.isArray(data)) {
    return data.map((item) => applyMapping(item, mapping));
  }
  return applyMapping(data, mapping);
}

function matchesFilter(item, filter = {}) {
  return Object.entries(filter).every(([field, predicate]) => {
    const value = getPathValue(item, field);
    if (predicate == null || typeof predicate !== 'object' || Array.isArray(predicate)) {
      return value === predicate;
    }

    return Object.entries(predicate).every(([operator, expected]) => {
      switch (operator) {
        case '$eq': return value === expected;
        case '$ne': return value !== expected;
        case '$gt': return value > expected;
        case '$gte': return value >= expected;
        case '$lt': return value < expected;
        case '$lte': return value <= expected;
        case '$in': return Array.isArray(expected) && expected.includes(value);
        case '$contains': return String(value ?? '').includes(String(expected));
        default: return false;
      }
    });
  });
}

function filterSort({ data, filter = null, sortBy = null, ascending = true, limit = null }) {
  let output = Array.isArray(data) ? [...data] : [];
  if (filter) {
    output = output.filter((item) => matchesFilter(item, filter));
  }
  if (sortBy) {
    output.sort((left, right) => {
      const a = getPathValue(left, sortBy);
      const b = getPathValue(right, sortBy);
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      if (a < b) return ascending ? -1 : 1;
      if (a > b) return ascending ? 1 : -1;
      return 0;
    });
  }
  if (typeof limit === 'number') {
    output = output.slice(0, limit);
  }
  return output;
}

function mergeArrays({ arrays, joinKey = null, label = null }) {
  if (!Array.isArray(arrays)) return [];

  if (!joinKey) {
    return arrays.flatMap((array) => {
      if (!Array.isArray(array)) return [];
      if (!label) return array;
      return array.map((item) => ({ label, ...item }));
    });
  }

  const [base = [], ...rest] = arrays;
  return base.map((item) => {
    const merged = { ...item };
    for (const array of rest) {
      const match = Array.isArray(array)
        ? array.find((candidate) => candidate?.[joinKey] === item?.[joinKey])
        : null;
      if (match) Object.assign(merged, match);
    }
    return merged;
  });
}

function computeStats({ data, field, ops }) {
  const values = (Array.isArray(data) ? data : [])
    .map((item) => Number(getPathValue(item, field)))
    .filter((value) => Number.isFinite(value));

  const result = {};
  for (const op of ops) {
    switch (op) {
      case 'avg':
        result.avg = values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0;
        break;
      case 'sum':
        result.sum = values.reduce((sum, value) => sum + value, 0);
        break;
      case 'min':
        result.min = values.length ? Math.min(...values) : null;
        break;
      case 'max':
        result.max = values.length ? Math.max(...values) : null;
        break;
      case 'last':
        result.last = values.length ? values[values.length - 1] : null;
        break;
      case 'first':
        result.first = values.length ? values[0] : null;
        break;
      case 'count':
        result.count = values.length;
        break;
      default:
        break;
    }
  }
  return result;
}

const COMMON_TIME_ZONES = {
  pst: 'America/Los_Angeles',
  pdt: 'America/Los_Angeles',
  pt: 'America/Los_Angeles',
  pacific: 'America/Los_Angeles',
  pacifictime: 'America/Los_Angeles',
  'us/pacific': 'America/Los_Angeles',
  mst: 'America/Denver',
  mdt: 'America/Denver',
  mt: 'America/Denver',
  mountain: 'America/Denver',
  cst: 'America/Chicago',
  cdt: 'America/Chicago',
  ct: 'America/Chicago',
  central: 'America/Chicago',
  est: 'America/New_York',
  edt: 'America/New_York',
  et: 'America/New_York',
  eastern: 'America/New_York',
  utc: 'UTC',
  gmt: 'UTC',
  london: 'Europe/London',
  paris: 'Europe/Paris',
  cet: 'Europe/Paris',
  cest: 'Europe/Paris',
  tokyo: 'Asia/Tokyo',
  jst: 'Asia/Tokyo',
  sydney: 'Australia/Sydney',
  aest: 'Australia/Sydney',
  aedt: 'Australia/Sydney',
};

function normalizeDateTimeStyle(style, fallback = null) {
  if (typeof style !== 'string') return fallback;
  switch (style.trim().toLowerCase()) {
    case 'none':
      return null;
    case 'short':
    case 'medium':
    case 'long':
    case 'full':
      return style.trim().toLowerCase();
    default:
      return fallback;
  }
}

function normalizeTimeZoneIdentifier(value) {
  const localTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  if (typeof value !== 'string' || !value.trim()) {
    return localTimeZone;
  }

  const trimmed = value.trim();
  const normalizedKey = trimmed.toLowerCase().replace(/\s+/g, '');
  const candidate = COMMON_TIME_ZONES[trimmed.toLowerCase()] || COMMON_TIME_ZONES[normalizedKey] || trimmed;

  try {
    new Intl.DateTimeFormat('en-US', { timeZone: candidate }).format(new Date());
    return candidate;
  } catch {
    throw new Error(`Unsupported time zone '${value}'.`);
  }
}

function currentDateTime(params = {}) {
  const now = new Date();
  const locale = typeof params.locale === 'string' && params.locale.trim() ? params.locale.trim() : undefined;
  const label = typeof params.label === 'string' && params.label.trim() ? params.label.trim() : null;
  const timeZone = normalizeTimeZoneIdentifier(params.timeZone);
  const showTimeZone = params.showTimeZone !== false;
  const includeSeconds = Boolean(params.includeSeconds);
  const hour12 = typeof params.hour12 === 'boolean' ? params.hour12 : undefined;
  const dateStyle = normalizeDateTimeStyle(params.dateStyle, null);
  const timeStyle = normalizeDateTimeStyle(params.timeStyle, includeSeconds ? 'medium' : 'short');

  const timeOptions = {
    timeZone,
    hour: 'numeric',
    minute: '2-digit',
  };
  if (includeSeconds) {
    timeOptions.second = '2-digit';
  }
  if (hour12 !== undefined) {
    timeOptions.hour12 = hour12;
  }

  const dateOptions = {
    timeZone,
    dateStyle: dateStyle || 'medium',
  };
  if (hour12 !== undefined) {
    dateOptions.hour12 = hour12;
  }

  const formattedOptions = { timeZone };
  if (dateStyle) {
    formattedOptions.dateStyle = dateStyle;
  }
  if (timeStyle) {
    formattedOptions.timeStyle = timeStyle;
  }
  if (!dateStyle && !timeStyle) {
    formattedOptions.timeStyle = includeSeconds ? 'medium' : 'short';
  }
  if (hour12 !== undefined) {
    formattedOptions.hour12 = hour12;
  }

  const time = new Intl.DateTimeFormat(locale, timeOptions).format(now);
  const date = new Intl.DateTimeFormat(locale, dateOptions).format(now);
  const timeZoneAbbreviation = new Intl.DateTimeFormat(locale, {
    timeZone,
    timeZoneName: 'short',
  }).formatToParts(now).find((part) => part.type === 'timeZoneName')?.value || timeZone;

  let formatted = new Intl.DateTimeFormat(locale, formattedOptions).format(now);
  if (showTimeZone && !formatted.includes(timeZoneAbbreviation)) {
    formatted = `${formatted} ${timeZoneAbbreviation}`;
  }

  return {
    label,
    content: formatted,
    formatted,
    date,
    time,
    timeZone,
    timeZoneAbbreviation,
    iso: now.toISOString(),
    timestamp: now.getTime(),
  };
}

async function fetchUrl(params, manifest, options = {}) {
  const remoteURL = params.url;
  const method = typeof params.method === 'string' && params.method.trim()
    ? params.method.trim().toUpperCase()
    : 'GET';
  const headers = params.headers && typeof params.headers === 'object' && !Array.isArray(params.headers)
    ? Object.fromEntries(
      Object.entries(params.headers)
        .filter(([key, value]) => typeof key === 'string' && typeof value === 'string')
    )
    : {};
  const body = params.body == null
    ? null
    : (typeof params.body === 'string' ? params.body : JSON.stringify(params.body));
  const query = new URLSearchParams({ url: remoteURL, method });
  if (Object.keys(headers).length > 0) {
    query.set('headers', base64EncodeUTF8(JSON.stringify(headers)));
  }
  if (method === 'POST' && body != null) {
    query.set('body', base64EncodeUTF8(body));
  }
  const proxied = `widget-fetch://request/${manifest.id}?${query.toString()}`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);

  try {
    const response = await fetch(proxied, { signal: controller.signal });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} ${response.statusText}`);
    }
    return await response.text();
  } finally {
    clearTimeout(timeout);
  }
}

const registry = {
  currentDateTime,
  fetchUrl,
  parseHtml,
  parseJson: ({ json, path }) => parseJsonPath(json, path),
  extractWithRegex,
  parseCsv,
  transform,
  filterSort,
  mergeArrays,
  computeStats,
};

async function executeSkillChain(manifest, { force = false } = {}) {
  const cacheKey = manifestCacheKey(manifest);
  const cached = state.cache.get(cacheKey);
  if (!force && isCacheFresh(cached)) {
    return cached.data;
  }

  if (!force && state.inFlight.has(cacheKey)) {
    return state.inFlight.get(cacheKey);
  }

  const execution = (async () => {
    const context = {};
    for (const step of [...manifest.skillChain].sort((left, right) => left.step - right.step)) {
      const skill = registry[step.skill];
      if (!skill) throw new Error(`Unknown skill '${step.skill}'.`);
      const params = resolveRef(step.params, context);
      context[step.outputKey] = await skill(params, manifest);
    }
    const result = context[manifest.returns];
    state.cache.set(cacheKey, {
      data: result,
      fetchedAt: Date.now(),
      ttl: manifest.ttl,
    });
    return result;
  })();

  state.inFlight.set(cacheKey, execution);
  try {
    return await execution;
  } finally {
    state.inFlight.delete(cacheKey);
  }
}

function isLiveDateTimeWidget(manifest) {
  return Array.isArray(manifest?.skillChain)
    && manifest.skillChain.some((step) => step?.skill === 'currentDateTime');
}

function stopLiveUpdates(id) {
  const handle = state.liveUpdates.get(id);
  if (!handle) return;

  if (handle.timeoutId) clearTimeout(handle.timeoutId);
  if (handle.intervalId) clearInterval(handle.intervalId);
  state.liveUpdates.delete(id);
}

function stopAllLiveUpdates() {
  for (const id of Array.from(state.liveUpdates.keys())) {
    stopLiveUpdates(id);
  }
}

function scheduleLiveUpdates(manifest) {
  if (!isLiveDateTimeWidget(manifest)) return;

  stopLiveUpdates(manifest.id);

  const handle = {
    timeoutId: null,
    intervalId: null,
    isUpdating: false,
  };

  const tick = () => {
    const card = dashboard.querySelector(`[data-widget-id="${manifest.id}"]`);
    const content = card?.querySelector('.widget-content');
    if (!card || !content || handle.isUpdating) return;

    handle.isUpdating = true;
    executeSkillChain(manifest, { force: true })
      .then((data) => {
        applyCardPresentation(card, manifest, data);
        content.innerHTML = renderWidgetContent(manifest, data);
      })
      .catch(() => {
        // Keep the current rendered value if a live local update fails unexpectedly.
      })
      .finally(() => {
        handle.isUpdating = false;
      });
  };

  const delay = Math.max(80, 1000 - (Date.now() % 1000));
  handle.timeoutId = setTimeout(() => {
    tick();
    handle.intervalId = setInterval(tick, 1000);
  }, delay);

  state.liveUpdates.set(manifest.id, handle);
}

const ACTION_ICONS = {
  toggleVisualization: `
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M4 15c2-3 4-4.5 6-4.5s4 1.5 6 1.5 4-1.5 4-1.5"></path>
      <path d="M4 19h16"></path>
      <path d="M8 7h.01"></path>
      <path d="M12 5h.01"></path>
      <path d="M16 8h.01"></path>
    </svg>
  `,
  refresh: `
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M20 12a8 8 0 1 1-2.34-5.66"></path>
      <path d="M20 4v6h-6"></path>
    </svg>
  `,
  moveUp: `
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 18V6"></path>
      <path d="m7 11 5-5 5 5"></path>
    </svg>
  `,
  moveDown: `
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 6v12"></path>
      <path d="m7 13 5 5 5-5"></path>
    </svg>
  `,
  remove: `
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M18 6 6 18"></path>
      <path d="M6 6l12 12"></path>
    </svg>
  `,
  toggleLayout: `
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="4" y="6" width="16" height="12" rx="2"></rect>
      <path d="M9 6v12"></path>
    </svg>
  `,
};

function createIconButton({ label, action, extraClass = '' }) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = `widget-button icon-button ${extraClass}`.trim();
  button.dataset.widgetAction = action;
  button.title = label;
  button.setAttribute('aria-label', label);
  button.innerHTML = `${ACTION_ICONS[action] || ''}<span class="sr-only">${label}</span>`;
  return button;
}

function widgetVisualizationMode(manifest) {
  if (manifest.widgetType === 'lineChart') {
    return manifest.visualizationPreference === 'value' ? 'value' : 'lineChart';
  }

  if (manifest.widgetType === 'statCard' || manifest.widgetType === 'priceCard') {
    return 'value';
  }

  return manifest.widgetType;
}

function supportsVisualizationToggle(manifest) {
  return manifest.widgetType === 'lineChart'
    && Array.isArray(manifest.config?.series)
    && manifest.config.series.length === 1;
}

function visualizationToggleActionLabel(manifest) {
  return widgetVisualizationMode(manifest) === 'value'
    ? 'Show Line Graph'
    : 'Show Instant Value';
}

function nextVisualizationPreference(preference) {
  switch (preference) {
    case 'value':
      return 'lineChart';
    case 'lineChart':
      return 'value';
    default:
      return 'value';
  }
}

function widgetChromeLabel(manifest) {
  if (Array.isArray(manifest?.skillChain) && manifest.skillChain.some((step) => step?.skill === 'currentDateTime')) {
    return manifest.widgetType === 'list' ? 'World Clock' : 'Clock';
  }

  if (manifest.widgetType === 'lineChart' && widgetVisualizationMode(manifest) === 'value') {
    return 'Sensor';
  }

  switch (manifest.widgetType) {
    case 'statCard':
      return 'Metric';
    case 'priceCard':
      return 'Live Price';
    case 'list':
      return manifest.config?.variant === 'ranked' ? 'Ranked List' : 'Live List';
    case 'table':
      return 'Table';
    case 'text':
      return manifest.config?.markdown ? 'Rich Text' : 'Text';
    case 'barChart':
      return 'Comparison';
    case 'lineChart':
      return 'Trend';
    default:
      return 'Widget';
  }
}

function widgetLayoutDensity(manifest) {
  if (manifest.layoutPreference === 'fullWidth') {
    return 'wide';
  }

  if (manifest.widgetType === 'lineChart' && widgetVisualizationMode(manifest) === 'value') {
    return 'compact';
  }

  switch (manifest.widgetType) {
    case 'statCard':
    case 'priceCard':
      return 'compact';
    case 'text':
      return manifest.config?.markdown ? 'regular' : 'compact';
    case 'table':
    case 'barChart':
    case 'lineChart':
      return 'wide';
    case 'list':
      return manifest.config?.variant === 'compact' || manifest.config?.variant === 'ranked'
        ? 'regular'
        : 'wide';
    default:
      return 'regular';
  }
}

function nextLayoutPreference(preference) {
  switch (preference) {
    case 'singleColumn':
      return 'fullWidth';
    case 'fullWidth':
      return 'auto';
    default:
      return 'singleColumn';
  }
}

function layoutPreferenceActionLabel(preference) {
  switch (preference) {
    case 'singleColumn':
      return 'Make Full Width';
    case 'fullWidth':
      return 'Use Auto Width';
    default:
      return 'Pin to One Column';
  }
}

function dashboardLayoutClasses(widgets) {
  const count = widgets.length;
  const countClass = count === 0 ? 'dashboard--empty' : count <= 4 ? `dashboard--count-${count}` : 'dashboard--count-many';
  const densities = widgets.map(widgetLayoutDensity);
  const allCompact = densities.length > 0 && densities.every((density) => density === 'compact');
  const hasWide = densities.some((density) => density === 'wide');
  const hasFullWidth = widgets.some((widget) => widget.layoutPreference === 'fullWidth');
  const heroIndex = count === 3 && !allCompact
    ? widgets.findIndex((widget, index) => densities[index] !== 'compact' && widget.layoutPreference === 'auto')
    : -1;

  return {
    classNames: ['dashboard', countClass, allCompact ? 'dashboard--all-compact' : 'dashboard--mixed', hasWide ? 'dashboard--has-wide' : 'dashboard--no-wide', hasFullWidth ? 'dashboard--has-full-width' : 'dashboard--auto-widths'],
    heroIndex,
  };
}

function formatValue(value, prefix = '', suffix = '') {
  if (value == null) return '—';
  return `${prefix}${value}${suffix}`;
}

function numericValue(value) {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }

  if (typeof value === 'string') {
    const normalized = value.replace(/,/g, '').replace(/[^0-9.+-]/g, '');
    if (!normalized) return null;
    const parsed = Number(normalized);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

function formatCompactNumber(value) {
  const number = numericValue(value);
  if (number == null) return '—';

  const magnitude = Math.abs(number);
  const fractionDigits = magnitude >= 100 ? 0 : magnitude >= 10 ? 1 : 2;
  const minimumFractionDigits = magnitude < 10 ? Math.min(fractionDigits, 2) : 0;

  return new Intl.NumberFormat(undefined, {
    minimumFractionDigits,
    maximumFractionDigits: fractionDigits,
  }).format(number);
}

function formatChartValue(value, prefix = '', suffix = '') {
  if (value == null) return '—';
  return `${prefix}${formatCompactNumber(value)}${suffix}`;
}

function deltaToneClass(value) {
  const number = numericValue(value);
  if (number != null) {
    if (number > 0) return 'is-positive';
    if (number < 0) return 'is-negative';
    return 'is-neutral';
  }

  const text = String(value ?? '').trim().toLowerCase();
  if (!text) return 'is-neutral';
  if (text.startsWith('+') || text.includes('up')) return 'is-positive';
  if (text.startsWith('-') || text.includes('down')) return 'is-negative';
  return 'is-neutral';
}

function isClockPayload(data) {
  return Boolean(
    data
    && typeof data === 'object'
    && typeof data.time === 'string'
    && typeof data.date === 'string'
    && (typeof data.timeZoneAbbreviation === 'string' || typeof data.timeZone === 'string')
  );
}

function splitClockDisplay(time) {
  const value = String(time ?? '').trim();
  const match = value.match(/^(.+?)(?:\s+([AP]M))?$/i);
  if (!match) {
    return { primary: value || '—', suffix: null };
  }

  return {
    primary: match[1],
    suffix: match[2] ? match[2].toUpperCase() : null,
  };
}

function renderClockWidget(data) {
  const zoneLabel = data?.timeZoneAbbreviation || data?.timeZone || 'Local';
  const zoneDetail = data?.timeZone && data.timeZone !== zoneLabel ? data.timeZone : null;
  const display = splitClockDisplay(data?.time);

  return `
    <div class="clock-panel">
      <div class="clock-panel__orbits" aria-hidden="true">
        <div class="clock-orbit clock-orbit--large"></div>
        <div class="clock-orbit clock-orbit--small"></div>
      </div>
      <div class="clock-header">
        <div class="clock-label">${escapeHTML(data?.label || 'Local Time')}</div>
        <div class="clock-zone-chip">${escapeHTML(zoneLabel)}</div>
      </div>
      <div class="clock-body">
        <div class="clock-time">
          <span class="clock-time-primary">${escapeHTML(display.primary)}</span>
          ${display.suffix ? `<span class="clock-time-suffix">${escapeHTML(display.suffix)}</span>` : ''}
        </div>
        <div class="clock-date">${escapeHTML(data?.date || '')}</div>
      </div>
      ${zoneDetail ? `<div class="clock-footer">${escapeHTML(zoneDetail)}</div>` : ''}
    </div>
  `;
}

function renderMetricPanel({ valueMarkup, delta = null, footnote = null }) {
  const deltaMarkup = delta != null
    ? `<div class="metric-pill ${deltaToneClass(delta)}">${escapeHTML(String(delta))}</div>`
    : '';
  const footnoteMarkup = footnote
    ? `<div class="metric-footnote">${escapeHTML(footnote)}</div>`
    : '';

  return `
    <div class="metric-panel">
      <div class="metric-panel__value">${valueMarkup}</div>
      <div class="metric-panel__footer">
        ${deltaMarkup}
        ${footnoteMarkup}
      </div>
    </div>
  `;
}

function renderMarkdown(content) {
  const escaped = escapeHTML(content);

  return escaped
    .replace(/\[(.+?)\]\((https?:\/\/.+?)\)/g, (_, label, href) => {
      const safeHref = safeURLString(href);
      if (!safeHref) {
        return label;
      }
      return `<a href="${escapeAttribute(safeHref)}">${label}</a>`;
    })
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\*(.+?)\*/g, '<em>$1</em>')
    .replace(/\n/g, '<br>');
}

function renderLinkOrText(label, href, className = '') {
  const safeLabel = escapeHTML(label);
  const safeHref = safeURLString(href);
  if (!safeHref) {
    return `<span class="${className}">${safeLabel}</span>`;
  }
  return `<a class="${className}" href="${escapeAttribute(safeHref)}">${safeLabel}</a>`;
}

function renderListItem(item, config, index) {
  const label = item?.[config.labelField] ?? '';
  const value = config.valueField ? item?.[config.valueField] : null;
  const subtitle = config.subtitleField ? item?.[config.subtitleField] : null;
  const badge = config.badgeField ? item?.[config.badgeField] : null;
  const caption = config.captionField ? item?.[config.captionField] : null;
  const icon = config.iconField ? item?.[config.iconField] : null;
  const href = config.linkField ? item?.[config.linkField] : (item?.link || item?.url);
  const variant = config.variant || 'compact';

  const iconMarkup = icon != null ? `<span class="list-icon">${escapeHTML(icon)}</span>` : '';
  const badgeMarkup = badge != null ? `<span class="list-badge">${escapeHTML(badge)}</span>` : '';
  const valueMarkup = value != null ? `<div class="list-trailing">${escapeHTML(value)}</div>` : '';
  const subtitleMarkup = subtitle != null ? `<div class="list-subtitle">${escapeHTML(subtitle)}</div>` : '';
  const captionMarkup = caption != null ? `<div class="list-caption">${escapeHTML(caption)}</div>` : '';
  const rankMarkup = variant === 'ranked' ? `<div class="list-rank">${index + 1}</div>` : '';
  const labelMarkup = renderLinkOrText(label, href, 'list-link');

  return `
    <div class="list-item is-${escapeAttribute(variant)}">
      ${rankMarkup}
      <div class="list-main">
        <div class="list-top">
          <div class="list-title-row">
            ${iconMarkup}
            ${labelMarkup}
            ${badgeMarkup}
          </div>
          ${valueMarkup}
        </div>
        ${subtitleMarkup}
        ${captionMarkup}
      </div>
    </div>
  `;
}

function renderBarChart(config, data) {
  const width = 640;
  const height = 240;
  const padding = { top: 22, right: 18, bottom: 34, left: 28 };
  const values = data
    .map((item) => numericValue(item?.[config.yField]))
    .filter((value) => value != null);
  const max = Math.max(...values, 1);
  const plotWidth = width - padding.left - padding.right;
  const plotHeight = height - padding.top - padding.bottom;
  const barWidth = plotWidth / Math.max(data.length, 1);
  const color = config.color || '#0d8f73';
  const labels = axisLabelsFromData(data, config.xField);
  const peakValue = values.length ? Math.max(...values) : null;

  const gridLines = Array.from({ length: 4 }, (_, index) => {
    const ratio = index / 3;
    const y = padding.top + plotHeight * ratio;
    return `<line class="chart-gridline" x1="${padding.left}" y1="${y}" x2="${width - padding.right}" y2="${y}"></line>`;
  }).join('');

  const bars = data.map((item, index) => {
    const value = numericValue(item?.[config.yField]) ?? 0;
    const barHeight = (plotHeight * value) / max;
    const x = padding.left + index * barWidth + Math.max((barWidth - 18) / 2, 6);
    const y = height - padding.bottom - barHeight;
    return `<rect class="chart-bar" x="${x}" y="${y}" width="${Math.max(barWidth - 12, 12)}" height="${barHeight}" fill="${escapeAttribute(color)}"></rect>`;
  }).join('');

  return `
    <div class="chart-shell">
      <div class="chart-meta">
        <div class="chart-legend">
          <span class="chart-legend__item">
            <span class="chart-swatch" style="--series-color: ${escapeAttribute(color)}"></span>
            <span class="chart-legend__label">${escapeHTML(config.title)}</span>
          </span>
        </div>
        ${peakValue != null ? `<div class="chart-summary"><span class="chart-summary-pill">Peak ${escapeHTML(formatChartValue(peakValue, config.yPrefix || '', config.yUnit ? ` ${config.yUnit}` : ''))}</span></div>` : ''}
      </div>
      <div class="chart-wrap">
        <svg class="chart-svg" viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeAttribute(config.title)}">
          ${gridLines}
          <line class="chart-axis" x1="${padding.left}" y1="${height - padding.bottom}" x2="${width - padding.right}" y2="${height - padding.bottom}"></line>
          ${bars}
        </svg>
      </div>
      ${renderAxisLabels(labels)}
    </div>
  `;
}

const DEFAULT_CHART_COLORS = ['#0d8f73', '#c18550', '#4259b2', '#b04444'];

function chartColor(series, index) {
  return series.color || DEFAULT_CHART_COLORS[index % DEFAULT_CHART_COLORS.length];
}

function axisLabelsFromData(data, xField) {
  if (!Array.isArray(data) || data.length === 0) return [];

  const indexes = Array.from(new Set([0, Math.floor((data.length - 1) / 2), data.length - 1]));
  return indexes
    .map((index) => {
      const label = data[index]?.[xField];
      return label == null ? '' : String(label);
    })
    .filter((label) => label);
}

function renderAxisLabels(labels) {
  const slots = labels.length >= 3
    ? labels.slice(0, 3)
    : labels.length === 2
      ? [labels[0], '', labels[1]]
      : labels.length === 1
        ? [labels[0], '', labels[0]]
        : [];

  if (slots.length === 0) return '';

  return `
    <div class="chart-axis-labels">
      ${slots.map((label) => `<span>${escapeHTML(label)}</span>`).join('')}
    </div>
  `;
}

function linePathFromCoordinates(points) {
  let path = '';
  let started = false;

  for (const point of points) {
    if (!point) {
      started = false;
      continue;
    }

    path += `${started ? ' L' : 'M'} ${point.x} ${point.y}`;
    started = true;
  }

  return path;
}

function areaPathFromCoordinates(points, baselineY) {
  const validPoints = points.filter(Boolean);
  if (validPoints.length < 2) return '';

  return `${validPoints.map((point, index) => `${index === 0 ? 'M' : 'L'} ${point.x} ${point.y}`).join(' ')} L ${validPoints[validPoints.length - 1].x} ${baselineY} L ${validPoints[0].x} ${baselineY} Z`;
}

function lastDefinedPoint(points) {
  for (let index = points.length - 1; index >= 0; index -= 1) {
    if (points[index]) {
      return points[index];
    }
  }
  return null;
}

function firstDefinedPoint(points) {
  for (let index = 0; index < points.length; index += 1) {
    if (points[index]) {
      return points[index];
    }
  }
  return null;
}

function formatSignedPercent(value) {
  if (!Number.isFinite(value)) return null;
  const fractionDigits = Math.abs(value) >= 10 ? 1 : 2;
  return `${value >= 0 ? '+' : ''}${value.toFixed(fractionDigits)}%`;
}

function formatSignedValue(value, prefix = '', suffix = '') {
  if (!Number.isFinite(value)) return null;
  const sign = value >= 0 ? '+' : '-';
  return `${sign}${formatChartValue(Math.abs(value), prefix, suffix)}`;
}

function renderLineChart(config, data) {
  if (!data.length || !config.series.length) {
    return '<div class="chart-empty">No data yet.</div>';
  }

  const width = 640;
  const height = 240;
  const padding = { top: 18, right: 18, bottom: 34, left: 44 };
  const allValues = config.series
    .flatMap((series) => data.map((item) => numericValue(item?.[series.field])))
    .filter((value) => Number.isFinite(value));
  if (allValues.length === 0) {
    return '<div class="chart-empty">No numeric chart data.</div>';
  }

  let min = Math.min(...allValues);
  let max = Math.max(...allValues);
  if (min === max) {
    const pad = min === 0 ? 1 : Math.abs(min) * 0.08;
    min -= pad;
    max += pad;
  } else {
    const pad = (max - min) * 0.12;
    min -= pad;
    max += pad;
  }

  const plotWidth = width - padding.left - padding.right;
  const plotHeight = height - padding.top - padding.bottom;
  const xStep = data.length > 1 ? plotWidth / (data.length - 1) : 0;
  const baselineY = height - padding.bottom;
  const gradientID = `chart-gradient-${Math.random().toString(36).slice(2, 9)}`;

  const gridLines = Array.from({ length: 4 }, (_, index) => {
    const ratio = index / 3;
    const y = padding.top + plotHeight * ratio;
    const value = max - (max - min) * ratio;
    return `
      <line class="chart-gridline" x1="${padding.left}" y1="${y}" x2="${width - padding.right}" y2="${y}"></line>
      <text class="chart-gridlabel" x="${padding.left - 10}" y="${y + 4}" text-anchor="end">${escapeHTML(formatCompactNumber(value))}</text>
    `;
  }).join('');

  const seriesCoordinates = config.series.map((series) => {
    return data.map((item, index) => {
      const value = numericValue(item?.[series.field]);
      if (value == null) return null;

      return {
        x: data.length > 1 ? padding.left + index * xStep : padding.left + plotWidth / 2,
        y: padding.top + ((max - value) / (max - min || 1)) * plotHeight,
        value,
      };
    });
  });

  const firstArea = areaPathFromCoordinates(seriesCoordinates[0], baselineY);
  const seriesMarkup = config.series.map((series, seriesIndex) => {
    const color = chartColor(series, seriesIndex);
    const points = seriesCoordinates[seriesIndex];
    const path = linePathFromCoordinates(points);
    const dots = config.showPoints
      ? points.filter(Boolean).map((point) => (
        `<circle class="chart-point" cx="${point.x}" cy="${point.y}" r="4" fill="${escapeAttribute(color)}"></circle>`
      )).join('')
      : '';
    return `<path class="chart-line" d="${path}" stroke="${escapeAttribute(color)}"></path>${dots}`;
  }).join('');

  const legendMarkup = config.series.map((series, index) => {
    const color = chartColor(series, index);
    return `
      <span class="chart-legend__item">
        <span class="chart-swatch" style="--series-color: ${escapeAttribute(color)}"></span>
        <span class="chart-legend__label">${escapeHTML(series.label)}</span>
      </span>
    `;
  }).join('');

  const summaryMarkup = config.series.map((series, index) => {
    const latest = lastDefinedPoint(seriesCoordinates[index]);
    if (!latest) return '';
    return `<span class="chart-summary-pill">${escapeHTML(series.label)} ${escapeHTML(formatChartValue(latest.value, config.yPrefix || ''))}</span>`;
  }).join('');

  const labels = axisLabelsFromData(data, config.xField);

  return `
    <div class="chart-shell">
      <div class="chart-meta">
        <div class="chart-legend">${legendMarkup}</div>
        ${summaryMarkup ? `<div class="chart-summary">${summaryMarkup}</div>` : ''}
      </div>
      <div class="chart-wrap">
        <svg class="chart-svg" viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeAttribute(config.title)}">
          <defs>
            <linearGradient id="${gradientID}" x1="0" x2="0" y1="0" y2="1">
              <stop offset="0%" stop-color="${escapeAttribute(chartColor(config.series[0], 0))}" stop-opacity="0.24"></stop>
              <stop offset="100%" stop-color="${escapeAttribute(chartColor(config.series[0], 0))}" stop-opacity="0"></stop>
            </linearGradient>
          </defs>
          ${gridLines}
          <line class="chart-axis" x1="${padding.left}" y1="${baselineY}" x2="${width - padding.right}" y2="${baselineY}"></line>
          ${firstArea ? `<path class="chart-area" d="${firstArea}" fill="url(#${gradientID})"></path>` : ''}
          ${seriesMarkup}
        </svg>
      </div>
      ${renderAxisLabels(labels)}
    </div>
  `;
}

function renderLineChartMetric(config, data) {
  const primarySeries = Array.isArray(config.series) ? config.series[0] : null;
  if (!primarySeries || !Array.isArray(data) || data.length === 0) {
    return '<div class="chart-empty">No data yet.</div>';
  }

  const points = data.map((item) => {
    const value = numericValue(item?.[primarySeries.field]);
    if (value == null) return null;
    return {
      label: item?.[config.xField] == null ? null : String(item[config.xField]),
      value,
    };
  });

  const firstPoint = firstDefinedPoint(points);
  const latestPoint = lastDefinedPoint(points);
  if (!firstPoint || !latestPoint) {
    return '<div class="chart-empty">No numeric chart data.</div>';
  }

  const deltaValue = latestPoint.value - firstPoint.value;
  const deltaPercent = firstPoint.value !== 0
    ? ((latestPoint.value - firstPoint.value) / Math.abs(firstPoint.value)) * 100
    : null;
  const suffix = config.yUnit ? ` ${config.yUnit}` : '';
  const delta = formatSignedPercent(deltaPercent) || formatSignedValue(deltaValue, config.yPrefix || '', suffix);
  const footnote = latestPoint.label ? `Latest ${latestPoint.label}` : null;

  return renderMetricPanel({
    valueMarkup: `<div class="price-value">${escapeHTML(formatValue(latestPoint.value, config.yPrefix || '', suffix))}</div>`,
    delta,
    footnote,
  });
}

function presentationModeFor(manifest, data) {
  if (manifest.widgetType === 'text' && !manifest.config?.markdown && isClockPayload(data)) {
    return 'clock';
  }
  if (manifest.widgetType === 'lineChart' && widgetVisualizationMode(manifest) === 'value') {
    return 'metric';
  }
  if (manifest.widgetType === 'statCard' || manifest.widgetType === 'priceCard') {
    return 'metric';
  }
  if (manifest.widgetType === 'lineChart') {
    return 'trend';
  }
  return null;
}

function applyCardPresentation(card, manifest, data) {
  card.dataset.visualization = widgetVisualizationMode(manifest);
  const mode = presentationModeFor(manifest, data);
  if (mode) {
    card.dataset.presentation = mode;
  } else {
    delete card.dataset.presentation;
  }
}

function renderWidgetContent(manifest, data) {
  switch (manifest.widgetType) {
    case 'statCard': {
      const config = manifest.config;
      const value = data?.[config.valueField];
      const delta = config.changeField ? data?.[config.changeField] : null;
      const deltaText = delta != null
        ? (config.changeIsPercent ? `${delta}%` : String(delta))
        : null;
      return renderMetricPanel({
        valueMarkup: `<div class="stat-value">${escapeHTML(formatValue(value, config.prefix || '', config.suffix || ''))}</div>`,
        delta: deltaText,
      });
    }
    case 'priceCard': {
      const config = manifest.config;
      const deltaField = config.changePercentField || config.changeField;
      return renderMetricPanel({
        valueMarkup: `<div class="price-value">${escapeHTML(formatValue(data?.[config.priceField], config.prefix || ''))}</div>`,
        delta: deltaField ? data?.[deltaField] ?? '—' : null,
        footnote: config.footnote,
      });
    }
    case 'list': {
      const config = manifest.config;
      const items = Array.isArray(data) ? data.slice(0, config.maxItems ?? data.length) : [];
      return `
        <div class="list is-${escapeAttribute(config.variant || 'compact')}">
          ${items.map((item, index) => renderListItem(item, config, index)).join('')}
        </div>
      `;
    }
    case 'table': {
      const config = manifest.config;
      const rows = Array.isArray(data) ? data.slice(0, config.maxRows ?? data.length) : [];
      return `
        <div class="table-wrap">
          <table>
            <thead>
              <tr>${config.columns.map((column) => `<th>${escapeHTML(column.header)}</th>`).join('')}</tr>
            </thead>
            <tbody>
              ${rows.map((row) => `
                <tr>
                  ${config.columns.map((column) => {
                    const raw = row?.[column.field];
                    const value = raw == null ? '—' : `${column.prefix || ''}${raw}`;
                    const safeHref = typeof raw === 'string' ? safeURLString(raw) : null;
                    if (safeHref) {
                      return `<td><a href="${escapeAttribute(safeHref)}">${escapeHTML(raw)}</a></td>`;
                    }
                    return `<td>${escapeHTML(value)}</td>`;
                  }).join('')}
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>
      `;
    }
    case 'text': {
      const config = manifest.config;
      const content = data?.content ?? '';
      if (!config.markdown && isClockPayload(data)) {
        return renderClockWidget(data);
      }
      return config.markdown
        ? `<div class="markdown">${renderMarkdown(content)}</div>`
        : `<div class="text-block">${escapeHTML(content)}</div>`;
    }
    case 'barChart':
      return renderBarChart(manifest.config, Array.isArray(data) ? data : []);
    case 'lineChart':
      return widgetVisualizationMode(manifest) === 'value'
        ? renderLineChartMetric(manifest.config, Array.isArray(data) ? data : [])
        : renderLineChart(manifest.config, Array.isArray(data) ? data : []);
    default:
      return `<div class="text-block">${JSON.stringify(data)}</div>`;
  }
}

function renderCard(manifest, options = {}) {
  const card = document.createElement('section');
  card.className = `widget-card widget-card--${manifest.widgetType} is-loading`;
  card.dataset.widgetId = manifest.id;
  card.dataset.widgetType = manifest.widgetType;
  card.dataset.density = widgetLayoutDensity(manifest);
  card.dataset.layoutPreference = manifest.layoutPreference || 'auto';
  card.dataset.visualization = widgetVisualizationMode(manifest);
  if (options.isHero && manifest.layoutPreference === 'auto') {
    card.classList.add('widget-card--hero');
  }

  const header = document.createElement('header');
  header.className = 'widget-header';
  const titleGroup = document.createElement('div');
  titleGroup.className = 'widget-title-group';
  const kicker = document.createElement('div');
  kicker.className = 'widget-kicker';
  kicker.textContent = widgetChromeLabel(manifest);
  const title = document.createElement('h2');
  title.className = 'widget-title';
  title.textContent = manifest.config.title || manifest.prompt;

  const actions = document.createElement('div');
  actions.className = 'widget-actions';
  if (supportsVisualizationToggle(manifest)) {
    actions.appendChild(createIconButton({
      label: visualizationToggleActionLabel(manifest),
      action: 'toggleVisualization',
    }));
  }
  actions.appendChild(createIconButton({ label: 'Refresh', action: 'refresh' }));

  if (state.isEditing) {
    actions.appendChild(createIconButton({
      label: layoutPreferenceActionLabel(manifest.layoutPreference),
      action: 'toggleLayout',
    }));
    actions.appendChild(createIconButton({ label: 'Move Up', action: 'moveUp' }));
    actions.appendChild(createIconButton({ label: 'Move Down', action: 'moveDown' }));
    actions.appendChild(createIconButton({ label: 'Remove', action: 'remove', extraClass: 'danger' }));
  }

  titleGroup.appendChild(kicker);
  titleGroup.appendChild(title);
  header.appendChild(titleGroup);
  header.appendChild(actions);

  const content = document.createElement('div');
  content.className = `widget-content widget-content--${manifest.widgetType}`;
  content.innerHTML = '<div class="skeleton"></div>';

  card.appendChild(header);
  card.appendChild(content);

  executeSkillChain(manifest)
    .then((data) => {
      card.classList.remove('is-loading');
      applyCardPresentation(card, manifest, data);
      content.innerHTML = renderWidgetContent(manifest, data);
      scheduleLiveUpdates(manifest);
      postMessage('widgetLoaded', { id: manifest.id });
      notifyHeight();
    })
    .catch((error) => {
      card.classList.remove('is-loading');
      stopLiveUpdates(manifest.id);
      delete card.dataset.presentation;
      content.innerHTML = `<div class="widget-error">${escapeHTML(error.message || String(error))}</div>`;
      postMessage('widgetError', { id: manifest.id, message: error.message || String(error) });
      notifyHeight();
    });

  return card;
}

function renderDashboard() {
  stopAllLiveUpdates();
  dashboard.innerHTML = '';
  const layout = dashboardLayoutClasses(state.widgets);
  dashboard.className = layout.classNames.join(' ');
  dashboard.classList.toggle('empty', state.widgets.length === 0);

  if (state.widgets.length === 0) {
    dashboard.innerHTML = `
      <section class="empty-state">
        <h2>No widgets yet</h2>
        <p>Add a widget to start building a live dashboard.</p>
      </section>
    `;
    notifyHeight();
    return;
  }

  for (const [index, manifest] of state.widgets.entries()) {
    dashboard.appendChild(renderCard(manifest, { isHero: index === layout.heroIndex }));
  }
  notifyHeight();
}

function normalizeDashboardWidget(widget) {
  if (widget?.manifest && typeof widget.manifest === 'object') {
    return {
      ...widget.manifest,
      layoutPreference: widget.layoutPreference || 'auto',
      visualizationPreference: widget.visualizationPreference || 'auto',
    };
  }

  return {
    ...widget,
    layoutPreference: widget?.layoutPreference || 'auto',
    visualizationPreference: widget?.visualizationPreference || 'auto',
  };
}

function applyDashboardState(payload) {
  state.widgets = (payload.widgets || []).map(normalizeDashboardWidget);
  state.isEditing = Boolean(payload.isEditing);
  renderDashboard();
}

function widgetIndexByID(id) {
  return state.widgets.findIndex((widget) => widget.id === id);
}

function refreshWidgetCard(manifest) {
  const card = dashboard.querySelector(`[data-widget-id="${manifest.id}"]`);
  if (card) {
    card.classList.add('is-loading');
    const content = card.querySelector('.widget-content');
    if (content) content.innerHTML = '<div class="skeleton"></div>';
  }

  executeSkillChain(manifest, { force: true })
    .then((data) => {
      const refreshed = dashboard.querySelector(`[data-widget-id="${manifest.id}"] .widget-content`);
      applyCardPresentation(card, manifest, data);
      if (refreshed) refreshed.innerHTML = renderWidgetContent(manifest, data);
      card?.classList.remove('is-loading');
      scheduleLiveUpdates(manifest);
      postMessage('widgetLoaded', { id: manifest.id });
      notifyHeight();
    })
    .catch((error) => {
      const refreshed = dashboard.querySelector(`[data-widget-id="${manifest.id}"] .widget-content`);
      stopLiveUpdates(manifest.id);
      if (card) delete card.dataset.presentation;
      if (refreshed) refreshed.innerHTML = `<div class="widget-error">${escapeHTML(error.message || String(error))}</div>`;
      card?.classList.remove('is-loading');
      postMessage('widgetError', { id: manifest.id, message: error.message || String(error) });
      notifyHeight();
    });
}

function handleWidgetAction(action, id) {
  const index = widgetIndexByID(id);
  if (index === -1) return;
  const manifest = state.widgets[index];

  switch (action) {
    case 'refresh':
      postMessage('widgetAction', { action, id });
      refreshWidgetCard(manifest);
      return;
    case 'toggleLayout': {
      const updated = [...state.widgets];
      const current = updated[index];
      updated[index] = {
        ...current,
        layoutPreference: nextLayoutPreference(current.layoutPreference),
      };
      state.widgets = updated;
      renderDashboard();
      postMessage('widgetAction', { action, id });
      return;
    }
    case 'toggleVisualization': {
      const updated = [...state.widgets];
      const current = updated[index];
      updated[index] = {
        ...current,
        visualizationPreference: nextVisualizationPreference(current.visualizationPreference),
      };
      state.widgets = updated;
      renderDashboard();
      postMessage('widgetAction', { action, id });
      return;
    }
    case 'remove':
      state.widgets = state.widgets.filter((widget) => widget.id !== id);
      renderDashboard();
      stopLiveUpdates(id);
      postMessage('widgetAction', { action, id });
      return;
    case 'moveUp':
      if (index > 0) {
        const reordered = [...state.widgets];
        [reordered[index - 1], reordered[index]] = [reordered[index], reordered[index - 1]];
        state.widgets = reordered;
        renderDashboard();
      }
      postMessage('widgetAction', { action, id });
      return;
    case 'moveDown':
      if (index < state.widgets.length - 1) {
        const reordered = [...state.widgets];
        [reordered[index], reordered[index + 1]] = [reordered[index + 1], reordered[index]];
        state.widgets = reordered;
        renderDashboard();
      }
      postMessage('widgetAction', { action, id });
      return;
    default:
      return;
  }
}

window.WidgetDashboard = {
  receiveCommand(command, payload) {
    try {
      switch (command) {
        case 'bootstrapDashboard':
        case 'setDashboardState':
          applyDashboardState(payload);
          break;
        case 'refreshWidget': {
          const manifest = state.widgets.find((widget) => widget.id === payload.id);
          if (!manifest) return;
          refreshWidgetCard(manifest);
          break;
        }
        default:
          break;
      }
    } catch (error) {
      postMessage('runtimeError', { message: error.message || String(error) });
    }
  },
};

dashboard.addEventListener('click', (event) => {
  const actionButton = event.target.closest('[data-widget-action]');
  if (actionButton) {
    event.preventDefault();
    event.stopPropagation();
    const card = actionButton.closest('.widget-card');
    const id = card?.dataset.widgetId;
    const action = actionButton.dataset.widgetAction;
    if (id && action) {
      handleWidgetAction(action, id);
    }
    return;
  }

  const link = event.target.closest('a[href]');
  if (!link) return;

  event.preventDefault();
  const card = event.target.closest('.widget-card');
  const id = card?.dataset.widgetId;
  if (!id) return;
  postMessage('widgetAction', {
    action: 'openLink',
    id,
    url: link.href,
  });
});

new ResizeObserver(() => notifyHeight()).observe(document.body);
window.addEventListener('load', () => notifyHeight());
postMessage('ready', {});
