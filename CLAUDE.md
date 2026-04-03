# CLAUDE.md

## gstack

**Web Browsing**: Use the `/browse` skill from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools.

**Available gstack Skills**:
- `/office-hours` - Check in on team velocity, blockers, and morale
- `/plan-ceo-review` - Product strategy and direction review
- `/plan-eng-review` - Technical architecture and edge case analysis
- `/plan-design-review` - Design system and UX review
- `/design-consultation` - Get design advice and feedback
- `/review` - Deep code review for security, performance, race conditions
- `/ship` - Automated testing, PR creation, deployment workflow
- `/land-and-deploy` - Land changes and deploy to production
- `/canary` - Canary deployment and monitoring
- `/benchmark` - Performance benchmarking
- `/browse` - Headless browser automation for testing and verification
- `/qa` - Automated QA testing with bug fixes
- `/qa-only` - Testing without code changes (report-only mode)
- `/design-review` - Structured design review process
- `/setup-browser-cookies` - Import browser cookies for authenticated testing
- `/setup-deploy` - Setup deployment configuration
- `/retro` - Engineering retrospective with metrics
- `/investigate` - Investigate issues and incidents
- `/document-release` - Document a release
- `/codex` - OpenAI Codex CLI integration for second opinions
- `/cso` - Chief Strategy Officer consultation
- `/careful` - Safety guardrails (warns before destructive commands)
- `/freeze` - Edit lock to restrict changes to one directory
- `/guard` - Full safety mode (combines careful + freeze)
- `/unfreeze` - Remove edit lock
- `/gstack-upgrade` - Upgrade gstack to latest version

**Troubleshooting**: If gstack skills aren't working, run `cd .claude/skills/gstack && ./setup` to build the binary and register skills.
