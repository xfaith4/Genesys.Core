/* Generic profile filtering/statistics; collection and domain profiling belong to Ops. */
(function (root) {
  'use strict';
  const values = value => Array.isArray(value) ? value : [value];
  const present = value => value !== null && value !== undefined && value !== '' && (!Array.isArray(value) || value.length > 0);
  const numeric = value => typeof value === 'number' && Number.isFinite(value);
  const text = value => String(value ?? '').toLocaleLowerCase();
  let searchIndex = new WeakMap();
  function validateBundle(bundle) {
    if (!bundle || bundle.kind !== 'genesys-conversation-analysis' || bundle.schemaVersion !== 1 || !Array.isArray(bundle.profiles) || !bundle.coverage || !bundle.definitions || !Array.isArray(bundle.definitions.numericFields)) throw new Error('Select a version 1 Genesys.Ops conversation analysis JSON file.');
    const ids = new Set();
    for (const row of bundle.profiles) {
      if (!row || typeof row.ConversationId !== 'string' || !row.ConversationId.trim() || ids.has(row.ConversationId)) throw new Error('Profiles must have unique, non-empty conversation IDs.');
      ids.add(row.ConversationId);
    }
    searchIndex = new WeakMap();
    return bundle;
  }
  function matches(row, filter) {
    const value = row[filter.field];
    if (filter.operator === 'exists') return present(value);
    if (filter.operator === 'missing') return !present(value);
    if (!present(value)) return false;
    return values(value).some(item => {
      if (filter.operator === 'contains') return text(item).includes(text(filter.value));
      if (filter.operator === 'equals') return text(item) === text(filter.value);
      if (!numeric(item) || String(filter.value).trim() === '') return false;
      const limit = Number(filter.value);
      if (!Number.isFinite(limit)) return false;
      if (filter.operator === 'lt') return item < limit;
      if (filter.operator === 'lte') return item <= limit;
      if (filter.operator === 'gt') return item > limit;
      if (filter.operator === 'gte') return item >= limit;
      return false;
    });
  }
  function filterProfiles(rows, filters = [], search = '') {
    const needle = text(search).trim();
    return rows.filter(row => {
      if (!filters.every(filter => matches(row, filter))) return false;
      if (!needle) return true;
      let index = searchIndex.get(row);
      if (index === undefined) {
        index = Object.entries(row).filter(([key]) => !['Sessions','ErrorEvents','Timeline','EndpointStats'].includes(key)).map(([,value]) => text(value)).join('\u0000');
        searchIndex.set(row, index);
      }
      return index.includes(needle);
    });
  }
  function stats(rows, field) {
    let count = 0, sum = 0, min = Infinity, max = -Infinity;
    for (const row of rows) if (numeric(row[field])) { const value = row[field]; count++; sum += value; min = Math.min(min, value); max = Math.max(max, value); }
    return { conversations: rows.length, validCount: count, missingCount: rows.length - count, average: count ? sum / count : null, min: count ? min : null, max: count ? max : null, sum: count ? sum : null };
  }
  function groupStats(rows, field, metric) {
    const groups = new Map();
    for (const row of rows) {
      const keys = !field ? ['All conversations'] : present(row[field]) ? new Set(values(row[field]).map(String)) : ['<missing>'];
      for (const key of keys) {
        let group = groups.get(key);
        if (!group) { group = { group: key, conversations: 0, validCount: 0, missingCount: 0, sum: 0, min: Infinity, max: -Infinity }; groups.set(key, group); }
        group.conversations++;
        const value = row[metric];
        if (numeric(value)) { group.validCount++; group.sum += value; group.min = Math.min(group.min,value); group.max = Math.max(group.max,value); }
        else group.missingCount++;
      }
    }
    return [...groups.values()].map(group => ({ ...group, average: group.validCount ? group.sum / group.validCount : null, min: group.validCount ? group.min : null, max: group.validCount ? group.max : null, sum: group.validCount ? group.sum : null })).sort((a,b) => b.conversations-a.conversations || a.group.localeCompare(b.group));
  }

  function errorStats(rows) {
    const groups = new Map();
    for (const row of rows) {
      for (const event of row.ErrorEvents ?? []) {
        const code = String(event.Code ?? '');
        if (!code) continue;
        if (!groups.has(code)) groups.set(code, { code, occurrences: 0, ids: new Set() });
        const group = groups.get(code); group.occurrences++; group.ids.add(row.ConversationId);
      }
    }
    return [...groups.values()].map(group => ({ code: group.code, occurrences: group.occurrences, conversations: group.ids.size })).sort((a, b) => b.conversations - a.conversations || a.code.localeCompare(b.code));
  }
  function csv(rows, columns) {
    const cell = value => {
      if (Array.isArray(value)) value = value.join(' | ');
      else if (value && typeof value === 'object') value = JSON.stringify(value);
      if (typeof value === 'string' && /^[=+\-@\t\r]/.test(value)) value = "'" + value;
      return '"' + String(value ?? '').replaceAll('"', '""') + '"';
    };
    return '\uFEFF' + [columns.map(cell).join(','), ...rows.map(row => columns.map(column => cell(row[column])).join(','))].join('\r\n');
  }
  root.GcPopulation = { validateBundle, filterProfiles, stats, groupStats, errorStats, csv };
})(globalThis);
