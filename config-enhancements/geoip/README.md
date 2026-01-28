# GeoIP Enrichment Enhancement

## Overview

This enhancement adds GeoIP enrichment for destination IPs (`data.dstip`) in addition to the default source IP enrichment. This is particularly useful for OPNsense firewall blocks where:
- Source IPs are typically private (10.x.x.x, 192.168.x.x) - cannot be geolocated
- Destination IPs are often public (external servers) - CAN be geolocated

## Files

| File | Purpose |
|------|---------|
| `custom-pipeline.json` | Complete Filebeat ingest pipeline with data.dstip GeoIP processor |
| `README.md` | This documentation |

## What Changed

### 1. GeoIP Processor for Destination IPs

The `custom-pipeline.json` adds this processor after the existing `data.srcip` processor:

```json
{
  "geoip": {
    "field": "data.dstip",
    "target_field": "GeoLocation",
    "properties": ["city_name", "country_name", "region_name", "location"],
    "ignore_missing": true,
    "ignore_failure": true
  }
}
```

### 2. Script Processor for Lat/Lon Extraction and Location Key

The pipeline includes a script processor that:
1. Extracts latitude/longitude from the geo_point into separate fields for Grafana
2. Creates a `location_key` field for aggregation (city-level when available, country fallback)

```json
{
  "script": {
    "description": "Extract lat/lon and create location_key (city or country fallback)",
    "lang": "painless",
    "source": "if (ctx.GeoLocation != null && ctx.GeoLocation.location != null) { ctx.GeoLocation.latitude = ctx.GeoLocation.location.lat; ctx.GeoLocation.longitude = ctx.GeoLocation.location.lon; if (ctx.GeoLocation.city_name != null && ctx.GeoLocation.city_name.length() > 0) { ctx.GeoLocation.location_key = ctx.GeoLocation.city_name + ', ' + ctx.GeoLocation.country_name; } else if (ctx.GeoLocation.country_name != null) { ctx.GeoLocation.location_key = ctx.GeoLocation.country_name; } }",
    "ignore_failure": true
  }
}
```

**Fields created:**
- `GeoLocation.latitude` - Double field for Grafana aggregation
- `GeoLocation.longitude` - Double field for Grafana aggregation
- `GeoLocation.location_key` - "City, Country" or "Country" for map grouping

## Manual Deployment to Current Wazuh Instance

### Step 1: Apply the Pipeline

```bash
# From the phoenix_wazuh project directory
curl -s -k -u <WAZUH_USER>:<WAZUH_PASSWORD> \
  -X PUT "https://10.2.0.86:9200/_ingest/pipeline/filebeat-7.10.2-wazuh-alerts-pipeline" \
  -H "Content-Type: application/json" \
  -d @config-enhancements/geoip/custom-pipeline.json
```

### Step 2: Verify the Pipeline

```bash
curl -s -k -u <WAZUH_USER>:<WAZUH_PASSWORD> \
  "https://10.2.0.86:9200/_ingest/pipeline/filebeat-7.10.2-wazuh-alerts-pipeline?pretty" \
  | grep -A5 "data.dstip"
```

Expected output:
```json
{
  "geoip" : {
    "field" : "data.dstip",
    "target_field" : "GeoLocation",
    ...
  }
}
```

### Step 3: Wait for New Data

GeoIP enrichment happens at index time. Only NEW documents will get GeoLocation data. Wait for new OPNsense blocks to occur.

### Step 4: Verify GeoLocation is Populated

```bash
# Check for recent OPNsense blocks with GeoLocation
curl -s -k -u <WAZUH_USER>:<WAZUH_PASSWORD> \
  "https://10.2.0.86:9200/wazuh-alerts-*/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "size": 5,
    "query": {
      "bool": {
        "must": [
          {"match": {"data.action": "block"}},
          {"exists": {"field": "GeoLocation.location"}}
        ]
      }
    },
    "sort": [{"@timestamp": "desc"}]
  }' | jq '.hits.hits[]._source | {srcip: .data.srcip, dstip: .data.dstip, geo: .GeoLocation}'
```

## Automatic Deployment

To include this in future deployments, the `phoenix-wazuh-orchestrator.sh` needs to be updated to:

1. Copy `custom-pipeline.json` to Unraid during file prep
2. Apply the pipeline via OpenSearch API during post-deployment config

See the full plan at:
`/home/dev/projects/phoenix_automation/ops-dashboard/docs/wazuh-geoip-enrichment-plan.md`

## Notes

- **Private IPs**: Cannot be geolocated (10.x.x.x, 192.168.x.x, 0.0.0.0)
- **Multicast IPs**: Cannot be geolocated (224.x.x.x)
- **MaxMind Database**: Included in Wazuh Indexer container
- **Persistence**: Pipeline survives restarts but resets on fresh deploy
