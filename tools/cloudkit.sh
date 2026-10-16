#!/bin/bash
# CloudKit setup for Brownie's meditation store. Runs on a Mac with Xcode.
#
#   tools/cloudkit.sh login         save a management token (for the schema) and a user token (for records)
#   tools/cloudkit.sh schema        import cloudkit/schema.ckdb into the Development environment
#   tools/cloudkit.sh export        print the Production schema, to compare after deploying
#   tools/cloudkit.sh feature LINK  make a store meditation a starter (a med.nxhx.org link or a record id)
#
# Deploying the schema to Production is a button in CloudKit Console; Apple has no command for it.
set -euo pipefail

TEAM_ID="B7P78ULCXS"
CONTAINER="iCloud.com.joeedelman.meditations"
ENVIRONMENT="${CK_ENVIRONMENT:-production}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-}" in
    login)
        xcrun cktool save-token --type management
        xcrun cktool save-token --type user
        ;;
    schema)
        xcrun cktool import-schema \
            --team-id "$TEAM_ID" \
            --container-id "$CONTAINER" \
            --environment development \
            --file "$ROOT/cloudkit/schema.ckdb"
        echo "Imported into Development. Deploy it to Production in CloudKit Console."
        ;;
    export)
        xcrun cktool export-schema \
            --team-id "$TEAM_ID" \
            --container-id "$CONTAINER" \
            --environment production
        ;;
    feature)
        id="${2:?usage: tools/cloudkit.sh feature <med.nxhx.org link or record id>}"
        id="${id%/}"
        id="${id##*/}"
        id="${id%.med}"
        xcrun cktool create-record \
            --team-id "$TEAM_ID" \
            --container-id "$CONTAINER" \
            --zone-name _defaultZone \
            --database-type public \
            --environment "$ENVIRONMENT" \
            --record-type Featured \
            --fields-json "{\"meditationID\": {\"type\": \"stringType\", \"value\": \"$id\"}}"
        echo "Featured $id in $ENVIRONMENT."
        ;;
    *)
        sed -n '2,10p' "$0"
        exit 1
        ;;
esac
