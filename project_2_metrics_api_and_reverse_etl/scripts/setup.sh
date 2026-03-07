#!/bin/bash
# Setup script for Project 2
# One-command project env setup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Project 2: Metrics Service + Reverse ETL"
echo "Setup Script"
echo "=========================================="
echo ""

# Check Python
echo "Step 1: Check Python..."
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 not installed"
    exit 1
fi

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
echo "  Python: $PYTHON_VERSION"
echo ""

# Check required commands
echo "Step 2: Check required commands..."
MISSING_CMDS=()

for cmd in dbt trino curl; do
    if ! command -v $cmd &> /dev/null; then
        MISSING_CMDS+=($cmd)
    else
        echo "  [OK] $cmd installed"
    fi
done

if [ ${#MISSING_CMDS[@]} -gt 0 ]; then
    echo "  WARNING: Missing: ${MISSING_CMDS[*]}"
    echo "  Some features may be unavailable"
fi
echo ""

# Create .env
echo "Step 3: Create .env..."
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    if [ -f "$PROJECT_ROOT/.env.example" ]; then
        cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
        echo "  [OK] Created .env from .env.example"
        echo "  Edit .env to set env vars"
    else
        echo "  WARNING: .env.example missing, skipping"
    fi
else
    echo "  [OK] .env exists, skipping"
fi
echo ""

# Install Python deps
echo "Step 4: Install Python deps..."

if [ -f "$PROJECT_ROOT/services/metrics_api/requirements.txt" ]; then
    echo "  Installing Metrics API deps..."
    pip3 install -q -r "$PROJECT_ROOT/services/metrics_api/requirements.txt" || {
        echo "  WARNING: Metrics API deps failed"
    }
fi

if [ -f "$PROJECT_ROOT/reverse_etl/requirements.txt" ]; then
    echo "  Installing Reverse ETL deps..."
    pip3 install -q -r "$PROJECT_ROOT/reverse_etl/requirements.txt" || {
        echo "  WARNING: Reverse ETL deps failed"
    }
fi

echo "  [OK] Python deps done"
echo ""

# dbt deps
echo "Step 5: Install dbt deps..."
if command -v dbt &> /dev/null; then
    cd "$PROJECT_ROOT/analytics/dbt"
    if [ -f "packages.yml" ]; then
        dbt deps --profiles-dir . --project-dir . || {
            echo "  WARNING: dbt deps failed"
        }
        echo "  [OK] dbt deps done"
    else
        echo "  WARNING: packages.yml missing"
    fi
    cd "$PROJECT_ROOT"
else
    echo "  WARNING: dbt not installed, skipping"
fi
echo ""

# Create dirs
echo "Step 6: Create directories..."
mkdir -p "$PROJECT_ROOT/evidence/demos"
mkdir -p "$PROJECT_ROOT/evidence/recon"
mkdir -p "$PROJECT_ROOT/evidence/releases"
mkdir -p "$PROJECT_ROOT/evidence/slo"
mkdir -p "$PROJECT_ROOT/evidence/validation"
mkdir -p "$PROJECT_ROOT/recon"
echo "  [OK] Directories created"
echo ""

# Check Project 1 Gold tables
echo "Step 7: Check Project 1 Gold tables..."
if command -v trino &> /dev/null; then
    echo "  Connecting to Trino to check tables..."
    TRINO_HOST="${TRINO_HOST:-localhost}"
    TRINO_PORT="${TRINO_PORT:-8080}"
    TRINO_USER="${TRINO_USER:-admin}"
    
    trino --server ${TRINO_HOST}:${TRINO_PORT} --user ${TRINO_USER} \
        --catalog iceberg --schema mart \
        --execute "SHOW TABLES" 2>/dev/null | grep -q "mart_kpis_daily" && {
        echo "  [OK] Project 1 Gold tables exist"
    } || {
        echo "  WARNING: Cannot reach Trino or Project 1 Gold tables missing"
        echo "  Ensure Project 1 is running and Gold layer exists"
    }
else
    echo "  WARNING: trino not installed, skipping table check"
fi
echo ""

echo "=========================================="
echo "Setup complete!"
echo "=========================================="
echo ""
echo "Next:"
echo "1. Edit .env with your config"
echo "2. Ensure Project 1 Gold tables exist"
echo "3. Run dbt: cd analytics/dbt && dbt run"
echo "4. Start API: make api-start"
echo "5. Run demo: ./scripts/demo_metric_release.sh"
echo ""
echo "See README.md for more."
