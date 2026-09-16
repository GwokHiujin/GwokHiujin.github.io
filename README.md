# Gwok Hiujin's Hugo blog

This repository publishes [gwokhiujin.github.io](https://gwokhiujin.github.io/) with [Hugo](https://gohugo.io/) and the [GwokHiujin/shibui](https://github.com/GwokHiujin/shibui) theme.

## Local development

```sh
git submodule update --init --recursive
hugo server -D
```

The GitHub Actions workflow installs the pinned Hugo version, builds the site, and deploys `public/` to GitHub Pages.

## Content layout

Public posts belong under either of these top-level sections:

```text
content/
├── Apodidae/
└── Taoasis/
```

Add a normal post as `content/Apodidae/my-post.md`. For a post with child routes, make the root a branch bundle so category pages show only the root entry:

```text
content/Apodidae/A_Comic/
├── _index.md  # /Apodidae/A_Comic/
├── 01.md      # /Apodidae/A_Comic/01/
└── 02.md      # /Apodidae/A_Comic/02/
```

## Encrypted Oleander section

Oleander source and rendered HTML live outside this public repository in the sibling `Oleander` directory:

```text
BlogPage/
├── GwokHiujin.github.io/       # public repository
└── Oleander/                   # private local files
    ├── .password               # local password; never committed
    ├── content/Oleander/       # private Hugo Markdown
    └── html/                   # private rendered HTML
```

After editing private content, rebuild the encrypted pages from the public repository root:

```powershell
.\scripts\build-oleander.ps1
```

The script builds Oleander locally, embeds the generated Shibui stylesheets into each readable page, keeps that readable HTML under `..\Oleander\html`, and writes only AES-256-GCM ciphertext wrappers to `protected/Oleander`. Large private assets are encrypted separately and split into repository-safe chunks. Commit the encrypted output together with the source changes. GitHub Actions builds the public Hugo content and then adds those encrypted files to the Pages artifact.

Use the `encrypted-pdf` shortcode for private PDF page resources. Other private images or downloads must not be placed under this repository's `static` directory unless the encryption pipeline is extended to load them.

This protects the plaintext from casual repository and page-source inspection, but a five-letter password still has low entropy and can be brute-forced offline. Use a longer password if stronger confidentiality is needed.
