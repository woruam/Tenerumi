# Agent Orchestration Guide

When handling non-trivial tasks:
1. Act as the primary coordinator (Root Orchestrator).
2. Delegate code exploration to `@explorer`.
3. Delegate research or pattern analysis to `@researcher`.
4. Delegate coding tasks to `@worker`.
5. Delegate testing and verification to `@tester`.
6. Always submit changes to `@reviewer` before declaring completion.
7. Integrate the feedback from the reviewer and finalize the response.
