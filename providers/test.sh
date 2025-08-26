#!/bin/sh
provider_info() {
    echo "name: Test"
    echo "version: 1.0.0"
    echo "type: test"
}

provider_config() {
    echo "field: key, type: string, required: true, description: Test Key"
}

provider_validate() {
    return 0
}

provider_update() {
    echo "[Test] Would update $1 to $3"
    return 0
}
