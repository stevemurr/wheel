// Widget transform runtime — pure JS, no dependencies.
// Implements sort, filter, map_fields, and aggregate skills.

function widgetTransform(skill, params, input) {
    if (!Array.isArray(input)) return input;

    switch (skill) {
        case "sort":
            return transformSort(params, input);
        case "filter":
            return transformFilter(params, input);
        case "map_fields":
            return transformMapFields(params, input);
        case "aggregate":
            return transformAggregate(params, input);
        default:
            throw new Error("Unknown transform skill: " + skill);
    }
}

function transformSort(params, input) {
    var field = params.field;
    var order = params.order || "desc";
    if (!field) throw new Error("sort requires 'field' parameter");

    var copy = input.slice();
    copy.sort(function(a, b) {
        var va = a[field], vb = b[field];
        if (va == null && vb == null) return 0;
        if (va == null) return 1;
        if (vb == null) return -1;
        if (typeof va === "string") {
            va = va.toLowerCase();
            vb = (vb || "").toString().toLowerCase();
        }
        if (va < vb) return order === "asc" ? -1 : 1;
        if (va > vb) return order === "asc" ? 1 : -1;
        return 0;
    });
    return copy;
}

function transformFilter(params, input) {
    var field = params.field;
    var op = params.operator;
    var value = params.value;
    if (!field || !op) throw new Error("filter requires 'field' and 'operator' parameters");

    return input.filter(function(item) {
        var v = item[field];
        switch (op) {
            case "eq": return v === value;
            case "neq": return v !== value;
            case "gt": return typeof v === "number" && v > value;
            case "gte": return typeof v === "number" && v >= value;
            case "lt": return typeof v === "number" && v < value;
            case "lte": return typeof v === "number" && v <= value;
            case "contains":
                return typeof v === "string" && v.toLowerCase().indexOf(String(value).toLowerCase()) !== -1;
            case "not_contains":
                return typeof v === "string" && v.toLowerCase().indexOf(String(value).toLowerCase()) === -1;
            default:
                throw new Error("Unknown filter operator: " + op);
        }
    });
}

function transformMapFields(params, input) {
    var mapping = params.mapping;
    if (!mapping || typeof mapping !== "object") throw new Error("map_fields requires 'mapping' parameter");

    return input.map(function(item) {
        var result = {};
        var keys = Object.keys(mapping);
        for (var i = 0; i < keys.length; i++) {
            var outputKey = keys[i];
            var template = mapping[outputKey];
            if (typeof template === "string" && template.indexOf("{{") !== -1) {
                result[outputKey] = template.replace(/\{\{(\w+)\}\}/g, function(_, field) {
                    var val = item[field];
                    return val != null ? String(val) : "";
                });
            } else if (typeof template === "string" && item[template] !== undefined) {
                result[outputKey] = item[template];
            } else {
                result[outputKey] = template;
            }
        }
        return result;
    });
}

function transformAggregate(params, input) {
    var operation = params.operation;
    var field = params.field;
    var groupBy = params.group_by;
    if (!operation) throw new Error("aggregate requires 'operation' parameter");

    if (groupBy) {
        var groups = {};
        for (var i = 0; i < input.length; i++) {
            var key = String(input[i][groupBy] || "null");
            if (!groups[key]) groups[key] = [];
            groups[key].push(input[i]);
        }
        var result = [];
        var groupKeys = Object.keys(groups);
        for (var g = 0; g < groupKeys.length; g++) {
            var entry = {};
            entry[groupBy] = groupKeys[g];
            entry["value"] = computeAggregate(operation, field, groups[groupKeys[g]]);
            result.push(entry);
        }
        return result;
    }

    return [{ "value": computeAggregate(operation, field, input) }];
}

function computeAggregate(operation, field, items) {
    switch (operation) {
        case "count":
            return items.length;
        case "sum":
            return items.reduce(function(s, i) { return s + (Number(i[field]) || 0); }, 0);
        case "avg":
            if (items.length === 0) return 0;
            var sum = items.reduce(function(s, i) { return s + (Number(i[field]) || 0); }, 0);
            return sum / items.length;
        case "min":
            return items.reduce(function(m, i) {
                var v = i[field]; return (m === null || v < m) ? v : m;
            }, null);
        case "max":
            return items.reduce(function(m, i) {
                var v = i[field]; return (m === null || v > m) ? v : m;
            }, null);
        case "first":
            return items.length > 0 ? items[0][field] : null;
        case "last":
            return items.length > 0 ? items[items.length - 1][field] : null;
        default:
            throw new Error("Unknown aggregate operation: " + operation);
    }
}
