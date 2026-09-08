## Worked example

One tool, one version, as an illustration of the shape above. The technique transfers; the paths do not. Gemini CLI 0.40.x, a bundled-JS agent CLI, read on Linux.

Entering the bundle on the literal `.project_root` reaches a build banner naming the upstream module, whose storage class constructs its registry with a two-element array of roots: the global temp directory and a `history` directory beside it, both under `~/.gemini`. Two roots, not one. A cleanup that sweeps only the temp store leaves a history entry behind on every single invocation, and the entry is found by reading the `.project_root` marker inside each candidate directory, because the CLI lowercases the basename and appends a numeric suffix on collision. The project registry, a single JSON file keyed by path that every concurrent process rewrites, is left in place deliberately per step 3.
