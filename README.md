# Gwok Hiujin's Hugo blog

This repository publishes [gwokhiujin.github.io](https://gwokhiujin.github.io/) with [Hugo](https://gohugo.io/) and the [GwokHiujin/shibui](https://github.com/GwokHiujin/shibui) theme.

## Local development

```sh
git submodule update --init --recursive
hugo server -D
```

The GitHub Actions workflow installs the pinned Hugo version, builds the site, and deploys `public/` to GitHub Pages.

## Content layout

Every post belongs under exactly one of these top-level sections:

```text
content/
├── Apodidae/
├── Oleander/
└── Taoasis/
```

Add a normal post as `content/Apodidae/my-post.md`. For a post with child routes, make the root a branch bundle so category pages show only the root entry:

```text
content/Oleander/A_Comic/
├── _index.md  # /Oleander/A_Comic/
├── 01.md      # /Oleander/A_Comic/01/
└── 02.md      # /Oleander/A_Comic/02/
```

The `Oleander` section uses a client-side access gate. Because GitHub Pages is static, this is a privacy prompt rather than server-side security: generated page source remains publicly retrievable.
