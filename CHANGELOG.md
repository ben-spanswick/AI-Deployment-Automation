# Changelog

All notable changes to the AI Box project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2025-06-04

### 🎯 Major Codebase Consolidation Release

This release represents a complete codebase consolidation and production hardening effort, transforming the project from a development workspace into a clean, maintainable, production-ready platform.

### ✨ Added
- **New directory structure** with logical organization
  - `src/` - Core application code
  - `docs/` - Technical documentation
  - `examples/` - API documentation and examples
  - `resources/` - Assets and screenshots
- **Comprehensive `.gitignore`** with production-ready exclusions
- **Production-ready documentation** structure
- **Info-focused dashboard UI** with service documentation modals
- **Service-specific guides** for model management and API usage

### 🔄 Changed
- **Reorganized file structure** for better maintainability
- **Updated all file references** to match new structure
- **Improved documentation** with clear separation of concerns
- **Enhanced dashboard interface** - replaced control buttons with informative help system
- **Streamlined configuration** with clean config directory

### 🗑️ Removed
- **Large CUDA package** (3GB) - now downloaded during setup
- **30+ redundant files** including:
  - Multiple dashboard versions (`dashboard-v2.py`, `dashboard-backend.py`, etc.)
  - Temporary fix scripts (`fix-*.sh`, `*-patch.sh`)
  - Development artifacts (`session-summary.md`, working configs)
  - Backup files (`setup.sh.bak`, etc.)
  - Duplicate compose files (`docker-compose-fixed.yml`, etc.)
- **Debug and temporary scripts** no longer needed for production
- **Hidden state files** from config directory

### 🏗️ File Structure Changes
```
Before: 80+ files, 5.9GB (including 3GB CUDA package)
After:  52 files, ~100MB clean codebase

New Structure:
├── src/           # Core applications
├── docs/          # Technical documentation  
├── examples/      # API docs and examples
├── resources/     # Screenshots and assets
├── scripts/       # Essential utility scripts
├── config/        # Clean configuration files
└── ansible/       # Deployment automation
```

### 🔒 Production Hardening
- **Removed all debug artifacts** and temporary files
- **Cleaned up logging** and removed development print statements
- **Standardized configuration** management
- **Improved error handling** throughout codebase
- **Enhanced security** with proper input validation

### 📊 Impact
- **Repository size reduced** from 5.9GB to ~100MB (98% reduction)
- **File count reduced** by ~35% (better maintainability)
- **Clear separation** of development vs production code
- **Improved documentation** structure and accessibility
- **Enhanced user experience** with informative dashboard

### 🔗 Migration Notes
If you're upgrading from a previous version:
1. Dashboard Dockerfile moved: `dashboard-final.Dockerfile` → `src/dashboard.Dockerfile`
2. Documentation moved: `details.md` → `docs/technical-details.md`
3. API docs moved: `chromadb-info.html` → `examples/api-docs/chromadb-info.html`
4. Screenshots moved: `dashboard.png` → `resources/dashboard-screenshot.png`
5. Core apps moved: `dashboard-unified.py` → `src/dashboard-unified.py`

---

## [2.0.0] - 2025-06-03

### 🚀 Complete Platform Rewrite

Major refactoring and feature enhancement release.

### Added
- Modern web dashboard with real-time GPU monitoring
- Unified service management interface
- GPU metrics server with live telemetry
- Security improvements with command injection protection
- Performance optimizations reducing API calls by 66%
- Network-agnostic design with dynamic IP configuration
- Comprehensive service documentation

### Changed
- Complete dashboard rewrite with modern UI
- Enhanced GPU monitoring capabilities
- Improved Docker containerization
- Better error handling and logging

---

## [1.0.0] - 2025-06-02

### 🎉 Initial Release

First stable release of AI Box platform.

### Added
- Basic AI service deployment
- Docker Compose configuration
- Initial setup scripts
- Basic dashboard functionality
- GPU acceleration support