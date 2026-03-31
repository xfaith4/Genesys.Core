# Genesys Best Practices Starter Package

This package is the first-pass implementation of a **Genesys Cloud Best Practices reference system**.

## Files

- `BestPractices.md`
- `best-practices.catalog.json`
- `best-practices.schema.json`
- `best-practices-map.json`

## Intended usage

### Human usage
Use `BestPractices.md` as the canonical readable guide for operators, engineers, and audit/report consumers.

### Application usage
Use `best-practices.catalog.json` as the lookup table for:

- finding enrichment
- glossary definitions
- report recommendations
- UI drill-down content
- filter/search by domain, severity, and tags

### Validation usage
Use `best-practices.schema.json` to validate future additions to the catalog.

### Mapping usage
Use `best-practices-map.json` to connect your analyzer result types to relevant best-practice keys.

## Suggested repo placement

```text
/docs/BestPractices.md
/reference/best-practices.catalog.json
/reference/best-practices.schema.json
/reference/best-practices-map.json
```

## Recommended future enhancements

1. Add `evidence_examples`
2. Add `recommended_action_short`
3. Add `recommended_action_detailed`
4. Add `owner_role`
5. Add `control_family`
6. Add `detection_strategy`
7. Add `false_positive_notes`
8. Add `last_reviewed`
