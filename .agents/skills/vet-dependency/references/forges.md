# Per-forge API calls

Steps 1 through 3 read four signals off whatever host the repository lives on: maintainer-authored commit history, the open pull request queue, the fork census, and a file at a tag. Every forge exposes all four; only the paths and the auth requirements differ.

## Contents

- Endpoint map
- GitHub
- GitLab
- Gitea and Forgejo
- Auth and rate limits
- Code search caveats
- A repository on no forge at all
- Verification status

## Endpoint map

`PROJ` is `OWNER%2FREPO` on GitLab (URL-encoded) and `OWNER/REPO` elsewhere.

| Signal | GitHub | GitLab | Gitea / Forgejo |
|---|---|---|---|
| Repository metadata | `repos/OWNER/REPO` | `projects/PROJ` | `repos/OWNER/REPO` |
| Commit history | `repos/OWNER/REPO/commits` | `projects/PROJ/repository/commits` | `repos/OWNER/REPO/commits` |
| Open change queue | `repos/OWNER/REPO/pulls?state=open` | `projects/PROJ/merge_requests?state=opened` | `repos/OWNER/REPO/pulls?state=open` |
| Comments on one item | `repos/OWNER/REPO/issues/N/comments` | `projects/PROJ/merge_requests/IID/notes` | `repos/OWNER/REPO/issues/N/comments` |
| Forks | `repos/OWNER/REPO/forks` | `projects/PROJ/forks` | `repos/OWNER/REPO/forks` |
| Raw file at a tag | `raw.githubusercontent.com/OWNER/REPO/TAG/PATH` | `projects/PROJ/repository/files/PATH/raw?ref=TAG` | `HOST/OWNER/REPO/raw/tag/TAG/PATH` |

Field names differ across forges for the same concept. Read the actual keys rather than assuming GitHub's: `pushed_at` is `last_activity_at` on GitLab and `updated_at` on Gitea, and the fork parent is `parent.full_name`, `forked_from_project.path_with_namespace`, and `parent.full_name` respectively.

## GitHub

```bash
gh api repos/OWNER/REPO \
  --jq '{stars: .stargazers_count, pushed: .pushed_at, created: .created_at, archived, fork: .fork, parent: .parent.full_name}'
gh api repos/OWNER/REPO/commits --jq '.[] | {date: .commit.author.date, author: .author.login}' | head -20
gh api 'repos/OWNER/REPO/pulls?state=open&per_page=100' \
  --jq '.[] | {num: .number, title, created: .created_at, updated: .updated_at, author: .user.login}'
gh api 'repos/OWNER/REPO/issues/NUMBER/comments' --jq '.[] | {user: .user.login, created: .created_at}'
gh api 'repos/OWNER/REPO/forks?sort=stargazers&per_page=100' \
  --jq '.[] | select(.stargazers_count > 0) | {full_name, stars: .stargazers_count, pushed: .pushed_at}'
```

Without `gh`, the same paths work under `https://api.github.com/` with `curl`, unauthenticated, at a much lower rate limit.

## GitLab

```bash
P="gitlab-org%2Fgitlab-runner"
curl -sS "https://gitlab.com/api/v4/projects/$P" \
  | jq -c '{id, path: .path_with_namespace, forked_from: .forked_from_project.path_with_namespace, last_activity_at}'
curl -sS "https://gitlab.com/api/v4/projects/$P/merge_requests?state=opened&per_page=100" \
  | jq -c '.[] | {iid, created_at, updated_at, notes: .user_notes_count, author: .author.username}'
curl -sS -o file "https://gitlab.com/api/v4/projects/$P/repository/files/go.mod/raw?ref=v16.0.0"
```

**The project path must be URL-encoded**, or substitute the numeric project id, which the metadata call returns.

**Merge request notes require a token; the merge request list does not.** `projects/PROJ/merge_requests/IID/notes` answers `{"message":"401 Unauthorized"}` for a public project without credentials. Without a token, use `user_notes_count` from the list response as the proxy: zero means nobody has replied at all, which is the case step 2 cares most about. With a token, read the notes and skip `system: true` entries, which are state changes rather than replies.

**A self-hosted GitLab uses the same `/api/v4` paths** under its own host. Only the base URL changes.

## Gitea and Forgejo

```bash
curl -sS "https://codeberg.org/api/v1/repos/OWNER/REPO" \
  | jq -c '{full_name, fork, parent: .parent.full_name, updated_at, stars: .stars_count}'
curl -sS "https://codeberg.org/api/v1/repos/OWNER/REPO/pulls?state=open&limit=50" \
  | jq -c '.[] | {number, created_at, user: .user.login}'
curl -sS "https://codeberg.org/api/v1/repos/OWNER/REPO/issues/NUMBER/comments?limit=50" \
  | jq -c '.[] | {user: .user.login, created_at}'
```

Paging uses `limit`, not `per_page`. Pull requests and issues share one number sequence, so the comments endpoint takes the pull request's number under `/issues/`.

## Auth and rate limits

| Host | Unauthenticated reads | Verified exception |
|---|---|---|
| GitHub | Metadata, commits, pulls, forks, comments all readable | Rate limit is low enough that a five-candidate census will hit it; authenticate |
| GitLab | Project, merge request list, forks, raw file all readable | Merge request notes return 401 |
| Gitea / Forgejo | Repo, pulls, comments all readable | Instance operators can disable the API entirely |

An empty response body with exit status 0 is the failure shape to guard against on all three. Check the HTTP status, not whether output appeared.

## Code search caveats

Forge code search answers a different question than the one step 3 and step 4 ask, and it answers it silently.

- It indexes the **default branch only**. A zero says nothing about a tag or a release.
- A **recently created repository may not be indexed at all**, so a zero can mean the repository is not visible to the index rather than absent from it.
- Index coverage differs per forge and per plan, and a self-hosted instance may have no index.

Run a positive control before reading any zero as absence:

```bash
gh api "search/code?q=repo:OWNER/REPO+<a+term+the+repo+must+contain>" --jq '.total_count'
```

When the control also returns zero, change instrument rather than softening the claim: download the tree or the release archive at the tag, grep it locally, and re-run the same control against the local copy.

## A repository on no forge at all

`golang.org/x/*` resolves to `go.googlesource.com`, a Gerrit instance with no pull requests. Mirrors on GitHub exist and are read-only, so their empty queue is an artifact of the mirror, not a maintenance signal.

Where the host has no queue to read, say so in the verdict rather than omitting step 2. Substitute what the host does expose (Gerrit's open changes, a mailing list archive, a bug tracker) and name the substitution, since its latency is not comparable to a pull request queue.

## Verification status

Every GitHub, GitLab, and Gitea command above was executed on 2026-09-02 against `pkg/errors`, `gitlab-org/gitlab-runner`, and `forgejo/forgejo`, and the field names quoted are the ones the responses returned. The GitLab 401 on notes and the HTTP 200 on unauthenticated GitHub comments were both observed, not inferred.
