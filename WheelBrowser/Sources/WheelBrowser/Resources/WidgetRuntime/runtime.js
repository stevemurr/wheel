const dashboard = document.getElementById('dashboard');

const state = {
  widgets: [],
  isEditing: false,
  cache: new Map(),
  inFlight: new Map(),
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

const ACTION_ICONS = {
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

function formatValue(value, prefix = '', suffix = '') {
  if (value == null) return '—';
  return `${prefix}${value}${suffix}`;
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
  const width = 600;
  const height = 220;
  const padding = 28;
  const max = Math.max(...data.map((item) => Number(item?.[config.yField] ?? 0)), 1);
  const barWidth = (width - padding * 2) / Math.max(data.length, 1);
  const color = config.color || '#0d8f73';

  const bars = data.map((item, index) => {
    const value = Number(item?.[config.yField] ?? 0);
    const barHeight = ((height - padding * 2) * value) / max;
    const x = padding + index * barWidth + 8;
    const y = height - padding - barHeight;
    return `<rect class="chart-bar" x="${x}" y="${y}" width="${Math.max(barWidth - 16, 12)}" height="${barHeight}" fill="${escapeAttribute(color)}"></rect>`;
  }).join('');

  return `
    <div class="chart-wrap">
      <svg class="chart-svg" viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeAttribute(config.title)}">
        <line class="chart-axis" x1="${padding}" y1="${height - padding}" x2="${width - padding}" y2="${height - padding}"></line>
        <line class="chart-axis" x1="${padding}" y1="${padding}" x2="${padding}" y2="${height - padding}"></line>
        ${bars}
      </svg>
    </div>
  `;
}

function renderLineChart(config, data) {
  const width = 600;
  const height = 220;
  const padding = 28;
  const allValues = config.series
    .flatMap((series) => data.map((item) => Number(item?.[series.field] ?? 0)))
    .filter((value) => Number.isFinite(value));
  const max = Math.max(...allValues, 1);
  const xStep = data.length > 1 ? (width - padding * 2) / (data.length - 1) : 0;

  const paths = config.series.map((series, seriesIndex) => {
    const color = series.color || ['#0d8f73', '#c18550', '#4259b2'][seriesIndex % 3];
    const coordinates = data.map((item, index) => {
      const value = Number(item?.[series.field] ?? 0);
      const x = padding + index * xStep;
      const y = height - padding - ((height - padding * 2) * value) / max;
      return { x, y };
    });
    const path = coordinates.map((point, index) => `${index === 0 ? 'M' : 'L'} ${point.x} ${point.y}`).join(' ');
    const dots = (config.showPoints ? coordinates.map((point) => `<circle class="chart-point" cx="${point.x}" cy="${point.y}" r="4" fill="${escapeAttribute(color)}"></circle>`).join('') : '');
    return `<path class="chart-line" d="${path}" stroke="${escapeAttribute(color)}"></path>${dots}`;
  }).join('');

  return `
    <div class="chart-wrap">
      <svg class="chart-svg" viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeAttribute(config.title)}">
        <line class="chart-axis" x1="${padding}" y1="${height - padding}" x2="${width - padding}" y2="${height - padding}"></line>
        <line class="chart-axis" x1="${padding}" y1="${padding}" x2="${padding}" y2="${height - padding}"></line>
        ${paths}
      </svg>
    </div>
  `;
}

function renderWidgetContent(manifest, data) {
  switch (manifest.widgetType) {
    case 'statCard': {
      const config = manifest.config;
      const value = data?.[config.valueField];
      const delta = config.changeField ? data?.[config.changeField] : null;
      return `
        <div class="stat-block">
          <div class="stat-value">${escapeHTML(formatValue(value, config.prefix || '', config.suffix || ''))}</div>
          ${delta != null ? `<div class="stat-delta">${escapeHTML(config.changeIsPercent ? `${delta}%` : delta)}</div>` : ''}
        </div>
      `;
    }
    case 'priceCard': {
      const config = manifest.config;
      const deltaField = config.changePercentField || config.changeField;
      return `
        <div class="stat-block">
          <div class="price-value">${escapeHTML(formatValue(data?.[config.priceField], config.prefix || ''))}</div>
          ${deltaField ? `<div class="price-delta">${escapeHTML(data?.[deltaField] ?? '—')}</div>` : ''}
          ${config.footnote ? `<div class="footnote">${escapeHTML(config.footnote)}</div>` : ''}
        </div>
      `;
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
      return config.markdown
        ? `<div class="markdown">${renderMarkdown(content)}</div>`
        : `<div class="text-block">${escapeHTML(content)}</div>`;
    }
    case 'barChart':
      return renderBarChart(manifest.config, Array.isArray(data) ? data : []);
    case 'lineChart':
      return renderLineChart(manifest.config, Array.isArray(data) ? data : []);
    default:
      return `<div class="text-block">${JSON.stringify(data)}</div>`;
  }
}

function renderCard(manifest) {
  const card = document.createElement('section');
  card.className = 'widget-card is-loading';
  card.dataset.widgetId = manifest.id;

  const header = document.createElement('header');
  header.className = 'widget-header';
  const title = document.createElement('h2');
  title.className = 'widget-title';
  title.textContent = manifest.config.title || manifest.prompt;

  const actions = document.createElement('div');
  actions.className = 'widget-actions';
  actions.appendChild(createIconButton({ label: 'Refresh', action: 'refresh' }));

  if (state.isEditing) {
    actions.appendChild(createIconButton({ label: 'Move Up', action: 'moveUp' }));
    actions.appendChild(createIconButton({ label: 'Move Down', action: 'moveDown' }));
    actions.appendChild(createIconButton({ label: 'Remove', action: 'remove', extraClass: 'danger' }));
  }

  header.appendChild(title);
  header.appendChild(actions);

  const content = document.createElement('div');
  content.className = 'widget-content';
  content.innerHTML = '<div class="skeleton"></div>';

  card.appendChild(header);
  card.appendChild(content);

  executeSkillChain(manifest)
    .then((data) => {
      card.classList.remove('is-loading');
      content.innerHTML = renderWidgetContent(manifest, data);
      postMessage('widgetLoaded', { id: manifest.id });
      notifyHeight();
    })
    .catch((error) => {
      card.classList.remove('is-loading');
      content.innerHTML = `<div class="widget-error">${escapeHTML(error.message || String(error))}</div>`;
      postMessage('widgetError', { id: manifest.id, message: error.message || String(error) });
      notifyHeight();
    });

  return card;
}

function renderDashboard() {
  dashboard.innerHTML = '';
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

  for (const manifest of state.widgets) {
    dashboard.appendChild(renderCard(manifest));
  }
  notifyHeight();
}

function applyDashboardState(payload) {
  state.widgets = payload.widgets || [];
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
      if (refreshed) refreshed.innerHTML = renderWidgetContent(manifest, data);
      card?.classList.remove('is-loading');
      postMessage('widgetLoaded', { id: manifest.id });
      notifyHeight();
    })
    .catch((error) => {
      const refreshed = dashboard.querySelector(`[data-widget-id="${manifest.id}"] .widget-content`);
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
    case 'remove':
      state.widgets = state.widgets.filter((widget) => widget.id !== id);
      renderDashboard();
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
