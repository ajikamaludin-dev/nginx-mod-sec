# Migration Notes (nginx-mod-sec) — Detail

## Sources (verify)
- CRS v4.25.2 setup example: https://raw.githubusercontent.com/coreruleset/coreruleset/v4.25.2/crs-setup.conf.example
- ModSecurity v3.0.14 recommended: https://raw.githubusercontent.com/owasp-modsecurity/ModSecurity/v3.0.14/modsecurity.conf-recommended
- CRS releases: https://github.com/coreruleset/coreruleset/releases

## Image changes
- TLS verification re-enabled.
- OWASP CRS v3.3 -> v4.25.2 (tag).
- Pin ModSecurity/connector/quiche to release tags before prod.

## Config diff (copy-paste)

### 1. crs-setup.conf version variable
Old (v3):
```
SecAction "id:900990,phase:1,nolog,pass,t:none,setvar:tx.crs_setup_version=337"
```
New (v4):
```
SecAction "id:900990,phase:1,nolog,pass,t:none,setvar:tx.crs_setup_version=4252"
```

### 2. Default action (unchanged)
```
SecDefaultAction "phase:1,log,auditlog,pass"
SecDefaultAction "phase:2,log,auditlog,pass"
```

### 3. Custom settings (still valid in v4)
- `tx.allowed_methods` (id 900200)
- `tx.allowed_http_versions` (id 900230) — ensure HTTP/3 added if needed
- `SecCollectionTimeout 600`

### 4. New in v4
- Review new variables in v4 example (paranoia level, anomaly thresholds).
- Some rule IDs renamed; exclusion files may need updates.

## Production impact
Paths unchanged:
- `./nginx/modsec/modsecurity.conf`
- `./nginx/modsec-rule/crs-setup.conf`
- `./nginx/conf.d`

## Manual migration checklist
1. Backup `./nginx/modsec/` and `./nginx/modsec-rule/`.
2. Update version variable to 4310.
3. Diff full crs-setup.conf.example vs current; apply new sections.
4. Test with `SecRuleEngine DetectionOnly`, then `On`.
5. Rebuild image, update compose `image:` tag.

## Rollback
Keep old image tag; revert compose if false positives spike.
