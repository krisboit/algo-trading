# Dashboard (DEPRECATED)

> **This dashboard is deprecated and no longer maintained.**
> It has been replaced by the new Firebase Management UI at `platform/ui/`.

This was the original local-only trading dashboard built with React + Vite. It provided basic charting and trade visualization but lacked strategy management, optimization job queuing, and multi-worker support.

## Replacement

The new platform at `platform/ui/` provides:
- Strategy version management with deployment tracking
- Batch optimization job creation wizard
- Job queue with status monitoring
- Optimization results viewer with sortable pass tables
- Multi-worker management with symbol mapping configuration
- Firebase-backed authentication and real-time data

## Why is this still here?

This directory is kept for historical reference only. It is not part of the npm workspaces and will not be built or deployed.
