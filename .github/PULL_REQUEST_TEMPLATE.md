name: Pull Request
description: Submit changes to hermes-alpine
title: "[PR]: "
labels: []
body:
  - type: markdown
    attributes:
      value: |
        Thanks for contributing to hermes-alpine!
  - type: textarea
    id: summary
    attributes:
      label: Summary
      description: What does this PR do?
    validations:
      required: true
  - type: textarea
    id: testing
    attributes:
      label: How was this tested?
      description: Describe the testing you performed
      placeholder: |
        - Ran make verify (all checks pass)
        - Ran setup-ecosystem.sh on Alpine 3.21
        - Tested skill loading with `hermes skills list`
    validations:
      required: true
  - type: checkboxes
    id: checks
    attributes:
      label: Pre-submit checklist
      options:
        - label: README.md or relevant docs are updated
          required: false
        - label: Scripts pass shellcheck or lint
          required: false
        - label: make verify passes with 0 warnings
          required: false
        - label: I've read CONTRIBUTING.md
          required: true
  - type: dropdown
    id: type
    attributes:
      label: Change type
      options:
        - New feature
        - Bug fix
        - Documentation
        - Infrastructure / CI
        - Dependency update
        - Refactor
    validations:
      required: true
