# soma
Static sites without the noise. A minimal static site generator.

This tool allows users to quickly spin up a static site with minimal fuss and configuration. As this was a learning exercise to understand how static site generators work under the hood, its implementation prioritises simplicity over features.

![Alt text](https://i.imgur.com/8SYyAd3.png)


## Installation

### Dependencies

- **[Odin](https://github.com/odin-lang/odin)** - The language and build system
- **[md4c](https://github.com/mity/md4c)** - C library for Markdown parsing

### macOS / Linux

The build script will move the `soma` binary to  `~/.local/bin/soma` after building. Make sure that this is on your path. 

```bash
# Build
./build.sh

# Verify
soma --help
```

### Windows (untested)

```powershell
# Build
odin build . -out:soma.exe

# Move binary to a directory on your PATH (run as Administrator)
move soma.exe C:\Windows\System32\soma.exe

# Verify
soma --help
```

> **Note:** On macOS/Linux you can confirm the binary is found with `which soma`. On Windows use `where soma`.

## Quickstart

Running the following commands will spin up a default soma site ready to deploy.

```
# Choose your site directory
soma init

# Navigate to new site
cd new-soma

# Build the site
soma build

# Serve. Optionally with `-dev` for live reload
soma serve
```

## Features
Any folders added are recognised as categories, and content placed therin automatically processed as long as a few basic rules are followed.

1. The root dir of the project contains an index.md. This is your landing page. You are free to add additional pages such as about.md within this dir.

2. Category folders (placed within the root dir) contain an index.md which serve as the index page for the category and will collate all items for that category (accessible in items as seen in the template).

3. Each markdownfile contains a title, template and some content. Other frontmatter such as Tags and Categories can be added and accessed in the templates.

### Example folder layout

Below is an example of what your layout should look like before building.

```
new-soma/
├── assets/
│   ├── css/
│   │   ├── site.css
│   │   └── syntax.css
│   └── fonts/
│       ├── cmunbi.otf
│       ├── cmunbx.otf
│       ├── cmumm.otf
│       └── cmunti.otf
├── blog/
│   ├── first-post.md
│   └── index.md
├── build/
├── projects/
│   ├── cool-project.md
│   └── index.md
├── templates/
│   ├── base.html
│   ├── category.html
│   ├── content.html
│   └── default.html
├── about.md
└── index.md
```

### Template example

Below is an example of a customised template to extract frontmatter fields such as tags.

```
{% extends "base.html" %}
{% block content %}

<h1>{{ title }}</h1>
{{ content | safe }}

<div class="projects">
    {% for item in items %}
    <div class="project" style="margin-bottom: 1rem;">
        <a class="project-title" href="{{ item.url }}">{{ item.title }}</a>

    {% if item.description %}
    <div class="project-description">{{ item.description }}</div>
    {% endif %}

    {% if item.tags %}
    <div class="project-tags">
        {% for tag in item.tags %}
        <span class="tag">#{{ tag }}</span>
        {% endfor %}
    </div>
    {% endif %}
</div>
{% endfor %}

{% endblock %}
```

## Coming soon
- Search & pagination
- Commands `new category` & `new item`
- Support for themes
