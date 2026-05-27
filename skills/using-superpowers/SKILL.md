---
name: using-superpowers
description: Use when the user explicitly asks to manually activate the Superpowers workflow, enable Superpowers for this session, or run the Superpowers methodology on demand.
disable-model-invocation: true
---

# Using Superpowers

Activate the Superpowers workflow only because the user explicitly invoked this skill.

## Step 1: Load Bootstrap

Read `~/.pi/agent/git/github.com/adtrac/superpowers/skills/using-superpowers/SKILL.md`.

## Step 2: Apply Session Rules

Follow the loaded `using-superpowers` instructions for the current session.

If the user says to stop Superpowers, stop following the loaded workflow and return to normal Pi project instructions.

## Step 3: Report Activation

Reply briefly:

```text
Superpowers active for this session.
```
